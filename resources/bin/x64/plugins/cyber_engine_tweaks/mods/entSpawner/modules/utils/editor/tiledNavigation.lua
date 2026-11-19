local tiledNavigation = {}

local tileSize, cellsPerTile = 32.4, 24
local step = tileSize / (2 * cellsPerTile)
local maxSlope = math.tan(math.rad(35))
local function portalSide(dx, dy)
    if dx > 0 then return 0 end
    if dy > 0 then return 2 end
    if dx < 0 then return 4 end
    return 6
end
local function key(i, j)
    return i .. ":" .. j
end

function tiledNavigation.capture(surface, sampleGround)
    local x, y = surface.anchor[1], surface.anchor[2]
    local w, h = surface.footprint[1] / 2, surface.footprint[2] / 2
    local angle = math.rad(surface.yaw)
    local c, s = math.cos(angle), math.sin(angle)
    local ex, ey = math.abs(c) * w + math.abs(s) * h, math.abs(s) * w + math.abs(c) * h
    local samples, border = {}, {}
    local function sample(i, j)
        local k = key(i, j)
        if samples[k] == nil then
            local sx, sy = i * step, j * step
            local dx, dy = sx - x, sy - y
            local u, v = (dx * c + dy * s) / (w - .3), (dy * c - dx * s) / (h - .3)
            local inside = math.abs(u) <= 1 and math.abs(v) <= 1
            if surface.shape == 1 then inside = u*u + v*v <= 1 end
            local z = inside and sampleGround(sx, sy, i % 2 == 0 and j % 2 == 0)
            samples[k] = z and {sx, sy, z} or false
        end
        return samples[k]
    end

    local tiles = {}
    for ty = math.floor((y - ey) / tileSize), math.floor((y + ey) / tileSize) do
        for tx = math.floor((x - ex) / tileSize), math.floor((x + ex) / tileSize) do
            local tile = {
                version = 1, coords = {tx, ty}, layer = surface.layer,
                anchor = {(tx + .5) * tileSize, (ty + .5) * tileSize, surface.anchor[3]},
                vertices = {}, faces = {}, portals = {}
            }
            local baseI, baseJ = tx * 2 * cellsPerTile, ty * 2 * cellsPerTile
            local ids = {}
            local function addFace(points, indices, mids)
                local gradientSquared = 0
                for n, point in ipairs(points) do
                    local nextPoint = points[n % 3 + 1]
                    local mx, my = mids[n][1], mids[n][2]
                    local mid = sample(mx, my)
                    if not mid then return end
                    local dx, dy = nextPoint[1] - point[1], nextPoint[2] - point[2]
                    local dz = nextPoint[3] - point[3]
                    if math.abs(dz) > math.min(.6, math.sqrt(dx*dx+dy*dy) * maxSlope)
                        or math.abs(mid[3] - (point[3] + nextPoint[3]) / 2) > .18 then return end
                    if dx == 0 or dy == 0 then gradientSquared = gradientSquared + (dz / (2 * step))^2 end
                end
                if gradientSquared > maxSlope^2 then return end
                local faceIndex, face = #tile.faces, {}
                for n, index in ipairs(indices) do
                    local i, j = index[1], index[2]
                    local k = key(i, j)
                    if ids[k] == nil then
                        ids[k] = #tile.vertices
                        tile.vertices[#tile.vertices + 1] = points[n]
                    end
                    face[n] = ids[k]

                    local other = indices[n % 3 + 1]
                    local ni, nj = other[1], other[2]
                    local verticalBorder = i == ni and (i == baseI or i == baseI + 2 * cellsPerTile)
                    local horizontalBorder = j == nj and (j == baseJ or j == baseJ + 2 * cellsPerTile)
                    if verticalBorder or horizontalBorder then
                        local edge = key(math.min(i, ni), math.min(j, nj)) .. ":" .. (verticalBorder and "v" or "h")
                        local previous = border[edge]
                        if previous then
                            local dx, dy = tx - previous.tile.coords[1], ty - previous.tile.coords[2]
                            table.insert(previous.tile.portals, {previous.face, previous.edge, portalSide(dx, dy)})
                            table.insert(tile.portals, {faceIndex, n - 1, portalSide(-dx, -dy)})
                        else
                            border[edge] = {tile = tile, face = faceIndex, edge = n - 1}
                        end
                    end
                end
                tile.faces[#tile.faces + 1] = face
            end
            for j = baseJ, baseJ + 2 * cellsPerTile - 2, 2 do
                for i = baseI, baseI + 2 * cellsPerTile - 2, 2 do
                    local a, b, c1, d = {i,j},{i,j+2},{i+2,j},{i+2,j+2}
                    local pa, pb = sample(i,j), sample(i,j+2)
                    local pc, pd = sample(i+2,j), sample(i+2,j+2)
                    if pa and pb and pc then
                        addFace({pa,pb,pc}, {a,b,c1}, {{i,j+1},{i+1,j+1},{i+1,j}})
                    end
                    if pc and pb and pd then
                        addFace({pc,pb,pd}, {c1,b,d}, {{i+1,j+1},{i+1,j+2},{i+2,j+1}})
                    end
                end
            end
            if #tile.faces > 0 then tiles[#tiles + 1] = tile end
        end
    end
    for _, tile in ipairs(tiles) do
        if #tile.portals == 0 then tile.portals = nil end
    end
    surface.tiles = tiles
    return {surface = surface}
end

return tiledNavigation
