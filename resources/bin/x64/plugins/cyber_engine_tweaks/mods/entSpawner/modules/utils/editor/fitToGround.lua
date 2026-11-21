local tiledNavigation = require("modules/utils/editor/tiledNavigation")

local fitToGround = {}

local radius, height, climb = .3, 1.8, .6
local slope = math.rad(35)
local maxSlope, minNormal = math.tan(slope), math.cos(slope)
local spacing, tileSize = .5, 32.4
local offsets = { {radius, 0}, {-radius, 0}, {0, radius}, {0, -radius} }

local function ground(cast, x, y, z)
    local hit = cast(x, y, z + 1.5, z - 2)
    if not hit or not hit:IsValid() or hit.normal.z < minNormal then return nil end
    local floor = hit.position.z
    local ceiling = cast(x, y, floor + .08, floor + height)
    if ceiling and ceiling:IsValid() then return nil end
    return floor
end

local function supported(cast, x, y, z)
    for _, offset in ipairs(offsets) do
        local neighbor = ground(cast, x + offset[1], y + offset[2], z)
        if not neighbor or math.abs(neighbor - z) > radius * maxSlope + .03 then return false end
    end
    return true
end

function fitToGround.capture(interface, x, y, z, width, depth, layer, yaw, shape)
    if not interface then return nil, "Load a save, move V and let collision stream in." end
    if width < 2 or width > 96 or depth < 2 or depth > 96 then
        return nil, "Use a footprint between 2 and 96 metres on each axis."
    end
    local angle = math.rad(yaw or 0)
    local c, s = math.cos(angle), math.sin(angle)
    local extentX = (math.abs(c) * width + math.abs(s) * depth) / 2
    local extentY = (math.abs(s) * width + math.abs(c) * depth) / 2
    local function cast(sx, sy, fromZ, toZ)
        return interface:RaycastWithASingleGroup(
            Vector4.new(sx, sy, fromZ, 1), Vector4.new(sx, sy, toZ, 1), "PlayerBlocker")
    end

    if width > 16 or depth > 16
        or math.floor((x - extentX) / tileSize) ~= math.floor((x + extentX) / tileSize)
        or math.floor((y - extentY) / tileSize) ~= math.floor((y + extentY) / tileSize) then
        return tiledNavigation.capture({
            version = 2, anchor = {x, y, z}, footprint = {width, depth},
            yaw = yaw or 0, shape = shape or 0, layer = layer
        }, function(sx, sy, checkSupport)
            local floor = ground(cast, sx, sy, z)
            if floor and (not checkSupport or supported(cast, sx, sy, floor)) then return floor end
        end)
    end

    local nx = math.ceil((width - 2 * radius) / spacing)
    local ny = math.ceil((depth - 2 * radius) / spacing)
    local dx, dy = (width - 2 * radius) / nx, (depth - 2 * radius) / ny
    local samples, vertexIds, cells = {}, {}, {}
    local surface = {
        version = 1,
        anchor = {x, y, z},
        footprint = {width, depth},
        yaw = yaw or 0,
        shape = shape or 0,
        layer = layer,
        vertices = {},
        faces = {}
    }
    -- Use a half-cell grid so corners, edge midpoints and centres share probes.
    local function sample(ix, iy)
        local k = iy * (2 * nx + 1) + ix
        if samples[k] == nil then
            local u, v = -width / 2 + radius + ix * dx / 2, -depth / 2 + radius + iy * dy / 2
            local sx, sy = x + c * u - s * v, y + s * u + c * v
            local inFootprint = shape ~= 1 or (u / (width / 2 - radius))^2 + (v / (depth / 2 - radius))^2 <= 1
            local sz = inFootprint and ground(cast, sx, sy, z)
            if sz and (ix % 2 ~= 0 or iy % 2 ~= 0 or supported(cast, sx, sy, sz)) then
                samples[k] = {sx, sy, sz}
            else
                samples[k] = false
            end
        end
        return samples[k], k
    end
    local function vertex(ix, iy)
        local point, key = sample(ix, iy)
        if vertexIds[key] == nil then
            vertexIds[key] = #surface.vertices -- Zero-based indices in the interchange file.
            surface.vertices[#surface.vertices+1] = point
        end
        return vertexIds[key]
    end
    local function edgeOK(a, b, mid, length)
        return mid and math.abs(a[3] - b[3]) <= math.min(climb, maxSlope * length)
            and math.abs(mid[3] - (a[3] + b[3]) / 2) <= .12
    end
    local function gradientOK(x0, x1, y0, y1)
        return ((x0[3] - x1[3]) / dx)^2 + ((y0[3] - y1[3]) / dy)^2 <= maxSlope^2
    end
    for iy = 0, ny - 1 do
        cells[iy + 1] = {}
        for ix = 0, nx - 1 do
            local u, v = ix * 2, iy * 2
            local a, b, c, d = sample(u, v), sample(u, v + 2), sample(u + 2, v), sample(u + 2, v + 2)
            local middle = sample(u + 1, v + 1)
            local valid = a and b and c and d
                and edgeOK(a, b, sample(u, v + 1), dy) and edgeOK(a, c, sample(u + 1, v), dx)
                and edgeOK(b, d, sample(u + 1, v + 2), dx) and edgeOK(c, d, sample(u + 2, v + 1), dy)
                and edgeOK(b, c, middle, math.sqrt(dx*dx + dy*dy))
            if valid then
                valid = gradientOK(a, c, a, b) and gradientOK(b, d, c, d)
            end
            if valid then
                local ia, ib, ic, id = vertex(u, v), vertex(u, v + 2), vertex(u + 2, v), vertex(u + 2, v + 2)
                surface.faces[#surface.faces + 1] = {ia, ib, ic}
                surface.faces[#surface.faces + 1] = {ic, ib, id}
                cells[iy + 1][ix + 1] = middle[3]
            else
                cells[iy + 1][ix + 1] = false
            end
        end
    end
    return { cells = cells, nx = nx, ny = ny, anchorZ = z, surface = surface }
end

return fitToGround
