"""Bended mesh -> skinned convex collision pieces in rest pose.

Per mesh:
  1. read the GLB (game space, per-vertex bone weights, bone rest positions from the skin)
  2. simplify by vertex clustering, then give each triangle to the slice (between two bones) holding
     its centre - no cut points, so every piece vertex is a mesh vertex the game skins like the render
  3. per slice, near-coplanar connected polygons form patches, each thickened inward into a slab
     (clamped by the surface behind it, an underside never past the surface above it; double-sided
     sheets keep only their upward copy)
  4. merge neighbouring slabs cheapest first while the merged hull stays within TOL of the union,
     then keep merging up to TOL_MAX until the slice fits SLICE_BUDGET, never adding more than
     TOL_TOP over a walkable top (an upward surface with CLEARANCE free height above it)
  5. drop hull vertices that barely move the hull (1.5 cm on upward faces), then pieces covered by the others
Hull vertices keep their bone weights (top two per vertex in the output).
"""
import heapq, math
import numpy as np
from scipy.spatial import ConvexHull, QhullError
from glb import load

TOL = 0.05          # max gap the merged hull may add (m)
THICK = 0.3         # slab thickness behind a surface (m)
MIN_THICK = 0.03
MAX_SLICE = 6.0     # longest slice along the rig axis (m)
GAP = 0.15          # pieces this close may merge across a gap in stage 2 (m)
ADJ = 0.02          # pieces closer than this are merge candidates (m)
MIN_EXTENT = 0.08   # pieces smaller than this in every direction are dropped (m)
TOL_TOP = 0.10      # tolerance over walkable tops allowed to meet the piece budget (m)
TOL_MAX = 0.25      # tolerance allowed to meet the piece budget (m)
SLICE_BUDGET = 12   # pieces per slice before the tolerance grows
CLUSTER = 0.04     # vertex clustering cell before decomposition (m)
MAX_TRIS = 8000     # the cell grows until the simplified mesh is below this
MIN_AREA = 0.01     # patches smaller than this (m2) add no slab
END_CAP_COS = 0.9   # faces this square to the rig axis, in a mesh's end plane, are seams with the next mesh
END_CAP_DIST = 0.02


def to_game(p):
    return np.stack([p[:, 0], -p[:, 2], p[:, 1]], 1)


def read_mesh(path):
    g = load(path)
    gl = g["gltf"]
    skins = gl.get("skins") or []
    if not skins:
        return None
    joints = skins[0]["joints"]
    nb = len(joints)
    # bone rest positions (game space) from the inverse bind matrices
    bones = None
    if skins[0].get("inverseBindMatrices") is not None:
        ibm = g["acc"](skins[0]["inverseBindMatrices"]).reshape(-1, 4, 4)
        bind = np.linalg.inv(np.transpose(ibm, (0, 2, 1)))   # glTF is column-major
        bones = to_game(bind[:, :3, 3])
    pos_all, tri_all, w_all, chunk_all = [], [], [], []
    base = 0
    for ci, m in enumerate(g["meshes"]):
        for p in m["prims"]:
            if p["idx"] is None:
                continue
            pos = to_game(p["pos"])
            W = np.zeros((len(pos), nb))
            for jk, wk in (("JOINTS_0", "WEIGHTS_0"), ("JOINTS_1", "WEIGHTS_1")):
                if jk in p:
                    J, Wt = p[jk], p[wk]
                    for c in range(J.shape[1]):
                        np.add.at(W, (np.arange(len(pos)), J[:, c]), Wt[:, c])
            s = W.sum(1, keepdims=True)
            W = np.where(s > 1e-9, W / np.maximum(s, 1e-9), 0)
            pos_all.append(pos)
            w_all.append(W)
            tri_all.append(p["idx"] + base)
            chunk_all.append(np.full(len(p["idx"]), ci))
            base += len(pos)
    if not pos_all:
        return None
    return {"pos": np.concatenate(pos_all), "w": np.concatenate(w_all), "tris": np.concatenate(tri_all),
            "chunk": np.concatenate(chunk_all), "nbones": nb, "bones": bones, "names": [gl["nodes"][j].get("name") for j in joints]}


def poly_normal(pts):
    n = np.zeros(3)
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n += np.cross(a, b)
    l = np.linalg.norm(n)
    return (n / l, l / 2) if l > 1e-12 else (None, 0)


def ray_depth(origins, dirs, tri_pts, tri_n, chunk=96, t_min=0.005):
    """Distance along dir to the nearest triangle facing the ray (back surface), or inf."""
    res = np.full(len(origins), np.inf)
    if len(tri_pts) == 0:
        return res
    v0 = tri_pts[:, 0]
    e1, e2 = tri_pts[:, 1] - v0, tri_pts[:, 2] - v0
    for c in range(0, len(origins), chunk):
        o, d = origins[c:c + chunk, None, :], dirs[c:c + chunk, None, :]
        h = np.cross(d, e2[None])
        a = (e1[None] * h).sum(2)
        ok = np.abs(a) > 1e-12
        f = np.where(ok, 1 / np.where(ok, a, 1), 0)
        s = o - v0[None]
        u = f * (s * h).sum(2)
        q = np.cross(s, e1[None])
        v = f * (q * d).sum(2)
        t = f * (e2[None] * q).sum(2)
        facing = (d[:, 0] @ tri_n.T) > 0.2   # back surface: its normal points along the ray
        hit = ok & (u >= -1e-4) & (v >= -1e-4) & (u + v <= 1 + 1e-4) & (t > t_min) & facing
        res[c:c + chunk] = np.where(hit, t, np.inf).min(1)
    return res


class Piece:
    __slots__ = ("pts", "w", "hull", "lo", "hi", "chunks", "area", "nsum")

    def __init__(self, pts, w, chunks, area, nsum, lo, hi):
        self.pts, self.w, self.chunks, self.area, self.nsum, self.lo, self.hi = pts, w, chunks, area, nsum, lo, hi
        try:
            h = ConvexHull(pts)
            keep = h.vertices
            if len(keep) < len(pts):
                self.pts, self.w = pts[keep], w[keep]
                h = ConvexHull(self.pts)
            self.hull = h
        except (QhullError, ValueError):
            self.hull = None


BARY = np.array([(1 / 3, 1 / 3), (2 / 3, 1 / 6), (1 / 6, 2 / 3), (1 / 6, 1 / 6), (0.5, 0.5), (0.5, 0), (0, 0.5)])


def face_samples(h):
    tri = h.points[h.simplices]                       # F,3,3
    a, ab, ac = tri[:, 0], tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]
    s = a[:, None] + ab[:, None] * BARY[None, :, :1] + ac[:, None] * BARY[None, :, 1:]
    return s.reshape(-1, 3)


def outside_dist(h, p):
    e = h.equations
    return np.max(p @ e[:, :3].T + e[:, 3], axis=1)


COLMAP = None   # column map of the slice being decomposed (see build_colmap)
CLEARANCE = 1.5     # an upward surface with this much free height above it is walkable (m)


def build_colmap(tri_pts, tri_n, cell=0.2):
    """Per xy cell, every render surface height (rest pose) and which upward ones are walkable."""
    if len(tri_pts) == 0:
        return None
    lo = tri_pts[:, :, :2].reshape(-1, 2).min(0)
    hi = tri_pts[:, :, :2].reshape(-1, 2).max(0)
    nx, ny = (np.floor((hi - lo) / cell).astype(int) + 1)
    ci, zs, ups = [], [], []
    for t, n in zip(tri_pts, tri_n):
        a, b, c = t
        up = n[2] > 0.3
        # vertices mark their own cells (steep and sliver triangles)
        vij = np.floor((t[:, :2] - lo) / cell).astype(int)
        ci.append(vij[:, 0] * ny + vij[:, 1])
        zs.append(t[:, 2])
        ups.append(np.full(3, up))
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-6:
            continue
        tlo = np.floor((t[:, :2].min(0) - lo) / cell).astype(int)
        thi = np.floor((t[:, :2].max(0) - lo) / cell).astype(int)
        gx, gy = np.meshgrid(np.arange(tlo[0], thi[0] + 1), np.arange(tlo[1], thi[1] + 1), indexing="ij")
        px = lo[0] + (gx + 0.5) * cell
        py = lo[1] + (gy + 0.5) * cell
        l1 = ((b[1] - c[1]) * (px - c[0]) + (c[0] - b[0]) * (py - c[1])) / d
        l2 = ((c[1] - a[1]) * (px - c[0]) + (a[0] - c[0]) * (py - c[1])) / d
        l3 = 1 - l1 - l2
        inside = (l1 >= -1e-3) & (l2 >= -1e-3) & (l3 >= -1e-3)
        if not inside.any():
            continue
        z = np.clip(l1 * a[2] + l2 * b[2] + l3 * c[2], t[:, 2].min(), t[:, 2].max())
        ci.append(gx[inside] * ny + gy[inside])
        zs.append(z[inside])
        ups.append(np.full(int(inside.sum()), up))
    ci, zs, ups = np.concatenate(ci), np.concatenate(zs), np.concatenate(ups)
    order = np.lexsort((zs, ci))
    ci, zs, ups = ci[order], zs[order], ups[order]
    starts = np.searchsorted(ci, np.arange(nx * ny), "left")
    ends = np.searchsorted(ci, np.arange(nx * ny), "right")
    width = int((ends - starts).max())
    heights = np.full((nx * ny, width), np.nan)
    walk = np.full((nx * ny, width), np.nan)
    for cell_id in np.nonzero(ends > starts)[0]:
        s, e = starts[cell_id], ends[cell_id]
        z, u = zs[s:e], ups[s:e]
        heights[cell_id, :e - s] = z
        # free height above each surface: next surface more than 2 cm higher
        nxt = np.searchsorted(z, z + 0.02, "right")
        free = np.where(nxt < len(z), z[np.minimum(nxt, len(z) - 1)] - z, np.inf)
        w = z[u & (free >= CLEARANCE)]
        walk[cell_id, :len(w)] = w
    return lo, cell, ny, heights, walk


def _cells(points):
    lo, cell, ny, heights, walk = COLMAP
    ij = np.floor((points[:, :2] - lo) / cell).astype(int)
    nx = heights.shape[0] // ny
    ok = (ij[:, 0] >= 0) & (ij[:, 1] >= 0) & (ij[:, 0] < nx) & (ij[:, 1] < ny)
    return ok, ij[:, 0] * ny + ij[:, 1]


def surface_above(points):
    """Nearest render surface above each point (inf when none)."""
    out = np.full(len(points), np.inf)
    if COLMAP is None:
        return out
    ok, cid = _cells(points)
    h = COLMAP[3][cid[ok]]
    z = points[ok, 2][:, None]
    with np.errstate(invalid="ignore"):
        above = np.where(h > z + 0.02, h, np.inf)
    out[ok] = above.min(1)
    return out


def exposed(points):
    """Points in the free space just above a walkable surface (within CLEARANCE)."""
    if COLMAP is None:
        return np.ones(len(points), bool)
    out = np.zeros(len(points), bool)
    ok, cid = _cells(points)
    w = COLMAP[4][cid[ok]]
    z = points[ok, 2][:, None]
    with np.errstate(invalid="ignore"):
        out[ok] = ((z >= w - 0.05) & (z <= w + CLEARANCE)).any(1)
    return out


def over_walk(points):
    """Height of each point above the highest walkable surface just below it (-inf when none)."""
    out = np.full(len(points), -np.inf)
    if COLMAP is None:
        return out
    ok, cid = _cells(points)
    w = COLMAP[4][cid[ok]]
    z = points[ok, 2]
    with np.errstate(invalid="ignore"):
        best = np.where(w <= z[:, None] + 0.05, w, -np.inf).max(1)
    out[ok] = np.where(np.isfinite(best), z - best, -np.inf)
    return out


def overhangs_walk(piece):
    """Whether the piece's hull tops rise more than TOL into the free space above a walkable surface:
    the hull of a non-convex patch (an end cap with curbs, a wall with a notch) fills its concavities."""
    h = piece.hull
    if h is None or COLMAP is None:
        return False
    top = h.equations[:, 2] > 0.3
    if not top.any():
        return False
    smp = face_samples(h)[np.repeat(top, len(BARY))]
    over = over_walk(smp)
    return bool(np.any((over > TOL) & (over <= CLEARANCE)))


def merge_cost(A, B, top_limit=None):
    if A.hull is None or B.hull is None:
        return math.inf
    try:
        h = ConvexHull(np.concatenate([A.pts, B.pts]))
    except (QhullError, ValueError):
        return math.inf
    smp = face_samples(h)
    dev = np.minimum(outside_dist(A.hull, smp), outside_dist(B.hull, smp))
    # material added over upward faces (walkable tops) is never allowed beyond TOL
    top = np.repeat(h.equations[:, 2] > 0.3, len(BARY))
    if top_limit and top_limit > TOL and top.any():
        top &= exposed(smp)
    if top.any() and dev[top].max() > (top_limit or TOL):
        return math.inf
    return float(dev.max())


def near(A, B, eps=ADJ):
    return bool(np.all(A.lo <= B.hi + eps) and np.all(B.lo <= A.hi + eps))


COPLANAR_COS = math.cos(math.radians(8))
COPLANAR_DIST = 0.01


def coplanar_patches(polys):
    """Group polygons into connected near-coplanar patches (shared vertices, same plane)."""
    keys = []
    owner = {}
    for i, (pts, _, _, _, _) in enumerate(polys):
        ks = [tuple(np.round(p / 0.002).astype(np.int64)) for p in pts]
        keys.append(ks)
        for k in ks:
            owner.setdefault(k, []).append(i)
    seen = [False] * len(polys)
    patches = []
    for s in range(len(polys)):
        if seen[s]:
            continue
        n0 = polys[s][4]
        d0 = float(n0 @ polys[s][0][0])
        group, stack = [s], [s]
        seen[s] = True
        while stack:
            i = stack.pop()
            for k in keys[i]:
                for j in owner[k]:
                    if seen[j]:
                        continue
                    pj, _, _, _, nj = polys[j]
                    if nj @ n0 >= COPLANAR_COS and np.abs(pj @ n0 - d0).max() <= COPLANAR_DIST:
                        seen[j] = True
                        group.append(j)
                        stack.append(j)
        patches.append(group)
    patch_of = {}
    for pi, group in enumerate(patches):
        for i in group:
            patch_of[i] = pi
    adjacency = [set() for _ in patches]
    for owners in owner.values():
        ps = {patch_of[i] for i in owners}
        if len(ps) > 1:
            for p in ps:
                adjacency[p] |= ps - {p}
    return patches, adjacency


def merge_pieces(A, B):
    chunks = dict(A.chunks)
    for k, v in B.chunks.items():
        chunks[k] = chunks.get(k, 0) + v
    return Piece(np.concatenate([A.pts, B.pts]), np.concatenate([A.w, B.w]), chunks, A.area + B.area,
                 A.nsum + B.nsum, np.minimum(A.lo, B.lo), np.maximum(A.hi, B.hi))


def agglomerate(alive, links, budget=None):
    """Greedy cheapest-first merging along the links graph while the merged hull stays within TOL,
    then (with a budget) up to TOL_MAX until no more than `budget` pieces remain."""
    limit = TOL_MAX if budget else TOL
    top_limit = TOL_TOP if budget else TOL
    alive, links = dict(alive), {k: set(v) for k, v in links.items()}
    nxt = max(alive) + 1 if alive else 0
    heap = []
    for a, ns in links.items():
        for b in ns:
            if a < b:
                c = merge_cost(alive[a], alive[b], top_limit)
                if c <= limit:
                    heapq.heappush(heap, (c, a, b))
    while heap:
        c, a, b = heapq.heappop(heap)
        if a not in alive or b not in alive:
            continue
        if c > TOL and len(alive) <= budget:
            break
        M = merge_pieces(alive.pop(a), alive.pop(b))
        ns = (links.pop(a) | links.pop(b)) - {a, b}
        idn = nxt
        nxt += 1
        for k in ns:
            links[k].discard(a)
            links[k].discard(b)
            links[k].add(idn)
            c2 = merge_cost(M, alive[k], top_limit)
            if c2 <= limit:
                heapq.heappush(heap, (c2, k, idn))
        alive[idn], links[idn] = M, ns
    return alive


def split_overhangs(pieces, links, patches, valid, slab):
    """Replaces each patch slab overhanging a walkable surface by one slab per polygon, linked to the
    polygons it shares a vertex with and to the patch's neighbours; stage 1 merges back what TOL allows."""
    nxt = len(patches)
    for pi in [p for p in pieces if len(patches[p]) > 1 and overhangs_walk(pieces[p])]:
        n, t = slab[pi]
        ids, owner = [], {}
        for i in patches[pi]:
            pts, w, ch, area, _ = valid[i]
            pieces[nxt] = Piece(np.concatenate([pts, pts - n * t]), np.concatenate([w, w]), {ch: area}, area,
                                n * area, pts.min(0), pts.max(0))
            for p in pts:
                owner.setdefault(tuple(np.round(p / 0.002).astype(np.int64)), []).append(nxt)
            ids.append(nxt)
            nxt += 1
        neighbours = links.pop(pi)
        del pieces[pi]
        for k in neighbours:
            links[k].discard(pi)
            links[k].update(ids)
        for i in ids:
            links[i] = set(neighbours)
        for shared in owner.values():
            for i in shared:
                links[i].update(j for j in shared if j != i)


def decompose_slice(polys, tri_pts_slice, tri_n_slice):
    """polys: list of (points[k,3], weights[k,nb], chunk). Returns merged pieces."""
    valid = []
    for pts, w, ch in polys:
        n, area = poly_normal(pts)
        if n is not None:
            valid.append((pts, w, ch, area, n))
    if not valid:
        return []
    cents, inward = np.array([v[0].mean(0) for v in valid]), -np.array([v[4] for v in valid])
    depth = ray_depth(cents, inward, tri_pts_slice, tri_n_slice)
    thick = np.where(np.isfinite(depth), np.clip(depth, MIN_THICK, THICK), THICK)
    # double-sided sheets: a coincident face behind with the opposite normal
    twin = ray_depth(cents - inward * 0.005, inward, tri_pts_slice, tri_n_slice, t_min=0.0) < 0.012
    keep = []
    for i, v in enumerate(valid):
        if twin[i]:
            if v[4][2] < -0.3:
                continue                       # the upward twin carries the slab
            if v[4][2] <= 0.3:
                thick[i] = MIN_THICK           # vertical sheet: thin on both sides
        keep.append(i)
    valid, thick = [valid[i] for i in keep], thick[keep]
    if not valid:
        return []

    global COLMAP
    COLMAP = build_colmap(tri_pts_slice, tri_n_slice)
    patches, adjacency = coplanar_patches(valid)
    pieces, links, slab = {}, {}, {}
    for pi, group in enumerate(patches):
        if sum(valid[i][3] for i in group) < MIN_AREA:
            continue
        pts = np.concatenate([valid[i][0] for i in group])
        w = np.concatenate([valid[i][1] for i in group])
        nsum = sum(valid[i][4] * valid[i][3] for i in group)
        area = sum(valid[i][3] for i in group)
        n = nsum / max(np.linalg.norm(nsum), 1e-12)
        t = float(np.median([thick[i] for i in group]))
        if n[2] < -0.3:
            # an underside thickens upward: never past the highest render surface above it
            room = (surface_above(pts) - pts[:, 2]).min() / -n[2]
            t = max(MIN_THICK, min(t, room)) if np.isfinite(room) else MIN_THICK
        chunks = {}
        for i in group:
            chunks[valid[i][2]] = chunks.get(valid[i][2], 0) + valid[i][3]
        pieces[pi] = Piece(np.concatenate([pts, pts - n * t]), np.concatenate([w, w]), chunks, area, nsum,
                           pts.min(0), pts.max(0))
        slab[pi] = (n, t)
    for pi in pieces:
        # neighbours, walking through dropped (tiny) patches
        found, seen, stack = set(), {pi}, list(adjacency[pi])
        while stack:
            q = stack.pop()
            if q in seen:
                continue
            seen.add(q)
            if q in pieces:
                found.add(q)
            else:
                stack.extend(adjacency[q])
        links[pi] = found
    split_overhangs(pieces, links, patches, valid, slab)

    # stage 1: topological neighbours only
    alive = agglomerate(pieces, links)
    # stage 2: every pair of remaining pieces whose surfaces are close
    ids = list(alive)
    links = {i: {j for j in ids if j != i and near(alive[i], alive[j], GAP)} for i in ids}
    alive = agglomerate(alive, links, SLICE_BUDGET)
    out = []
    for p in alive.values():
        if p.hull is None or (p.hi - p.lo).max() < MIN_EXTENT:
            continue
        # vertices of upward faces keep the tight tolerance: lowering a top leaves walkable surface uncovered
        top = np.zeros(len(p.pts), bool)
        top[np.unique(p.hull.simplices[p.hull.equations[:, 2] > 0.3])] = True
        keep = reduce_hull(p.pts, top)
        out.append((p.pts[keep], p.w[keep], p.chunks, p.nsum))
    return out


def reduce_hull(pts, protect, tol_top=0.015, tol=0.05, min_verts=8):
    """Greedy hull vertex removal while the hull moves less than the tolerance (tol_top for protected
    vertices). Returns the kept indices."""
    keep = list(range(len(pts)))
    while len(keep) > min_verts:
        best, best_i = None, None
        for k in range(len(keep)):
            rest = keep[:k] + keep[k + 1:]
            try:
                h = ConvexHull(pts[rest])
            except (QhullError, ValueError):
                continue
            e = h.equations
            d = float(np.max(pts[keep[k]] @ e[:, :3].T + e[:, 3]))
            limit = tol_top if protect[keep[k]] else tol
            if d <= limit and (best is None or d / limit < best):
                best, best_i = d / limit, k
        if best_i is None:
            break
        keep.pop(best_i)
    return keep


def drop_redundant(pieces, tol=0.01):
    """Remove pieces whose every sample lies inside the union of the remaining ones (smallest first)."""
    hulls = []
    for p in pieces:
        try:
            hulls.append(ConvexHull(p["pts"]))
        except (QhullError, ValueError):
            hulls.append(None)
    order = sorted(range(len(pieces)), key=lambda i: hulls[i].volume if hulls[i] is not None else 0)
    alive = set(i for i in range(len(pieces)) if hulls[i] is not None)
    for i in order:
        if i not in alive:
            continue
        h = hulls[i]
        smp = np.concatenate([h.points[h.vertices], face_samples(h)])
        lo, hi = smp.min(0) - tol, smp.max(0) + tol
        best = np.full(len(smp), np.inf)
        for j in alive:
            if j == i:
                continue
            q = hulls[j].points
            if np.any(q.max(0) < lo) or np.any(q.min(0) > hi):
                continue
            best = np.minimum(best, outside_dist(hulls[j], smp))
        if best.max() <= tol:
            alive.discard(i)
    return [pieces[i] for i in sorted(alive)]


def rig_axis(bones):
    first, last = bones[0], bones[-1]
    axis = last - first
    L = np.linalg.norm(axis)
    if L < 1e-6:
        return None
    axis = axis / L
    for b in bones:
        v = b - first
        if np.linalg.norm(v - axis * (v @ axis)) > max(0.01, L * 0.001):
            return None
    return axis


def simplify(pos, W, tris, chunk, cell=CLUSTER):
    """Vertex clustering: one vertex per grid cell (the one nearest the cell centre), degenerate triangles dropped."""
    keys = np.floor(pos / cell).astype(np.int64)
    _, inverse = np.unique(keys, axis=0, return_inverse=True)
    inverse = inverse.reshape(-1)
    centre = (keys + 0.5) * cell
    dist = np.linalg.norm(pos - centre, axis=1)
    order = np.lexsort((dist, inverse))
    first = np.ones(len(order), bool)
    first[1:] = inverse[order][1:] != inverse[order][:-1]
    rep = np.empty(inverse.max() + 1, np.int64)
    rep[inverse[order][first]] = order[first]
    t = rep[inverse[tris]]
    ok = (t[:, 0] != t[:, 1]) & (t[:, 1] != t[:, 2]) & (t[:, 0] != t[:, 2])
    t, chunk = t[ok], chunk[ok]
    srt = np.sort(t, axis=1)
    _, uniq = np.unique(srt, axis=0, return_index=True)
    uniq.sort()
    return t[uniq], chunk[uniq]


def decompose(glb_path, bones):
    """bones: rest positions [n,3] in game space (bone order = skin joint order)."""
    m = read_mesh(glb_path)
    if m is None:
        return None, "no skin"
    bones = np.asarray(bones, float)
    axis = rig_axis(bones)
    if axis is None:
        return None, "non-linear rig"
    s_b = (bones - bones[0]) @ axis
    pos, W = m["pos"], m["w"]
    cell = CLUSTER
    tris, chunks = simplify(pos, W, m["tris"], m["chunk"], cell)
    while len(tris) > MAX_TRIS and cell < 0.5:
        cell *= 1.5
        tris, chunks = simplify(pos, W, m["tris"], m["chunk"], cell)
    s_v = (pos - bones[0]) @ axis
    cuts = []
    for i in range(len(s_b) - 1):
        a, b = sorted((s_b[i], s_b[i + 1]))
        n = max(1, int(math.ceil((b - a) / MAX_SLICE - 1e-6)))
        cuts.extend(a + (b - a) * k / n for k in range(n))
    cuts.append(max(s_b[0], s_b[-1]))
    cuts = sorted(set(round(c, 6) for c in cuts))
    edges = [-math.inf] + cuts[1:-1] + [math.inf] if len(cuts) > 2 else [-math.inf, math.inf]
    # triangle normals for depth queries
    tp = pos[tris]
    tn = np.cross(tp[:, 1] - tp[:, 0], tp[:, 2] - tp[:, 0])
    ln = np.linalg.norm(tn, axis=1)
    good = ln > 1e-12
    tp, tn, tris_g, chunk_g = tp[good], tn[good] / ln[good, None], tris[good], chunks[good]
    t_lo, t_hi = s_v[tris_g].min(1), s_v[tris_g].max(1)
    # whole triangles go to the slice of their centre: pieces only hold real vertices, which the game
    # skins exactly like the render (an inserted cut point would not follow the render's chord)
    t_mid = s_v[tris_g].mean(1)
    # end caps sit between two meshes of a chain, where their hull would ridge the road
    s_min, s_max = s_v[tris_g].min(), s_v[tris_g].max()
    cap = (np.abs(tn @ axis) > END_CAP_COS) & ((t_hi - s_min < END_CAP_DIST) | (s_max - t_lo < END_CAP_DIST))
    result = []
    for k in range(len(edges) - 1):
        lo, hi = edges[k], edges[k + 1]
        sel = np.nonzero((t_mid >= lo) & (t_mid < hi) & ~cap)[0]
        polys = [(pos[tris_g[ti]], W[tris_g[ti]], int(chunk_g[ti])) for ti in sel]
        if not polys:
            continue
        # back-surface query set: the slice's triangles (slightly widened)
        selw = np.nonzero((t_hi > lo - 0.5) & (t_lo < hi + 0.5))[0]
        for pts, w, ch, nsum in decompose_slice(polys, tp[selw], tn[selw]):
            result.append({"slice": k, "pts": pts, "w": w, "chunks": ch, "nsum": nsum})
    result = drop_redundant(result)
    return {"pieces": result, "nbones": m["nbones"], "axis": axis, "cuts": cuts, "tris": len(tris_g)}, None
