local logger = require("modules/utils/core/logger")

---Allocates placeholder bended mesh nodes used to preview deformation.
---Each slot is a `worldBendedMeshNode` alone in a prefab variant of the World Builder preview
---sector. The engine reads `deformationData` only when a node attaches, so a slot is updated by
---turning its variant off, writing the definition, and turning it back on.
---Definitions are read from the sector resource and variants toggled through Codeware.
---@class bendedPool
local pool = {}

-- Nodes shipped in the archive; the pool shrinks to the sector actually loaded (an older archive).
local expectedSlots = 500
local slotCount = expectedSlots
local prefabPath = "$/mods/entSpawner/preview_bended/#all"
local variantPrefix = "wb_bended_v"
local sectorPath = "world_builder\\sectors\\wb_preview_bended.streamingsector"

-- Off and on in the same frame is a no-op; one frame apart re-attaches.
local detachFrames = 1
-- Nothing reports the re-attach, so the cycle waits this long after turning the variant back on.
local attachFrames = 5
local resolveTimeoutFrames = 60

local parkedPayload = {
    mesh = "base\\worlds\\03_night_city\\sectors\\_external\\road_meshes\\bended\\br_bcaafaf2_rt_1x1_with_sidewalks_24m.mesh",
    appearance = "default",
    matrices = {},
    box = { -1, -1, -1, 1, 1, 1 }
}
for i = 1, 9 do
    parkedPayload.matrices[i] = { 0.001, 0, 0, 0, 0, 0.001, 0, 0, 0, 0, 0.001, 0, 0, (i - 1) * 0.003, 0, 1 }
end

---@class bendedPoolPayload
---@field mesh string Mesh resource path.
---@field appearance string
---@field matrices table[] World-space deformation, 16 numbers per bone (X, Y, Z, W rows).
---@field box number[] World-space deformed box: minX, minY, minZ, maxX, maxY, maxZ.
---@field castShadows string? `shadowsShadowCastingMode` member name.
---@field castLocalShadows string?

---@class bendedPoolSlot
---@field index integer 0-based slot index.
---@field variant string Variant name.
---@field state string `idle`, `resolving`, `detaching` or `attaching`.
---@field frames integer
---@field definition worldBendedMeshNode?
---@field job table? `{ payload, onDone }`
---@field user any? Owner record or `true` while parking.
---@field broken boolean? Could not be resolved this session.

---@class bendedPoolOwner
---@field owner table Spawnable the record belongs to.
---@field front bendedPoolSlot? Slot currently showing the owner's mesh.
---@field pending bendedPoolPayload?
---@field busy boolean A cycle for this owner is running.
---@field released boolean

local slots = {}
local owners = {}
local prefabRef = nil
---Held so the preview sector resource stays loaded.
local sectorToken = nil
---Slot definitions by node index, read from the sector resource.
local sectorNodes = nil

---Last claim error shown in the UI.
pool.lastReason = ""

---@return WorldStateSystem?
local function getWorldState()
    local ok, system = pcall(function()
        return Game.GetWorldStateSystem and Game.GetWorldStateSystem()
    end)

    return ok and system or nil
end

---@return ResourceDepot?
local function getDepot()
    local ok, depot = pcall(function()
        return Game.GetResourceDepot and Game.GetResourceDepot()
    end)

    return ok and depot or nil
end

---Whether the runtime pieces the pool needs are present.
---@return boolean
function pool.isAvailable()
    return getDepot() ~= nil and getWorldState() ~= nil
end

---@param index integer
---@return bendedPoolSlot
local function getSlot(index)
    local slot = slots[index]
    if not slot then
        slot = { index = index, variant = variantPrefix .. index, state = "idle", frames = 0 }
        slots[index] = slot
    end

    return slot
end

local sectorIssue = nil

---Shows why the sector cannot be read yet; each new reason is logged once.
---@param issue string
---@param quiet boolean?
local function reportSector(issue, quiet)
    pool.lastReason = issue
    if issue ~= sectorIssue then
        sectorIssue = issue
        if not quiet then
            logger:warn("[bendedPool] " .. issue)
        end
    end
end

---Slot definition read from the preview sector resource, the one the streamed node uses.
---@param slot bendedPoolSlot
---@return worldBendedMeshNode?
local function resolve(slot)
    if not sectorNodes then
        local depot = getDepot()
        if not depot then
            reportSector("Codeware's resource depot is not available.")
            return nil
        end

        if not sectorToken then
            local ok, token = pcall(function()
                return depot:LoadResource(ResRef.FromString(sectorPath))
            end)
            if not ok or not token then
                reportSector("Could not request the preview sector: " .. tostring(token))
                return nil
            end
            sectorToken = token
        end

        local ok, issue = pcall(function()
            if sectorToken:IsFailed() then
                return "The preview sector failed to load. Is the World Builder archive installed?"
            end
            if not sectorToken:IsLoaded() then
                return false
            end

            local sector = sectorToken:GetResource()
            if not sector then
                return "The preview sector resource is empty."
            end

            -- debugName is editor data, so slots are found by node index: node N is slot N.
            local count = sector:GetNodeCount()
            if count == 0 then
                return "The preview sector holds no node. Is the World Builder archive up to date?"
            end
            if count ~= expectedSlots then
                logger:warn(string.format("[bendedPool] the preview sector holds %d nodes, expected %d: World Builder archive out of date", count, expectedSlots))
            end
            slotCount = count

            local nodes = {}
            for i = 0, count - 1 do
                nodes[i] = sector:GetNode(i)
            end
            sectorNodes = nodes
            return nil
        end)

        if not ok then
            reportSector("Could not read the preview sector: " .. tostring(issue))
            return nil
        elseif issue == false then
            reportSector("Loading the preview sector...", true)
            return nil
        elseif issue then
            reportSector(issue)
            return nil
        end
    end

    local node = sectorNodes[slot.index]
    if not node then
        reportSector(string.format("Placeholder node %d is missing from the preview sector.", slot.index))
    elseif sectorIssue then
        sectorIssue = nil
        pool.lastReason = ""
    end

    return node
end

---@param slot bendedPoolSlot
---@param state boolean
local function toggle(slot, state)
    local system = getWorldState()
    if not system then return end

    pcall(function()
        if not prefabRef then
            prefabRef = CreateEntityReference(prefabPath, {}).reference
        end
        system:ToggleVariant(prefabRef, slot.variant, state)
    end)
end

---@param t number[]
---@return Matrix
local function toMatrix(t)
    local m = Matrix.new()
    m.X = Vector4.new(t[1], t[2], t[3], t[4])
    m.Y = Vector4.new(t[5], t[6], t[7], t[8])
    m.Z = Vector4.new(t[9], t[10], t[11], t[12])
    m.W = Vector4.new(t[13], t[14], t[15], t[16])
    return m
end

---Writes a payload into a detached slot definition.
---@param definition worldBendedMeshNode
---@param payload bendedPoolPayload
---@return boolean
local function write(definition, payload)
    local ok, err = pcall(function()
        local matrices = {}
        for i, t in ipairs(payload.matrices) do
            matrices[i] = toMatrix(t)
        end

        local box = Box.new()
        box.Min = Vector4.new(payload.box[1], payload.box[2], payload.box[3], 1)
        box.Max = Vector4.new(payload.box[4], payload.box[5], payload.box[6], 1)

        definition.mesh = ResRef.FromString(payload.mesh)
        definition.meshAppearance = CName.new(payload.appearance or "default")
        definition.deformationData = matrices
        definition.deformedBox = box

        if payload.castShadows then
            definition.castShadows = Enum.new("shadowsShadowCastingMode", payload.castShadows)
        end
        if payload.castLocalShadows then
            definition.castLocalShadows = Enum.new("shadowsShadowCastingMode", payload.castLocalShadows)
        end
    end)

    if not ok then
        logger:warn("[bendedPool] could not write slot data: " .. tostring(err))
    end

    return ok
end

---Starts the detach / write / attach cycle on an idle slot.
---@param slot bendedPoolSlot
---@param payload bendedPoolPayload
---@param onDone fun(success: boolean)
local function startCycle(slot, payload, onDone)
    slot.job = { payload = payload, onDone = onDone }
    slot.state = "resolving"
    slot.frames = 0
end

---@param slot bendedPoolSlot
---@param success boolean
local function finish(slot, success)
    local job = slot.job
    slot.job = nil
    slot.state = "idle"
    slot.frames = 0

    if job and job.onDone then
        job.onDone(success)
    end
end

---@param slot bendedPoolSlot
local function step(slot)
    slot.frames = slot.frames + 1

    if slot.state == "resolving" then
        local definition = resolve(slot)

        if definition then
            slot.definition = definition
            toggle(slot, false)
            slot.state = "detaching"
            slot.frames = 0
        elseif slot.frames == 1 then
            -- A variant left off by a save comes back on.
            toggle(slot, true)
        elseif slot.frames > resolveTimeoutFrames then
            slot.broken = true
            finish(slot, false)
        end
    elseif slot.state == "detaching" then
        if slot.frames >= detachFrames then
            local written = write(slot.definition, slot.job.payload)
            toggle(slot, true)
            slot.state = "attaching"
            slot.frames = 0

            if not written then
                slot.job.failed = true
            end
        end
    elseif slot.state == "attaching" then
        if slot.frames >= attachFrames then
            finish(slot, not slot.job.failed)
        end
    end
end

---Puts a slot back to its invisible default and frees it afterwards.
---@param slot bendedPoolSlot?
local function park(slot)
    if not slot then return end

    slot.user = true
    startCycle(slot, parkedPayload, function()
        slot.user = nil
    end)
end

---@return bendedPoolSlot?
local function takeFreeSlot()
    for index = 0, slotCount - 1 do
        local slot = getSlot(index)
        if not slot.user and not slot.broken and slot.state == "idle" then
            return slot
        end
    end

    return nil
end

---@param record bendedPoolOwner
local function notifyShown(record)
    local owner = record.owner
    if owner and owner.onBendedPreviewShown then
        local ok, err = pcall(owner.onBendedPreviewShown, owner)
        if not ok then
            logger:warn("[bendedPool] owner callback failed: " .. tostring(err))
        end
    end
end

---Parks every slot of a record once its running cycle is over.
---@param record bendedPoolOwner
local function settleReleased(record)
    if not record.released or record.busy then return end

    park(record.front)
    record.front = nil
end

---@param record bendedPoolOwner
local function process(record)
    if record.busy or record.released or not record.pending then return end

    local payload = record.pending
    local spare = takeFreeSlot()

    if not record.front then
        if not spare then
            pool.lastReason = "No preview slot is free. All " .. slotCount .. " bended placeholders are in use, or the World Builder preview sector is not streaming - which needs a full game restart after installing or updating the mod."
            return
        end

        record.pending = nil
        record.busy = true
        spare.user = record

        startCycle(spare, payload, function(success)
            record.busy = false

            if success then
                record.front = spare
                notifyShown(record)
            else
                spare.user = nil
                -- Retried on another slot.
                record.pending = record.pending or payload
            end

            settleReleased(record)
        end)
    elseif spare then
        -- Double buffer: the front slot stays visible until the new one is attached.
        record.pending = nil
        record.busy = true
        spare.user = record

        startCycle(spare, payload, function(success)
            record.busy = false

            if success then
                park(record.front)
                record.front = spare
            else
                spare.user = nil
                record.pending = record.pending or payload
            end

            settleReleased(record)
        end)
    else
        record.pending = nil
        record.busy = true

        startCycle(record.front, payload, function()
            record.busy = false
            settleReleased(record)
        end)
    end
end

---Queues a payload for an owner, claiming a slot if it has none. Repeated calls coalesce.
---@param owner table
---@param payload bendedPoolPayload
---@return boolean queued False when the pool cannot run at all.
function pool.submit(owner, payload)
    if not pool.isAvailable() then
        pool.lastReason = "Codeware is not installed. The deformed preview needs it to reach and toggle the placeholder bended nodes."
        return false
    end

    local record = owners[owner]
    if not record then
        record = { owner = owner, busy = false, released = false }
        owners[owner] = record
    end

    record.pending = payload
    return true
end

---Releases an owner's slots; they are parked and freed once their cycle ends.
---@param owner table
function pool.release(owner)
    local record = owners[owner]
    if not record then return end

    owners[owner] = nil
    record.pending = nil
    record.released = true
    settleReleased(record)
end

---Whether the owner's deformed mesh is currently on screen.
---@param owner table
---@return boolean
function pool.isShowing(owner)
    local record = owners[owner]
    return record ~= nil and record.front ~= nil
end

---Preview state for the UI.
---@param owner table
---@return string state `active`, `pending`, `unavailable` or `off`.
function pool.getStatus(owner)
    local record = owners[owner]
    if not record then
        return "off"
    end

    if record.front then
        return "active"
    end

    if record.busy or (record.pending and takeFreeSlot()) then
        return "pending"
    end

    return "unavailable"
end

---Advances every running cycle. Called once per frame.
function pool.update()
    for _, slot in pairs(slots) do
        if slot.state ~= "idle" then
            step(slot)
        end
    end

    for _, record in pairs(owners) do
        process(record)
    end
end

local dissolveRestore = nil

---Streamed nodes fade in over `Rendering/DissolveTime`. At 0 a re-attached slot shows at once.
---@param state boolean True sets 0 and remembers the current value, false puts it back.
function pool.setInstantDissolve(state)
    if not GameOptions or not GameOptions.GetFloat or not GameOptions.SetFloat then return end

    if state then
        if dissolveRestore then return end
        local ok, current = pcall(GameOptions.GetFloat, "Rendering", "DissolveTime")
        dissolveRestore = (ok and type(current) == "number" and current > 0) and current or 0.5
        pcall(GameOptions.SetFloat, "Rendering", "DissolveTime", 0.0)
    elseif dissolveRestore then
        pcall(GameOptions.SetFloat, "Rendering", "DissolveTime", dissolveRestore)
        dissolveRestore = nil
    end
end

---Forgets every slot and owner. Slot definitions reload with the sector on a new session.
function pool.reset()
    slots = {}
    owners = {}
    prefabRef = nil
    sectorToken = nil
    sectorNodes = nil
    sectorIssue = nil
    slotCount = expectedSlots
    pool.lastReason = ""
end

return pool
