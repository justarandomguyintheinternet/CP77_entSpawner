local utils = require("modules/utils/core/utils")
local Cron = require("modules/utils/vendor/Cron")
local history = require("modules/utils/project/history")
local settings = require("modules/utils/core/settings")
local pipelineCommon = require("modules/utils/pipeline/common")
local logger = require("modules/utils/core/logger")
local saveState = require("modules/utils/project/saveState")

local groupLoadManager = {}
local FAST_LOAD_BUDGET_MS = 20
local SLOW_LOAD_BUDGET_MS = 5
local FAST_LOAD_PRESET = 1

---@return number
local function getConfiguredLoadBudgetMs()
    if settings.groupLoadSpeedPreset == FAST_LOAD_PRESET then
        return FAST_LOAD_BUDGET_MS
    end

    return SLOW_LOAD_BUDGET_MS
end

local function createLoadState(previous)
    -- enqueue
    local enqueueChunkSize = previous and previous.enqueueChunkSize or 2
    local enqueueTimeBudgetMs = previous and previous.enqueueTimeBudgetMs or 100
    -- build
    local buildChunkSize = previous and previous.buildChunkSize or 300
    local buildTimeBudgetMs = getConfiguredLoadBudgetMs()
    -- spawn
    local chunkSize = previous and previous.chunkSize or 100
    local spawnTimeBudgetMs = getConfiguredLoadBudgetMs()

    return {
        active = false,
        phase = "idle", -- idle|enqueue|build|spawn
        total = 0,
        loaded = 0,
        index = 1,
        entries = {},
        timer = nil,
        group = nil,
        groupName = "",
        targetParent = nil,
        setAsSpawnNew = false,
        loadHidden = false,
        selectLoaded = false,
        clearLocks = false,
        captureBaseTransform = nil,
        initialPosition = nil,
        initialRotation = nil,
        onFinished = nil,
        spawner = nil,
        chunkSize = chunkSize,
        buildChunkSize = buildChunkSize,
        enqueueChunkSize = enqueueChunkSize,
        enqueueTimeBudgetMs = enqueueTimeBudgetMs,
        buildTimeBudgetMs = buildTimeBudgetMs,
        spawnTimeBudgetMs = spawnTimeBudgetMs,
        buildQueue = {},
        buildHead = 1,
        buildTail = 0,
        rootChildContainer = nil,
        rootEnqueueCursor = nil,
        enqueueProcessed = 0,
        buildProcessed = 0,
        buildTotal = 0,
        buildFailed = 0,
        spawnFailed = 0
    }
end

groupLoadManager.state = createLoadState()
groupLoadManager.pendingToasts = {}

local function enqueueBuildEntry(state, data, parent)
    state.buildTail = state.buildTail + 1
    state.buildQueue[state.buildTail] = { data = data, parent = parent }
    state.buildTotal = state.buildTotal + 1
end

---Records the transform an element was loaded with as its base one, so the transform reset actions
---restore the source values instead of identity. Only requested for sources that define a transform
---of their own, a prefab being the one that does.
---@param state table
---@param element element?
local function captureBaseTransform(state, element)
    if not state.captureBaseTransform then return end
    if not element or not element.captureBaseTransform then return end

    element:captureBaseTransform(state.captureBaseTransform)
end

local function logLoadError(phase, name, err)
    logger:error(string.format("[Group Load Manager] [%s] Failed to process \"%s\": %s", phase, name or "Unknown", tostring(err)))
end

local function getLoadName(state)
    if state and state.groupName and state.groupName ~= "" then
        return state.groupName
    end

    if state and state.group and state.group.name then
        return state.group.name
    end

    return "Group"
end

local function removePartiallyLoadedGroup(state)
    if not state or not state.group then return end

    local ok, err = pcall(function ()
        state.group:remove()
    end)
    if not ok then
        logLoadError("cleanup", getLoadName(state), err)
    end

    if state.spawner and state.spawner.baseUI and state.spawner.baseUI.spawnedUI and state.spawner.baseUI.spawnedUI.cachePaths then
        local cacheOk, cacheErr = pcall(function ()
            state.spawner.baseUI.spawnedUI.cachePaths()
        end)

        if not cacheOk then
            logLoadError("cleanup", getLoadName(state), cacheErr)
        end
    end
end

local function queueToast(kind, duration, text)
    pipelineCommon.queueToast(groupLoadManager.pendingToasts, kind, duration, text)
end

---Change tracking is suppressed for the whole load: a group being built from a file matches that file
---by definition, and the thousands of addChild/load calls involved are not user edits.
---
---A load spans many ticks, so this cannot be a scoped push/pop -- it is held on the state and must be
---released on every exit path (finish, cancel, and the build error path). saveState's watchdog is the
---backstop if one is ever missed.
---@param state table
local function acquireSuppress(state)
    if state and not state.suppressHeld then
        state.suppressHeld = true
        saveState.pushSuppress()
    end
end

---@param state table
local function releaseSuppress(state)
    if state and state.suppressHeld then
        state.suppressHeld = false
        saveState.popSuppress()
    end
end

local function finishQueuedGroupLoad()
    local state = groupLoadManager.state
    if not state.active or not state.group then return end

    if state.timer then
        Cron.Halt(state.timer)
        state.timer = nil
    end

    local loadedGroup = state.group
    local setAsSpawnNew = state.setAsSpawnNew
    local loadedGroupName = state.groupName ~= "" and state.groupName or loadedGroup.name
    local selectLoaded = state.selectLoaded
    local spawner = state.spawner
    local onFinished = state.onFinished
    local projectFile = state.projectFile
    local suppressHistory = state.suppressHistory
    local styleNames = state.styleNames

    -- Bind before releasing suppression, so the group is already known to be a faithful copy of its
    -- file by the time anything can mark it modified.
    if projectFile then
        saveState.markLoadedFromDisk(loadedGroup, projectFile)
    end

    releaseSuppress(state)
    groupLoadManager.state = createLoadState(state)

    -- Before the insert action, so history records the styled names.
    if styleNames then
        require("modules/classes/editor/element").styleNewNames(loadedGroup)
        saveState.markDirty(loadedGroup)
    end

    if not suppressHistory then
        history.addAction(history.getInsert({ loadedGroup }))
    end
    spawner.baseUI.spawnedUI.cachePaths()

    if selectLoaded then
        spawner.baseUI.spawnedUI.unselectAll()
        loadedGroup.selected = true
        spawner.baseUI.spawnedUI.cachePaths()
    end

    if setAsSpawnNew then
        spawner.baseUI.spawnedUI.setElementSpawnNewTarget(loadedGroup)
    end

    if onFinished then
        local callbackOk, callbackErr = pcall(function ()
            onFinished(loadedGroup, state)
        end)

        if not callbackOk then
            logLoadError("finish", loadedGroupName, callbackErr)
        end
    end

    if state.buildFailed > 0 or state.spawnFailed > 0 then
        queueToast("warning", 5000, string.format("Finished loading group \"%s\" with %d build failures and %d spawn failures", loadedGroupName, state.buildFailed, state.spawnFailed))
    else
        queueToast("success", 5000, string.format("Finished loading group \"%s\"", loadedGroupName))
    end
end

local function beginSpawnPhase()
    local state = groupLoadManager.state
    if not state.active then return end

    state.phase = "spawn"
    state.total = #state.entries
    state.loaded = 0
    state.index = 1

    if state.initialPosition and state.group and state.group.setPosition then
        local ok, err = pcall(function ()
            state.group:setPosition(state.initialPosition)
        end)
        if not ok then
            logLoadError("place", state.groupName, err)
        end
    end

    if state.initialRotation and state.group and state.group.setRotation then
        local ok, err = pcall(function ()
            state.group:setRotation(state.initialRotation)
        end)
        if not ok then
            logLoadError("rotate", state.groupName, err)
        end
    end

    if state.buildFailed > 0 then
        queueToast("warning", 5000, string.format("\"%s\": %d/%d elements prepared (%d failures)", state.groupName, state.buildProcessed, state.buildTotal, state.buildFailed))
    else
        queueToast("info", 5000, string.format("\"%s\": %d/%d elements prepared", state.groupName, state.buildProcessed, state.buildTotal))
    end

    if state.total == 0 then
        if state.loadHidden then
            queueToast("info", 5000, string.format("\"%s\": 0/0 elements loaded hidden", state.groupName))
        else
            queueToast("info", 5000, string.format("\"%s\": 0/0 elements spawned", state.groupName))
        end
        finishQueuedGroupLoad()
        return
    end

    state.timer = Cron.OnUpdate(function (timer)
        local current = groupLoadManager.state
        if not current.active or current.phase ~= "spawn" then
            timer:Halt()
            return
        end

        local processed = 0
        local startedAt = pipelineCommon.nowMs()
        local maxPerTick = math.max(1, current.chunkSize or 1)
        local budgetMs = math.max(0.1, current.spawnTimeBudgetMs or 0.9)

        while processed < maxPerTick and current.index <= current.total do
            local entry = current.entries[current.index]
            local ok, err = pcall(function ()
                entry:setSilent(false)
                if not current.loadHidden then
                    entry:setVisible(entry.visible, true)
                end
            end)
            if not ok then
                current.spawnFailed = current.spawnFailed + 1
                local name = entry and entry.name or "Unknown"
                logLoadError("spawn", name, err)
            end
            current.loaded = current.loaded + 1
            current.index = current.index + 1
            processed = processed + 1

            if (pipelineCommon.nowMs() - startedAt) >= budgetMs then
                break
            end
        end

        if current.index > current.total then
            timer:Halt()

            if current.loadHidden then
                if current.spawnFailed > 0 then
                    queueToast("warning", 5000, string.format("\"%s\": %d/%d elements loaded hidden (%d failures)", current.groupName, current.loaded, current.total, current.spawnFailed))
                else
                    queueToast("info", 5000, string.format("\"%s\": %d/%d elements loaded hidden", current.groupName, current.loaded, current.total))
                end
            elseif current.spawnFailed > 0 then
                queueToast("warning", 5000, string.format("\"%s\": %d/%d elements spawned (%d failures)", current.groupName, current.loaded, current.total, current.spawnFailed))
            else
                queueToast("info", 5000, string.format("\"%s\": %d/%d elements spawned", current.groupName, current.loaded, current.total))
            end

            finishQueuedGroupLoad()
        end
    end)
end

local function processBuildChunk(timer)
    local state = groupLoadManager.state
    if not state.active or state.phase ~= "build" then
        timer:Halt()
        return
    end

    local processed = 0
    local startedAt = pipelineCommon.nowMs()
    local maxPerTick = math.max(1, state.buildChunkSize or 1)
    local budgetMs = math.max(0.1, state.buildTimeBudgetMs or 1.25)

    while processed < maxPerTick and state.buildHead <= state.buildTail do
        local entry = state.buildQueue[state.buildHead]
        state.buildQueue[state.buildHead] = nil
        state.buildHead = state.buildHead + 1

        local nodeName = entry.data and entry.data.name or "Unknown"
        local new = nil
        local ok, err = pcall(function ()
            local modulePath = entry.data.modulePath or entry.parent:getModulePathByType(entry.data)
            new = require(modulePath):new(state.spawner.baseUI.spawnedUI)
            new:load(pipelineCommon.copyNodeDataWithoutChildren(entry.data, state.clearLocks), true)
            captureBaseTransform(state, new)
            new:setParent(entry.parent)
        end)
        state.buildProcessed = state.buildProcessed + 1

        if ok then
            if utils.isA(new, "spawnableElement") then
                table.insert(state.entries, new)
            end

            for _, child in pairs(entry.data.childs or {}) do
                enqueueBuildEntry(state, child, new)
            end
        else
            state.buildFailed = state.buildFailed + 1
            logLoadError("build", nodeName, err)

            -- Best effort fallback: keep loading descendants under the current parent.
            for _, child in pairs(entry.data.childs or {}) do
                enqueueBuildEntry(state, child, entry.parent)
            end
        end

        processed = processed + 1
        if (pipelineCommon.nowMs() - startedAt) >= budgetMs then
            break
        end
    end

    if state.buildHead > state.buildTail then
        timer:Halt()
        state.timer = nil
        beginSpawnPhase()
    end
end

local function beginBuildPhase()
    local state = groupLoadManager.state
    if not state.active then return end

    state.phase = "build"

    if state.buildHead > state.buildTail then
        beginSpawnPhase()
        return
    end

    state.timer = Cron.OnUpdate(function (timer)
        processBuildChunk(timer)
    end)
end

local function processEnqueueChunk(timer)
    local state = groupLoadManager.state
    if not state.active or state.phase ~= "enqueue" then
        timer:Halt()
        return
    end

    if not state.rootChildContainer then
        timer:Halt()
        state.timer = nil
        beginBuildPhase()
        return
    end

    local processed = 0
    local startedAt = pipelineCommon.nowMs()
    local maxPerTick = math.max(1, state.enqueueChunkSize or 1)
    local budgetMs = math.max(0.1, state.enqueueTimeBudgetMs or 1.0)

    while processed < maxPerTick do
        local key, child = next(state.rootChildContainer, state.rootEnqueueCursor)

        if key == nil then
            timer:Halt()
            state.timer = nil
            state.rootChildContainer = nil
            state.rootEnqueueCursor = nil
            beginBuildPhase()
            return
        end

        state.rootEnqueueCursor = key
        enqueueBuildEntry(state, child, state.group)
        state.enqueueProcessed = state.enqueueProcessed + 1
        processed = processed + 1

        if (pipelineCommon.nowMs() - startedAt) >= budgetMs then
            break
        end
    end
end

---@class groupLoadRequest
---@field spawner spawner
---@field data table
---@field targetParent element?
---@field setAsSpawnNew boolean?
---@field loadHidden boolean?
---@field selectLoaded boolean?
---@field clearLocks boolean?
---@field captureBaseTransform string? Source name recorded as the base transform of every loaded element, for example "prefab".
---@field initialPosition Vector4?
---@field initialRotation EulerAngles?
---@field onFinished function?
---@field projectFile string? File name in `data/objects/` this group was loaded from. Binds the group
---to that file for auto-save, and marks it as matching disk. Omit for anything not loaded from a
---saved project (favorites, prefabs, session blobs).
---@field suppressHistory boolean? Skip the insert action on finish. Used when restoring several
---groups at once, where one history entry per group would be noise.
---@field styleNames boolean? Apply the `underscoreNames` setting to the loaded tree on finish, for
---content added rather than restored (prefabs).
---@field chunkSize number?
---@field buildChunkSize number?
---@field enqueueChunkSize number?
---@field enqueueTimeBudgetMs number?
---@field buildTimeBudgetMs number?
---@field spawnTimeBudgetMs number?
---@return boolean started
function groupLoadManager.start(request)
    if groupLoadManager.state.active then return false end
    if not request or not request.spawner or not request.data then return false end

    local state = createLoadState(groupLoadManager.state)
    state.active = true
    state.phase = "enqueue"
    state.spawner = request.spawner
    state.groupName = request.data.name or "Group"
    state.targetParent = request.targetParent or request.spawner.baseUI.spawnedUI.root
    state.loadHidden = request.loadHidden == true
    state.setAsSpawnNew = request.setAsSpawnNew == true and not state.loadHidden
    state.selectLoaded = request.selectLoaded == true
    state.clearLocks = request.clearLocks == true
    state.captureBaseTransform = request.captureBaseTransform
    state.initialPosition = request.initialPosition
    state.initialRotation = request.initialRotation
    state.onFinished = request.onFinished
    state.projectFile = request.projectFile
    state.suppressHistory = request.suppressHistory == true
    state.styleNames = request.styleNames == true

    acquireSuppress(state)

    if request.chunkSize and request.chunkSize > 0 then
        state.chunkSize = request.chunkSize
    end
    if request.buildChunkSize and request.buildChunkSize > 0 then
        state.buildChunkSize = request.buildChunkSize
    end
    if request.enqueueChunkSize and request.enqueueChunkSize > 0 then
        state.enqueueChunkSize = request.enqueueChunkSize
    end
    if request.enqueueTimeBudgetMs and request.enqueueTimeBudgetMs > 0 then
        state.enqueueTimeBudgetMs = request.enqueueTimeBudgetMs
    end
    if request.buildTimeBudgetMs and request.buildTimeBudgetMs > 0 then
        state.buildTimeBudgetMs = request.buildTimeBudgetMs
    end
    if request.spawnTimeBudgetMs and request.spawnTimeBudgetMs > 0 then
        state.spawnTimeBudgetMs = request.spawnTimeBudgetMs
    end

    groupLoadManager.state = state

    -- Delay loading start by one tick so the loading UI can render first.
    Cron.NextTick(function ()
        local current = groupLoadManager.state
        if not current.active or current.phase ~= "enqueue" then return end

        local rootData = request.data
        local rootModulePath = rootData.modulePath
        if not rootModulePath and current.targetParent and current.targetParent.getModulePathByType then
            rootModulePath = current.targetParent:getModulePathByType(rootData)
        end
        if not rootModulePath then
            rootModulePath = "modules/classes/editor/positionableGroup"
        end

        local ok, err = pcall(function ()
            local loadedGroup = require(rootModulePath):new(request.spawner.baseUI.spawnedUI)
            loadedGroup:load(pipelineCommon.copyNodeDataWithoutChildren(rootData, current.clearLocks), true)
            captureBaseTransform(current, loadedGroup)
            loadedGroup:setParent(current.targetParent)
            if current.loadHidden then
                loadedGroup:setVisible(false, true)
            end

            -- A loose element as the root is spawned like any child, or it stays silent and never spawns.
            if utils.isA(loadedGroup, "spawnableElement") then
                table.insert(current.entries, loadedGroup)
            end

            current.group = loadedGroup
            current.groupName = loadedGroup.name
            current.buildQueue = {}
            current.buildHead = 1
            current.buildTail = 0
            current.buildProcessed = 0
            current.buildTotal = 0
            current.buildFailed = 0
            current.spawnFailed = 0
            current.rootChildContainer = rootData.childs or {}
            current.rootEnqueueCursor = nil
            current.enqueueProcessed = 0

            if next(current.rootChildContainer) == nil then
                beginBuildPhase()
                return
            end

            current.timer = Cron.OnUpdate(function (timer)
                processEnqueueChunk(timer)
            end)
        end)

        if not ok then
            current.buildFailed = current.buildFailed + 1
            logLoadError("build", current.groupName, err)
            removePartiallyLoadedGroup(current)
            queueToast("warning", 5000, string.format("Failed loading \"%s\": %s", current.groupName, tostring(err)))
            releaseSuppress(current)
            groupLoadManager.state = createLoadState(current)
        end
    end)

    return true
end

---@return boolean
function groupLoadManager.isActive()
    return groupLoadManager.state.active
end

---@param reason string?
---@param suppressToast boolean?
---@return boolean cancelled
function groupLoadManager.cancel(reason, suppressToast)
    local state = groupLoadManager.state
    if not state.active then return false end

    if state.timer then
        Cron.Halt(state.timer)
        state.timer = nil
    end

    removePartiallyLoadedGroup(state)

    if not suppressToast then
        queueToast("warning", 3500, string.format("Cancelled loading \"%s\"%s", getLoadName(state), reason and (" (" .. reason .. ")") or ""))
    end

    releaseSuppress(state)
    groupLoadManager.state = createLoadState(state)
    return true
end

function groupLoadManager.drawToasts()
    pipelineCommon.drawQueuedToasts(groupLoadManager.pendingToasts)
end

---@param style style
---@return boolean drawn
function groupLoadManager.drawProgress(style)
    local state = groupLoadManager.state
    if not state.active then return false end

    local progress = 0
    local phaseText = ""
    local counterText = ""
    local helpText = ""

    if state.phase == "enqueue" then
        -- Indeterminate queue phase: number of root children is not pre-counted
        -- to avoid a full synchronous pass before loading starts.
        progress = (math.sin(Cron.time * 4) + 1) * 0.5
        phaseText = string.format("Queueing \"%s\"", state.groupName)
        counterText = string.format("%d/?", state.enqueueProcessed or 0)
        helpText = "Queueing root entries in chunks to avoid start spikes."
    elseif state.phase == "build" then
        local totalBuild = math.max(1, state.buildTotal)
        progress = state.buildProcessed / totalBuild
        phaseText = string.format("Preparing \"%s\"", state.groupName)
        counterText = string.format("%d/%d", state.buildProcessed, state.buildTotal)
        helpText = "Building hierarchy in chunks to avoid UI stalls."
    else
        local totalSpawn = math.max(1, state.total)
        progress = state.loaded / totalSpawn
        if state.loadHidden then
            phaseText = string.format("Finalizing hidden load \"%s\"", state.groupName)
            helpText = "Finalizing loaded entries without spawning entities."
        else
            phaseText = string.format("Spawning \"%s\"", state.groupName)
            helpText = "Spawning entities in chunks to reduce frame spikes."
        end
        counterText = string.format("%d/%d", state.loaded, state.total)
    end

    pipelineCommon.drawCancelableProgress({
        style = style,
        phaseText = phaseText,
        progress = progress,
        counterText = counterText,
        helpText = helpText,
        onCancel = function ()
            groupLoadManager.cancel("user request")
        end
    })

    return true
end

return groupLoadManager
