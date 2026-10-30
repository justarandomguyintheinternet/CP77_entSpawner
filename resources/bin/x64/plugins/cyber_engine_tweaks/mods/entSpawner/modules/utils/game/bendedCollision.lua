local config = require("modules/utils/core/config")
local bendedRig = require("modules/utils/game/bendedRig")

---Collision sources of bended meshes: convex pieces in rest pose with per-vertex bone weights,
---extracted offline into `data/static/bended_collision/`. Deforming them with the node's bone
---matrices gives the convex hull vertices of every piece in node space.
---@class bendedCollision
local collision = {}

local folder = "data/static/bended_collision/"
local index = nil
local loaded = {}

---@class bendedCollisionPiece
---@field class string `ground`, `raised` or `wall`.
---@field slice integer 0-based slice along the rig axis the piece belongs to.
---@field points number[] Flat rest positions `x, y, z, ...` in mesh space.
---@field weights number[] Per point `bone, secondBone, secondWeight` (0-based bones).
---@field faces integer[]? Hull triangles as flat 0-based point indices, counter-clockwise seen from outside.

---@class bendedCollisionSource
---@field bones integer
---@field tolerance number
---@field materials table<string, string> Physics material per class.
---@field pieces bendedCollisionPiece[]

---@class bendedCollisionShape
---@field class string
---@field material string
---@field points { x: number, y: number, z: number }[]
---@field faces integer[]? Same as the piece's.

---@return table<string, string>
local function getIndex()
    if not index then
        local data = config.loadFile(folder .. "index.json")
        index = type(data) == "table" and data or {}
    end
    return index
end

---Collision source of a mesh, or nil when the mesh has none.
---@param path string?
---@return bendedCollisionSource?
function collision.get(path)
    if not path or path == "" then return nil end

    local key = string.lower(path)
    local known = loaded[key]
    if known ~= nil then
        return known or nil
    end

    local name = getIndex()[key]
    local source = name and config.loadFile(folder .. name .. ".json") or nil
    if type(source) ~= "table" or type(source.pieces) ~= "table" or #source.pieces == 0 then
        source = nil
    end

    loaded[key] = source or false
    return source
end

---Skinning matrices (`inverseBind * deformation`) of every bone, as flat row-major matrices.
---@param rigData bendedRigData
---@param deformation table[] Per bone `{ X, Y, Z, W }` rows (Vector4 or `{ x, y, z, w }`).
---@return table[]
function collision.getSkinMatrices(rigData, deformation)
    local skin = {}
    for bone, inverseBind in ipairs(rigData.inverseBind) do
        local d = deformation[bone]
        if not d then break end
        skin[bone] = bendedRig.mul(inverseBind, {
            d.X.x, d.X.y, d.X.z, 0,
            d.Y.x, d.Y.y, d.Y.z, 0,
            d.Z.x, d.Z.y, d.Z.z, 0,
            d.W.x, d.W.y, d.W.z, 1
        })
    end
    return skin
end

---@param m table
---@param x number
---@param y number
---@param z number
---@return number, number, number
local function transform(m, x, y, z)
    return x * m[1] + y * m[5] + z * m[9] + m[13],
        x * m[2] + y * m[6] + z * m[10] + m[14],
        x * m[3] + y * m[7] + z * m[11] + m[15]
end

---Deformed convex pieces in node space, or nil when the skin does not cover the source's bones.
---@param source bendedCollisionSource
---@param skin table[] From `getSkinMatrices`.
---@return bendedCollisionShape[]?
function collision.deform(source, skin)
    if #skin < source.bones then return nil end

    local shapes = {}
    for _, piece in ipairs(source.pieces) do
        local points = {}
        local p, w = piece.points, piece.weights

        for i = 1, #p / 3 do
            local x, y, z = p[i * 3 - 2], p[i * 3 - 1], p[i * 3]
            local b0, b1, w1 = w[i * 3 - 2], w[i * 3 - 1], w[i * 3]
            local ax, ay, az = transform(skin[b0 + 1], x, y, z)

            if w1 > 0 and b1 ~= b0 then
                local bx, by, bz = transform(skin[b1 + 1], x, y, z)
                local w0 = 1 - w1
                ax, ay, az = ax * w0 + bx * w1, ay * w0 + by * w1, az * w0 + bz * w1
            end

            points[i] = { x = ax, y = ay, z = az }
        end

        shapes[#shapes + 1] = {
            class = piece.class,
            material = source.materials and source.materials[piece.class] or "concrete.physmat",
            points = points,
            faces = piece.faces
        }
    end

    return shapes
end

return collision
