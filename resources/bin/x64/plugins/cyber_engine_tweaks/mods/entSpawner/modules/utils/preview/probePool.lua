local logger = require("modules/utils/core/logger")

---Placeholder reflection probe nodes used to preview probes through the real node path.
---Each slot is a `worldReflectionProbeNode` alone in an off-by-default prefab variant of the preview sector.
---A slot is updated by turning its variant off, writing its definition and instance transform, and turning it back on.
---@class probePool
local pool = {}

local expectedSlots = 20
local slotCount = expectedSlots
local prefabPath = "$/mods/entSpawner/preview_probes/#all"
local variantPrefix = "wb_probe_v"
local sectorPath = "world_builder\\sectors\\wb_preview_probes.streamingsector"

-- Off and on in the same frame is a no-op; one frame apart re-attaches.
local detachFrames = 1
local attachFrames = 5

---@class probePoolPayload
---@field position Vector4
---@field orientation Quaternion
---@field scale {x: number, y: number, z: number}
---@field write fun(definition: worldReflectionProbeNode) Writes the node properties.

---@class probePoolSlot
---@field index integer 0-based slot index, also the node index in the sector.
---@field variant string
---@field state string `idle`, `detaching` or `attaching`.
---@field frames integer
---@field job table? `{ record, payload, onDone, failed }`
---@field user probePoolOwner? Owner record holding the slot.

---@class probePoolOwner
---@field owner table
---@field front probePoolSlot? Slot showing the owner's probe.
---@field pending probePoolPayload?
---@field busy boolean
---@field released boolean

local slots = {}
local owners = {}
---Owners sent to the component preview because every slot was taken; told when one frees up, then dropped.
local waiters = {}
local prefabRef = nil
local sectorToken = nil
---@type worldStreamingSector?
local sector = nil
local sectorFailed = false
local parkedAll = false

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

---@param slot probePoolSlot
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

---@param index integer
---@return probePoolSlot
local function getSlot(index)
    local slot = slots[index]
    if not slot then
        slot = { index = index, variant = variantPrefix .. index, state = "idle", frames = 0 }
        slots[index] = slot
    end
    return slot
end

---Loads the preview sector resource; true once its nodes can be written.
---@return boolean
local function resolveSector()
    if sector then return true end
    if sectorFailed then return false end

    local depot = getDepot()
    if not depot then
        pool.lastReason = "Codeware's resource depot is not available."
        return false
    end

    if not sectorToken then
        local ok, token = pcall(function()
            return depot:LoadResource(ResRef.FromString(sectorPath))
        end)
        if not ok or not token then
            pool.lastReason = "Could not request the probe preview sector."
            sectorFailed = true
            return false
        end
        sectorToken = token
    end

    local ok, result = pcall(function()
        if sectorToken:IsFailed() then
            return "The probe preview sector failed to load. Is the World Builder archive up to date?"
        end
        if not sectorToken:IsLoaded() then
            return false
        end

        local resource = sectorToken:GetResource()
        if not resource or resource:GetNodeCount() == 0 or resource:GetNodeSetupCount() == 0 then
            return "The probe preview sector holds no node. Is the World Builder archive up to date?"
        end

        slotCount = math.min(resource:GetNodeCount(), resource:GetNodeSetupCount())
        sector = resource
        return true
    end)

    if not ok then
        pool.lastReason = "Could not read the probe preview sector: " .. tostring(result)
        sectorFailed = true
        return false
    elseif result == false then
        pool.lastReason = "Loading the probe preview sector..."
        return false
    elseif result ~= true then
        pool.lastReason = result
        sectorFailed = true
        logger:warn("[probePool] " .. result)
        return false
    end

    pool.lastReason = ""
    return true
end

---Writes a payload into a detached slot.
---@param slot probePoolSlot
---@param payload probePoolPayload
---@return boolean
local function write(slot, payload)
    local ok, err = pcall(function()
        local setup = sector:GetNodeSetup(slot.index)
        setup:SetPosition(payload.position)
        setup:SetOrientation(payload.orientation)
        setup:SetScale(Vector3.new(payload.scale.x, payload.scale.y, payload.scale.z))
        payload.write(sector:GetNode(slot.index))
    end)

    if not ok then
        pool.lastReason = "Could not write the probe placeholder: " .. tostring(err)
        logger:warn("[probePool] " .. pool.lastReason)
    end

    return ok
end

---@param slot probePoolSlot
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


---@param slot probePoolSlot
---@param record probePoolOwner
---@param payload probePoolPayload
---@param onDone fun(success: boolean)
local function startCycle(slot, record, payload, onDone)
    slot.job = { record = record, payload = payload, onDone = onDone }
    slot.state = "detaching"
    slot.frames = 0
    toggle(slot, false)
end

---@param slot probePoolSlot
local function step(slot)
    slot.frames = slot.frames + 1

    if slot.state == "detaching" then
        if slot.frames >= detachFrames then
            slot.job.failed = not write(slot, slot.job.payload)
            if not slot.job.failed then
                toggle(slot, true)
            end
            slot.state = "attaching"
            slot.frames = 0
        end
    elseif slot.state == "attaching" and slot.frames >= attachFrames then
        finish(slot, not slot.job.failed)
    end
end

---Turns a slot's variant off and frees the slot.
---@param slot probePoolSlot?
local function park(slot)
    if not slot then return end
    toggle(slot, false)
    slot.user = nil
end

---@param slot probePoolSlot
---@return boolean
local function isFree(slot)
    return not slot.user and slot.state == "idle"
end

---@return probePoolSlot?
local function takeFreeSlot()
    for index = 0, slotCount - 1 do
        local slot = getSlot(index)
        if isFree(slot) then
            return slot
        end
    end
    return nil
end

---@return integer
local function countFreeSlots()
    local free = 0
    for index = 0, slotCount - 1 do
        if isFree(getSlot(index)) then
            free = free + 1
        end
    end
    return free
end

---Whether a running cycle frees a slot when it ends: a double buffer swap, or a released owner.
---@return boolean
local function slotFreesSoon()
    for _, slot in pairs(slots) do
        local record = slot.job and slot.job.record
        if record and (record.released or (record.front ~= nil and record.front ~= slot)) then
            return true
        end
    end
    return false
end

---@param record probePoolOwner
local function settleReleased(record)
    if not record.released or record.busy then return end
    park(record.front)
    record.front = nil
end

---@param owner table
---@param method string
local function notify(owner, method)
    if owner and owner[method] then
        local ok, err = pcall(owner[method], owner)
        if not ok then
            logger:warn("[probePool] owner callback failed: " .. tostring(err))
        end
    end
end

---Drops an owner's slot and sends it to the component preview, unless it was released.
---@param record probePoolOwner
local function giveUp(record)
    park(record.front)
    record.front = nil
    record.pending = nil
    if record.released then return end

    owners[record.owner] = nil
    notify(record.owner, "onProbePreviewUnavailable")
end

---@param record probePoolOwner
---@param reserved integer Free slots kept for owners without a slot.
local function process(record, reserved)
    if record.busy or record.released or not record.pending then return end

    -- Double buffering an owner that already shows its probe must not starve one that has none.
    local spare = nil
    if not record.front or countFreeSlots() > reserved then
        spare = takeFreeSlot()
    end

    if not spare and not record.front then
        if slotFreesSoon() then return end

        pool.lastReason = string.format("All %d probe placeholders are in use. The preview switches back once one is free.", slotCount)
        giveUp(record)
        waiters[record.owner] = true
        return
    end

    local payload = record.pending
    record.pending = nil
    record.busy = true

    if spare then
        -- Double buffer: the front slot stays live until the new one is attached.
        spare.user = record
        startCycle(spare, record, payload, function(success)
            record.busy = false
            if success then
                park(record.front)
                record.front = spare
            else
                park(spare)
                giveUp(record)
            end
            settleReleased(record)
        end)
    else
        startCycle(record.front, record, payload, function(success)
            record.busy = false
            if not success then
                giveUp(record)
            end
            settleReleased(record)
        end)
    end
end

---Whether Codeware is present and the preview sector has not failed.
---@return boolean
function pool.isAvailable()
    return getDepot() ~= nil and getWorldState() ~= nil and not sectorFailed
end

---Queues a payload for an owner, claiming a slot if it has none. Repeated calls coalesce.
---@param owner table
---@param payload probePoolPayload
---@return boolean queued
function pool.submit(owner, payload)
    if not pool.isAvailable() then return false end

    waiters[owner] = nil
    local record = owners[owner]
    if not record then
        record = { owner = owner, busy = false, released = false }
        owners[owner] = record
    end

    record.pending = payload
    return true
end

---Releases an owner's slot; it is parked once its cycle ends.
---A waiter stays listed: its fallback respawn may despawn it after the pool listed it. A deleted owner ignores the call.
---@param owner table
function pool.release(owner)
    local record = owners[owner]
    if not record then return end

    owners[owner] = nil
    record.pending = nil
    record.released = true
    settleReleased(record)
end

---@param owner table
---@return string state `active`, `pending` or `off`.
function pool.getStatus(owner)
    local record = owners[owner]
    if not record then return "off" end
    if record.front then return "active" end
    return "pending"
end

---Advances every running cycle. Called once per frame.
function pool.update()
    if not next(owners) and not next(slots) then return end
    if not resolveSector() then
        if sectorFailed then
            waiters = {}
            for owner in pairs(owners) do
                owners[owner] = nil
                notify(owner, "onProbePreviewUnavailable")
            end
        end
        return
    end

    if not parkedAll then
        -- Variant states can come back from a save.
        parkedAll = true
        for index = 0, slotCount - 1 do
            toggle(getSlot(index), false)
        end
        return
    end

    for _, slot in pairs(slots) do
        if slot.state ~= "idle" then
            step(slot)
        end
    end

    -- Owners without a slot go first, and the free slots they still need are not used for double buffering.
    local unslotted, slotted = {}, {}
    for _, record in pairs(owners) do
        table.insert(record.front and slotted or unslotted, record)
    end
    for _, record in ipairs(unslotted) do
        process(record, 0)
    end

    local reserved = 0
    for _, record in pairs(owners) do
        if not record.front and not record.busy and record.pending then
            reserved = reserved + 1
        end
    end
    local waiting = {}
    for owner in pairs(waiters) do
        table.insert(waiting, owner)
    end
    reserved = reserved + #waiting

    for _, record in ipairs(slotted) do
        process(record, reserved)
    end

    local free = countFreeSlots()
    for _, owner in ipairs(waiting) do
        if free <= 0 then break end
        free = free - 1
        waiters[owner] = nil
        notify(owner, "onProbePreviewSlotFree")
    end
end

---Forgets every slot and owner; the sector is read again on the next session.
function pool.reset()
    slots = {}
    owners = {}
    waiters = {}
    prefabRef = nil
    sectorToken = nil
    sector = nil
    sectorFailed = false
    parkedAll = false
    pool.lastReason = ""
end

return pool
