local builder = require("modules/utils/game/entityBuilder")
local logger = require("modules/utils/core/logger")
local bendedPool = require("modules/utils/preview/bendedPool")

---Live collision of bended meshes in the editor: one host entity per mesh carrying convex colliders,
---cooked by the engine from their vertices. Colliders only take effect when added during assembly,
---so a changed shape respawns the host. It is removed as soon as the shape changes and rebuilt once
---the shape has been stable for `settleTime` with the mouse released, so editor tools that raycast
---(surface snap, drape) never hit the mesh's own outdated collision.
---The pieces can also be shown as a hologram through the bended preview pool: one placeholder per
---`trianglesPerMesh` hull triangles, each bone of the preview mesh carrying one triangle.
---@class bendedCollisionPreview
local preview = {}

local hostTemplate = "base\\spawner\\empty_entity.ent"
local settleTime = 0.3
local collidersPerComponent = 64
local trianglesPerMesh = 251
local visualMeshPrefix = "base\\spawner\\bended_collision_"
local visualColours = { "red", "green", "blue" }
-- The hologram meshes ship with a 1 m box, which the renderer hides past a few dozen meters.
local visualBoundsExtent = 500

---@class bendedCollisionRecord
---@field owner table Spawnable providing `getCollisionShapes()`, `position` and `rotation`.
---@field signature string?
---@field changedAt number Clock of the last signature change.
---@field entityID entEntityID?
---@field built boolean The current signature has a host (or failed to get one).
---@field removedTick integer? Update tick of the last host removal.
---@field count integer Convex pieces on the current host.
---@field issue string? Why the owner has no collision.
---@field shapes bendedCollisionShape[]? Pieces of the current host, in the owner's local space.
---@field position { x: number, y: number, z: number }? Owner transform the shapes were built with.
---@field quat Quaternion?
---@field colour string? Hologram colour, nil when hidden.
---@field parts table[] Pool owners of the hologram, one per placeholder.

local records = {}
local clock = 0
local tick = 0
local mouseDown = false
local waiting = {}
---Held so the widened hologram meshes stay loaded.
local visualTokens = {}
local visualBoundsReady = false

---Widens the bounds of the hologram meshes once they are loaded.
---@return boolean done
local function widenVisualBounds()
    local ok, done = pcall(function()
        local depot = Game.GetResourceDepot and Game.GetResourceDepot()
        if not depot then return false end

        local done = true
        for _, colour in ipairs(visualColours) do
            local token = visualTokens[colour]
            if not token then
                token = depot:LoadResource(ResRef.FromString(visualMeshPrefix .. colour .. ".mesh"))
                visualTokens[colour] = token
            end

            if token:IsLoaded() then
                local box = Box.new()
                box.Min = Vector4.new(-visualBoundsExtent, -visualBoundsExtent, -visualBoundsExtent, 1)
                box.Max = Vector4.new(visualBoundsExtent, visualBoundsExtent, visualBoundsExtent, 1)
                token:GetResource().boundingBox = box
            elseif not token:IsFailed() then
                done = false
            end
        end
        return done
    end)

    if not ok then
        logger:warn("Bended collision hologram bounds: " .. tostring(done))
        return true
    end
    return done
end

---@param owner table
---@return bendedCollisionRecord
local function getRecord(owner)
    local record = records[owner]
    if not record then
        record = { owner = owner, changedAt = 0, built = false, count = 0, parts = {} }
        records[owner] = record
    end
    return record
end

---@param record bendedCollisionRecord
local function despawnHost(record)
    if record.entityID then
        Game.GetStaticEntitySystem():DespawnEntity(record.entityID)
        record.entityID = nil
        record.removedTick = tick
    end
    record.count = 0
end

---@param preset string
---@return physicsFilterData
local function makeFilter(preset)
    local filterData = physicsFilterData.new()
    filterData.preset = CName.new(preset)

    local query = physicsQueryFilter.new()
    query.mask1 = 0
    query.mask2 = 70107400

    local sim = physicsSimulationFilter.new()
    sim.mask1 = 114696
    sim.mask2 = 23627

    filterData.queryFilter = query
    filterData.simulationFilter = sim
    return filterData
end

---@param entity entEntity
---@param shapes bendedCollisionShape[]
local function addColliders(entity, shapes)
    -- The filter is per component: one set of components per preset.
    local byPreset = {}
    local order = {}
    for _, shape in ipairs(shapes) do
        local preset = shape.preset or "World Static"
        if not byPreset[preset] then
            byPreset[preset] = {}
            table.insert(order, preset)
        end
        table.insert(byPreset[preset], shape)
    end

    local part = 0
    for _, preset in ipairs(order) do
        local colliders = {}

        local function flush()
            if #colliders == 0 then return end
            part = part + 1
            local component = entColliderComponent.new()
            component.name = CName.new("bendedCollision" .. part)
            component.colliders = colliders
            component.filterData = makeFilter(preset)
            entity:AddComponent(component)
            colliders = {}
        end

        for _, shape in ipairs(byPreset[preset]) do
            local vertices = {}
            for i, point in ipairs(shape.points) do
                vertices[i] = Vector3.new(point.x, point.y, point.z)
            end

            local convex = physicsColliderConvex.new()
            convex.vertices = vertices
            convex.material = CName.new(shape.material)
            table.insert(colliders, convex)

            if #colliders >= collidersPerComponent then
                flush()
            end
        end
        flush()
    end
end

---Rotation matrix rows of a quaternion, for row vectors.
---@param q Quaternion
---@return number[]
local function rotationRows(q)
    local x, y, z, w = q.i, q.j, q.k, q.r
    return {
        1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w),
        2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w),
        2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)
    }
end

---World-space bone matrices placing one hull triangle each, and their bounds.
---@param record bendedCollisionRecord
---@return table[] matrices
---@return number[] box
local function buildTriangleMatrices(record)
    local r = rotationRows(record.quat)
    local px, py, pz = record.position.x, record.position.y, record.position.z
    local matrices = {}
    local box = { math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge }

    for _, shape in ipairs(record.shapes) do
        local world = {}
        for i, p in ipairs(shape.points) do
            local x = p.x * r[1] + p.y * r[4] + p.z * r[7] + px
            local y = p.x * r[2] + p.y * r[5] + p.z * r[8] + py
            local z = p.x * r[3] + p.y * r[6] + p.z * r[9] + pz
            world[i] = { x, y, z }
            box[1], box[2], box[3] = math.min(box[1], x), math.min(box[2], y), math.min(box[3], z)
            box[4], box[5], box[6] = math.max(box[4], x), math.max(box[5], y), math.max(box[6], z)
        end

        local faces = shape.faces or {}
        for f = 1, #faces - 2, 3 do
            local a, b, c = world[faces[f] + 1], world[faces[f + 1] + 1], world[faces[f + 2] + 1]
            local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
            local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
            local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            local length = math.sqrt(nx * nx + ny * ny + nz * nz)

            -- Rows X and Y swapped: the preview mesh shows counter-clockwise faces as back faces.
            if length > 1e-9 then
                matrices[#matrices + 1] = {
                    vx, vy, vz, 0, ux, uy, uz, 0,
                    nx / length, ny / length, nz / length, 0,
                    a[1], a[2], a[3], 1
                }
            end
        end
    end

    return matrices, box
end

---@param record bendedCollisionRecord
---@param from integer First part to release.
local function releaseParts(record, from)
    for i = #record.parts, from, -1 do
        bendedPool.release(record.parts[i])
        record.parts[i] = nil
    end
end

---Shows the record's pieces as a hologram, or hides it when there is nothing to show.
---@param record bendedCollisionRecord
local function showVisual(record)
    if not record.colour or not record.shapes or #record.shapes == 0 then
        releaseParts(record, 1)
        return
    end

    local matrices, box = buildTriangleMatrices(record)
    local count = math.ceil(#matrices / trianglesPerMesh)
    local mesh = visualMeshPrefix .. record.colour .. ".mesh"

    for part = 1, count do
        local slice = {}
        local first = (part - 1) * trianglesPerMesh
        for bone = 1, trianglesPerMesh do
            slice[bone] = matrices[first + bone] or { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, box[1], box[2], box[3], 1 }
        end

        record.parts[part] = record.parts[part] or { record = record, index = part }
        bendedPool.submit(record.parts[part], {
            mesh = mesh,
            appearance = "default",
            matrices = slice,
            box = box,
            castShadows = "Never",
            castLocalShadows = "Never"
        })
    end

    releaseParts(record, count + 1)
end

---@param record bendedCollisionRecord
local function build(record)
    record.built = true
    despawnHost(record)

    local ok, shapes, issue = pcall(record.owner.getCollisionShapes, record.owner)
    if not ok then
        logger:warn("Bended collision failed: " .. tostring(shapes))
        record.issue = "Collision could not be built."
        return
    end
    record.issue = issue
    record.shapes = shapes
    local position = record.owner.position
    record.position = { x = position.x, y = position.y, z = position.z }
    record.quat = record.owner.rotation:ToQuat()
    showVisual(record)
    if not shapes or #shapes == 0 then return end

    local spec = StaticEntitySpec.new()
    spec.templatePath = hostTemplate
    spec.position = record.owner.position
    spec.orientation = record.owner.rotation:ToQuat()
    spec.attached = true

    local entityID = Game.GetStaticEntitySystem():SpawnEntity(spec)
    if not entityID or not entityID.hash or entityID.hash == 0 then
        record.issue = "The collision host could not be spawned."
        return
    end

    record.entityID = entityID
    record.count = #shapes

    builder.registerAssembleCallback(entityID, function (entity)
        if record.entityID ~= entityID then return end
        addColliders(entity, shapes)
    end)
end

---Declares the owner's current shape. A new signature removes the collision until it settles.
---@param owner table
---@param signature string
function preview.request(owner, signature)
    local record = getRecord(owner)
    if record.signature == signature then return end

    record.signature = signature
    record.changedAt = clock
    record.built = false
    record.issue = nil
    despawnHost(record)
end

---Removes the owner's collision now; it comes back with the next settled shape.
---@param owner table
function preview.suspend(owner)
    local record = records[owner]
    if not record then return end

    despawnHost(record)
    record.built = false
    record.changedAt = clock
end

---Suspends the owner's collision and runs `callback` once raycasts no longer hit it: a despawned
---host stays in the physics scene until the next frame. The callback runs from onDraw.
---@param owner table
---@param callback function
function preview.withoutCollision(owner, callback)
    preview.suspend(owner)

    local record = records[owner]
    if record and record.removedTick == tick then
        table.insert(waiting, { tick = tick, callback = callback })
    else
        callback()
    end
end

---Shows the owner's collision as a hologram of the given colour (`red`, `green`, `blue`), or hides it.
---The hologram follows the collision: it is replaced each time the collision is rebuilt.
---@param owner table
---@param colour string?
function preview.setVisual(owner, colour)
    local record = getRecord(owner)
    if record.colour == colour then return end

    record.colour = colour
    showVisual(record)
end

---@param owner table
function preview.release(owner)
    local record = records[owner]
    if not record then return end

    despawnHost(record)
    releaseParts(record, 1)
    records[owner] = nil
end

---Hologram placeholders on screen and in total; 0, 0 when hidden.
---@param owner table
---@return integer shown
---@return integer total
function preview.getVisualStatus(owner)
    local record = records[owner]
    if not record then return 0, 0 end

    local shown = 0
    for _, part in ipairs(record.parts) do
        if bendedPool.isShowing(part) then shown = shown + 1 end
    end
    return shown, #record.parts
end

---`active`, `pending`, `none` or `off`, with the piece count and the reason when there is none.
---@param owner table
---@return string status
---@return integer count
---@return string? issue
function preview.getStatus(owner)
    local record = records[owner]
    if not record or not record.signature then return "off", 0, nil end
    if not record.built then return "pending", 0, nil end
    if record.entityID then return "active", record.count, nil end
    return "none", 0, record.issue
end

---Reads the mouse (ImGui is not callable from onUpdate), released while CET is closed, and runs the
---`withoutCollision` callbacks that are due.
---@param overlayOpen boolean
function preview.onDraw(overlayOpen)
    mouseDown = overlayOpen and ImGui.IsMouseDown(ImGuiMouseButton.Left) or false

    if #waiting == 0 or waiting[1].tick == tick then return end
    local due = waiting
    waiting = {}
    for _, entry in ipairs(due) do
        if entry.tick == tick then
            table.insert(waiting, entry)
        else
            local ok, err = pcall(entry.callback)
            if not ok then
                logger:warn("Bended collision callback failed: " .. tostring(err))
            end
        end
    end
end

---@param dt number
function preview.update(dt)
    clock = clock + (dt or 0)
    tick = tick + 1

    if not visualBoundsReady then
        visualBoundsReady = widenVisualBounds()
    end

    for _, record in pairs(records) do
        if not record.built and record.signature and not mouseDown and clock - record.changedAt >= settleTime then
            build(record)
        end
    end
end

---Forgets every host, e.g. when the game session ends and the entities are gone.
function preview.reset()
    waiting = {}
    visualBoundsReady = false
    for _, record in pairs(records) do
        record.parts = {}
        record.entityID = nil
        record.built = false
        record.count = 0
    end
end

return preview
