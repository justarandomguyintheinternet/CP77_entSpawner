local config = require("modules/utils/core/config")
local utils = require("modules/utils/core/utils")
local logger = require("modules/utils/core/logger")
local settings = require("modules/utils/core/settings")
local saveState = require("modules/utils/project/saveState")
local backup = require("modules/utils/project/backup")
local history = require("modules/utils/project/history")
local projectFiles = require("modules/utils/project/projectFiles")
local projectLinkPopup = require("modules/utils/ui/projectLinkPopup")
local pipelineCommon = require("modules/utils/pipeline/common")
local streamingBox = require("modules/utils/pipeline/streamingBox")
local groupLoadManager = require("modules/utils/pipeline/groupLoadManager")
local groupExportManager = require("modules/utils/pipeline/groupExportManager")
local groupAMMImportManager = require("modules/utils/pipeline/groupAMMImportManager")
local sessionSnapshot = require("modules/utils/pipeline/sessionSnapshot")

---Drives auto-save. Turns a root group into its canonical JSON a few milliseconds at a time, and only
---touches the disk when the content hash proves something actually changed.
---
---Unlike the load/export pipelines this does **not** run on Cron: Cron is only pumped while in-game
---and out of menus (see the onUpdate handler in init.lua), which would freeze the auto-save clock
---exactly when someone tabs out to think. Serialization is pure cached Lua -- there is no engine call
---anywhere in the serialize path -- so it is safe to run regardless of game state.
---
---Running from onUpdate also means it never interleaves with ImGui, which draws from onDraw. That
---matters because element:serialize hands out live UI-state tables.
local persistenceManager = {
    ---@type table? Active job, or nil when idle.
    job = nil,
    pendingToasts = {},

    lastPassAt = 0,
    lastAutoSaveAt = nil,
    lastAutoSaveName = nil,

    ---Round-robin cursor over root children, so one slow group cannot starve the others.
    cursor = 1,

    ---Groups the user explicitly asked to save, waiting their turn. Always drained before auto-save
    ---work: this is what someone is actually watching for.
    ---@type element[]
    manualQueue = {},
    ---Tally for the one summary notification a batch produces, instead of one per group.
    manualBatch = { total = 0, saved = 0, failed = 0, updatedInExport = 0 },
    ---Retry counts for explicit saves abandoned mid-build, keyed by element id.
    manualAttempts = {},

    ---Mirrors history.propBeingEdited so the falling edge of a drag can be detected.
    wasEditing = false,

    stats = { saved = 0, skipped = 0, aborted = 0, failed = 0 }
}

---How often stale records are swept, regardless of whether auto-save is running.
local PRUNE_INTERVAL_SECONDS = 30

---@param kind string
---@param duration number
---@param text string
local function queueToast(kind, duration, text)
    pipelineCommon.queueToast(persistenceManager.pendingToasts, kind, duration, text)
end

---@return number
local function quietSeconds()
    return math.max(0, math.min(tonumber(settings.autoSaveQuietSeconds) or 2, 10))
end

---@return number
local function intervalSeconds()
    return math.max(30, (tonumber(settings.autoSaveIntervalMinutes) or 5) * 60)
end

---Whether another pipeline, or the user, is mid-operation.
---
---Treats any other active pipeline as a hard block regardless of its apparent progress: they run on
---Cron, which is frozen while this is not, so "active" there can mean "active and paused".
---@return boolean blocked
---@return string? reason Human-readable cause, for the diagnostics readout.
function persistenceManager.isBlocked()
    if history.propBeingEdited then return true, "a property is being edited" end
    if history.active ~= nil or #history.pending > 0 then return true, "undo/redo is running" end
    if groupLoadManager.isActive() then return true, "a group is loading" end
    if groupExportManager.isActive and groupExportManager.isActive() then return true, "an export is running" end
    if groupAMMImportManager.isActive and groupAMMImportManager.isActive() then return true, "an AMM import is running" end

    return false, nil
end

---@return boolean
function persistenceManager.isActive()
    return persistenceManager.job ~= nil
end

--------------------------------------------------------------------------------------------------
-- Job lifecycle
--------------------------------------------------------------------------------------------------

---@param job table
---@param reason string
local function discardJob(job, reason)
    config.abortAtomicWrite(job.file, job.tmpPath)
    job.file = nil

    local record = job.record
    if record then
        record.state = record.projectFile and (record.dirty and "edited" or "clean") or "new"
    end

    if persistenceManager.job == job then
        persistenceManager.job = nil
    end

    -- An automatic pass that gets abandoned simply runs again next interval. An explicit save cannot
    -- just evaporate, so it goes back in the queue -- but only a couple of times, or a group being
    -- edited continuously would retry forever and never let the batch finish.
    if job.manual then
        local attempts = job.attempts or 1
        if attempts < 3 and saveState.isSavableRootGroup(job.root) then
            persistenceManager.manualAttempts[job.root.id] = attempts + 1
            persistenceManager.manualQueue[#persistenceManager.manualQueue + 1] = job.root
        else
            persistenceManager.manualAttempts[job.root.id] = nil
            persistenceManager.manualBatch.failed = persistenceManager.manualBatch.failed + 1
            logger:error("[Persistence] Gave up saving \"" .. tostring(job.name) .. "\": " .. tostring(reason))
        end
    end

    if reason ~= "structure_changed" then
        logger:info("[Persistence] Discarded job for \"" .. tostring(job.name) .. "\": " .. tostring(reason))
    end
end

---Begins a pass over one root group. An automatic pass only ends in a write when the content hash
---says the file is out of date; a manual one always writes, because the user asked it to.
---@param rootChild element
---@param record table
---@param manual boolean? True for a user-requested save.
---@return table job
local function beginJob(rootChild, record, manual)
    local job = {
        root = rootChild,
        record = record,
        name = rootChild.name,
        manual = manual == true,
        phase = "build",
        startedAt = os.clock(),
        mutationAtStart = record.mutationCounter or 0,
        -- Held on the job so a verification rebuild reproduces the same document, timestamp included.
        -- The field is excluded from the content hash, so it never reads as a change.
        extraRootFields = { lastEditedAt = os.date("%Y-%m-%d %H:%M:%S") }
    }

    job.build = saveState.beginBuild(rootChild, { extraRootFields = job.extraRootFields })
    record.state = "saving"

    return job
end

---Decides whether the freshly computed hash means a write, a silent baseline adoption, or nothing.
---@param job table
---@return string outcome `"write"`, `"baseline"`, or `"unchanged"`
local function classifyResult(job)
    local record = job.record
    local hash = job.build.result.contentHash

    if job.manual then
        -- The user pressed save. Write, even if the content is byte-identical: a save that quietly
        -- does nothing is indistinguishable from a save that failed.
        return "write"
    end

    if record.needsBaseline then
        -- The group was just loaded from, or saved to, this file and untouched since, so whatever it
        -- hashes to now is the on-disk state: adopt it instead of rewriting the file. Relies on
        -- `saveState.markDirty` clearing this the instant anything is edited.
        --
        -- "Untouched" means by the user. Entity assembly lands here asynchronously, well after a load
        -- finishes, and re-derives serialized fields; it marks derived rather than dirty precisely so
        -- it is folded into this baseline instead of counting as an edit.
        return "baseline"
    end

    if record.lastSavedContentHash == hash then
        return "unchanged"
    end

    return "write"
end

---@param job table
---@return boolean ok
local function openWriteTarget(job)
    local record = job.record

    -- Automatic saves only ever touch the file the group is already bound to. A manual save may be
    -- the group's first, in which case the name on screen picks the file name -- once, and only when
    -- nothing else already answers to it; otherwise the user is asked rather than guessed at.
    local fileName = record.projectFile
    if not fileName and job.manual then
        local resolved, suggestion, takenBy = projectFiles.resolveSaveTarget(nil, job.root.name)

        if not resolved then
            job.nameConflict = { suggestion = suggestion, takenBy = takenBy }
            return false
        end

        fileName = resolved
    end
    if not fileName then return false end

    job.fileName = fileName
    job.targetPath = projectFiles.getPath(fileName)

    -- Only for explicit saves: this is what "Restore previous save" in the Projects tab rolls back to,
    -- so it has to mean "before the last save the user made", not "before some timer fired".
    if job.manual then
        job.hadBackup = backup.backupObjectBeforeSave(fileName)
    end

    local file, tmpPath, err = config.beginAtomicWrite(job.targetPath)
    job.tmpPath = tmpPath

    if not file then
        record.lastError = "could not open " .. tmpPath .. ": " .. tostring(err)
        logger:error("[Persistence] " .. record.lastError)
        return false
    end

    job.file = file
    job.nextFragment = saveState.ropeIterator(job.build.result.pieces)
    job.bytesWritten = 0

    return true
end

---Streams the rope into the temp file for at most one frame budget.
---@param job table
---@param deadline number
---@return boolean done True when the document is fully written, or when writing failed.
local function stepWrite(job, deadline)
    local status, written, err = pipelineCommon.streamFragments(job.nextFragment, job.file, deadline)
    job.bytesWritten = job.bytesWritten + written

    if status == "failed" then
        job.record.lastError = "write failed: " .. tostring(err)
        logger:error("[Persistence] " .. job.record.lastError)
        job.failed = true
        return true
    end

    return status == "done"
end

---Collects the handful of top-level facts the Projects tab and the export list need, without keeping
---(or re-reading) the whole document.
---@param job table
---@return table summary
local function buildSummary(job)
    local root = job.root
    local childs = {}

    for _, child in ipairs(root.childs) do
        childs[#childs + 1] = { name = child.name, modulePath = child.modulePath }
    end

    local pos = nil
    local okPos, position = pcall(root.getPosition, root)
    if okPos and position then
        pos = { x = position.x, y = position.y, z = position.z, w = position.w or 0 }
    end

    local okCenter, streamingCenter = pcall(function ()
        return streamingBox.getContentCenter(streamingBox.collectExported(root))
    end)

    return {
        -- Read by the Export tab, whose streaming box is centered on the exported content.
        streamingCenter = okCenter and streamingCenter or nil,
        name = root.name,
        elementCount = job.build.result.elementCount,
        lastEditedAt = os.date("%Y-%m-%d %H:%M:%S"),
        pos = pos,
        origin = pos,
        -- Copied, not referenced: this lands in savedUI's cache, which can be written back to disk.
        -- Sharing the element's own table would let later edits to the group leak into the Projects
        -- tab entry. element:save avoided this by going through normalizeProjectData, which copies.
        project = utils.deepcopy(root.project),
        childs = childs
    }
end

---@param job table
local function finishWrite(job)
    local record = job.record

    config.closeFileQuietly(job.file)
    job.file = nil

    local function fail(reason)
        os.remove(job.tmpPath)

        -- Put back what was there before, so a failed explicit save does not leave the file missing
        -- or half-replaced. Mirrors element:save.
        if job.manual and job.hadBackup then
            backup.restoreObjectBackup("on_save", job.fileName)
        end

        if reason then
            record.lastError = reason
            logger:error("[Persistence] " .. reason)
        end

        record.state = "error"
        persistenceManager.stats.failed = persistenceManager.stats.failed + 1
        if job.manual then
            persistenceManager.manualBatch.failed = persistenceManager.manualBatch.failed + 1
        end
        persistenceManager.job = nil
    end

    if job.failed then
        fail(nil)
        return
    end

    local promoted, err = config.promoteTempFile(job.targetPath, job.tmpPath)
    if not promoted then
        fail("could not replace " .. job.targetPath .. ": " .. tostring(err))
        return
    end

    if job.manual then
        -- Takes ownership of the file (a manual save is what decides which group owns a name), then
        -- records the hash we just wrote so the next automatic pass has a baseline already.
        saveState.markManuallySaved(job.root, job.fileName)
    end
    saveState.markSaved(job.root, job.build.result.contentHash)

    -- The mutation guard only covers the build, but writing spans many frames. If the group changed
    -- during the write the file is still a valid older snapshot, so keep its hash as the baseline
    -- but leave the group flagged, or that edit would look saved and never reach disk.
    if (record.mutationCounter or 0) ~= job.mutationAtStart then
        record.dirty = true
        record.state = "edited"
    end

    local summary = buildSummary(job)
    local baseUI = job.root.sUI and job.root.sUI.spawner and job.root.sUI.spawner.baseUI
    local updatedInExport = 0

    if baseUI then
        if baseUI.savedUI and baseUI.savedUI.refreshEntryShallow then
            pcall(baseUI.savedUI.refreshEntryShallow, job.fileName, summary)
        end
        if baseUI.exportUI and baseUI.exportUI.syncGroupFromData then
            local ok, synced = pcall(baseUI.exportUI.syncGroupFromData, job.fileName, summary)
            if ok then
                updatedInExport = synced or 0
            end
        end
    end

    persistenceManager.stats.saved = persistenceManager.stats.saved + 1

    if job.manual then
        local batch = persistenceManager.manualBatch
        batch.saved = batch.saved + 1
        batch.updatedInExport = batch.updatedInExport + updatedInExport
    else
        persistenceManager.lastAutoSaveAt = os.clock()
        persistenceManager.lastAutoSaveName = job.root.name

        if settings.autoSaveShowToasts then
            queueToast("success", 2000, string.format("Auto-saved \"%s\"", job.root.name))
        end
    end

    persistenceManager.job = nil
end

---Whether this pass should re-derive the group from scratch and check the cache told the truth.
---
---A missed invalidation is the one failure mode that writes *wrong* data rather than merely late
---data, so it is worth paying for periodically -- but the check must obey the frame budget like
---everything else, which is why it runs as a job phase rather than a synchronous rebuild.
---
---This compares content hashes, not bytes. That catches a stale cache, which is data-dependent and
---can appear at any time. It does not compare against `config.saveFile`'s encoder, because encoder
---agreement is a static property of the code: `saveState.verify` checks that on demand instead.
---@param job table
---@return boolean
local function shouldVerify(job)
    local record = job.record
    local every = math.max(0, math.floor(tonumber(settings.autoSaveVerifyEvery) or 4))

    if not saveState.cacheEnabled then
        return false
    end

    if record.savesSinceVerify == nil then
        return true
    end

    return every > 0 and record.savesSinceVerify >= every
end

---Handles the result of the verification rebuild.
---@param job table
local function finishVerify(job)
    local record = job.record
    record.savesSinceVerify = 0

    local fresh = job.verifyBuild.result
    local cachedHash = job.build.result.contentHash

    if fresh and fresh.contentHash == cachedHash then
        -- Cache was honest. Keep using its rope, which is already built.
        job.verifyBuild = nil
        return
    end

    logger:warn(string.format(
        "[Persistence] Cache check failed for \"%s\": cached hash %s, rebuilt %s. Writing the rebuilt data.",
        job.root.name, tostring(cachedHash), tostring(fresh and fresh.contentHash)))

    if fresh then
        -- The cache-free build already replaced every cache entry on its way through, so simply using
        -- its result both fixes this write and repairs the cache.
        job.build.result = fresh
    end

    queueToast("warning", 6000, string.format("Rebuilt \"%s\" from scratch (cache check failed)", job.root.name))
    job.verifyBuild = nil
end

--------------------------------------------------------------------------------------------------
-- Scheduling
--------------------------------------------------------------------------------------------------

---Queues a group for an explicit save.
---
---Returns false when the pipeline cannot take it, which callers use to fall back to the synchronous
---`element:save`. A save the user asked for must never silently not happen.
---@param rootChild element
---@return boolean queued
function persistenceManager.enqueueManualSave(rootChild)
    if not saveState.isSavableRootGroup(rootChild) then return false end

    for _, queued in ipairs(persistenceManager.manualQueue) do
        if queued == rootChild then return true end
    end

    if persistenceManager.job and persistenceManager.job.manual and persistenceManager.job.root == rootChild then
        return true
    end

    persistenceManager.manualQueue[#persistenceManager.manualQueue + 1] = rootChild
    persistenceManager.manualBatch.total = persistenceManager.manualBatch.total + 1

    return true
end

---True while explicit saves are still queued or running.
---@return boolean
function persistenceManager.isSavingManually()
    return #persistenceManager.manualQueue > 0
        or (persistenceManager.job ~= nil and persistenceManager.job.manual)
end

---Emits the single notification a batch of explicit saves produces, once the last one lands.
local function finishManualBatch()
    local batch = persistenceManager.manualBatch
    if batch.total == 0 then return end

    local msg
    if batch.total == 1 and batch.saved == 1 then
        msg = string.format("Saved group \"%s\"", tostring(persistenceManager.lastManualName))
        if batch.updatedInExport == 1 then
            msg = msg .. " and updated it in export list"
        elseif batch.updatedInExport > 1 then
            msg = msg .. string.format(" and updated %d entries in export list", batch.updatedInExport)
        end
    else
        msg = string.format("Saved %d root group%s", batch.saved, batch.saved == 1 and "" or "s")
        if batch.failed > 0 then
            msg = msg .. string.format(", %d failed", batch.failed)
        end
        if batch.updatedInExport > 0 then
            msg = msg .. string.format(" and updated %d export list entr%s",
                batch.updatedInExport, batch.updatedInExport == 1 and "y" or "ies")
        end
    end

    queueToast(batch.failed > 0 and "error" or "success", 2500, msg)

    batch.total = 0
    batch.saved = 0
    batch.failed = 0
    batch.updatedInExport = 0
end

---Starts the next queued explicit save, skipping entries that left the tree meanwhile.
---@return boolean started
local function startNextManualSave()
    while #persistenceManager.manualQueue > 0 do
        local rootChild = table.remove(persistenceManager.manualQueue, 1)

        if saveState.isSavableRootGroup(rootChild) then
            persistenceManager.lastManualName = rootChild.name
            local job = beginJob(rootChild, saveState.getRecord(rootChild), true)
            job.attempts = persistenceManager.manualAttempts[rootChild.id] or 1
            persistenceManager.manualAttempts[rootChild.id] = nil
            persistenceManager.job = job
            return true
        end

        persistenceManager.manualBatch.total = math.max(0, persistenceManager.manualBatch.total - 1)
    end

    return false
end

---Picks the next root group worth processing, round-robin so no group starves.
---@return element? rootChild Eligible group, or nil when none is ready right now.
---@return table? record
---@return boolean anyPending Whether a modified group exists but is still inside its quiet window.
local function pickCandidate()
    local sUI = saveState.spawnedUI
    if not sUI or not sUI.root then return nil, nil, false end

    local childs = sUI.root.childs
    local count = #childs
    if count == 0 then return nil, nil, false end

    local quiet = quietSeconds()
    local now = os.clock()
    local anyPending = false

    if persistenceManager.cursor > count then
        persistenceManager.cursor = 1
    end

    for offset = 0, count - 1 do
        local index = ((persistenceManager.cursor - 1 + offset) % count) + 1
        local child = childs[index]

        if saveState.isSavableRootGroup(child) then
            local record = saveState.getRecord(child)

            if record.projectFile and record.dirty then
                if (now - (record.lastMutationTime or 0)) >= quiet then
                    persistenceManager.cursor = (index % count) + 1
                    return child, record, true
                end

                anyPending = true
            end
        end
    end

    return nil, nil, anyPending
end

---@param dt number
local function stepJob(job, dt)
    local deadline = pipelineCommon.frameDeadline()

    -- This group changed under us, so anything built so far is a torn snapshot. Costs one integer
    -- compare, and is per group so editing elsewhere cannot starve a slow one. The structural guard
    -- inside the build is the backstop for mutations no hook reported.
    if (job.phase == "build" or job.phase == "verify")
        and (job.record.mutationCounter or 0) ~= job.mutationAtStart then
        discardJob(job, "mutated_during_build")
        return
    end

    if job.phase == "build" then
        local status = saveState.stepBuild(job.build, pipelineCommon.remainingMs(deadline))

        if status == "aborted" then
            persistenceManager.stats.aborted = persistenceManager.stats.aborted + 1
            discardJob(job, job.build.aborted or "aborted")
            return
        end

        if status ~= "done" or not job.build.result then
            return
        end

        local outcome = classifyResult(job)

        if outcome ~= "write" then
            -- Either nothing really changed, or this is the first pass after a load/manual save and we
            -- are just recording what the file already contains. Both end the same way: no disk write.
            saveState.markSaved(job.root, job.build.result.contentHash)
            persistenceManager.stats.skipped = persistenceManager.stats.skipped + 1
            persistenceManager.job = nil
            return
        end

        if shouldVerify(job) then
            job.verifyBuild = saveState.beginBuild(job.root, {
                ignoreCache = true,
                extraRootFields = job.extraRootFields
            })
            job.phase = "verify"
        else
            job.record.savesSinceVerify = (job.record.savesSinceVerify or 0) + 1
            job.phase = "openWrite"
        end
    end

    if job.phase == "verify" then
        local status = saveState.stepBuild(job.verifyBuild, pipelineCommon.remainingMs(deadline))

        if status == "aborted" then
            persistenceManager.stats.aborted = persistenceManager.stats.aborted + 1
            discardJob(job, job.verifyBuild.aborted or "aborted_during_verify")
            return
        end

        if status ~= "done" then
            return
        end

        finishVerify(job)
        job.phase = "openWrite"
    end

    if job.phase == "openWrite" then
        if not openWriteTarget(job) then
            if job.nameConflict then
                -- Not an error: the group has simply never been saved and the file name its name
                -- points at belongs to someone else. Hand it to the user instead of picking for
                -- them, and leave the group exactly as it was.
                job.record.state = "new"
                projectLinkPopup.requestConflict(job.root, job.nameConflict.suggestion, job.nameConflict.takenBy)

                if job.manual then
                    persistenceManager.manualBatch.total = math.max(0, persistenceManager.manualBatch.total - 1)
                end

                persistenceManager.job = nil
                return
            end

            job.record.state = "error"
            persistenceManager.stats.failed = persistenceManager.stats.failed + 1
            -- Counted so the batch summary reports it. Deliberately not retried: a path that cannot
            -- be opened now will not open on the next attempt either.
            if job.manual then
                persistenceManager.manualBatch.failed = persistenceManager.manualBatch.failed + 1
            end
            persistenceManager.job = nil
            return
        end

        job.phase = "write"
    end

    if job.phase == "write" then
        if stepWrite(job, deadline) then
            finishWrite(job)
        end
    end
end

---Advances the pipeline. Call once per frame from onUpdate, outside any in-game/menu gate.
---@param dt number
function persistenceManager.update(dt)
    saveState.cacheEnabled = settings.autoSaveCacheEnabled ~= false
    saveState.updateWatchdog(persistenceManager.isActive() or groupLoadManager.isActive())

    -- A property drag pushes one history action on its first frame and then keeps mutating silently.
    -- Re-mark on the falling edge, or the value the user actually released on could stay uncaptured.
    local editing = history.propBeingEdited == true
    if persistenceManager.wasEditing and not editing then
        saveState.markDirty(history.lastEditedElement)
    end
    persistenceManager.wasEditing = editing

    local blocked = persistenceManager.isBlocked()

    -- One job at a time across every feature: they share the frame budget, and two streams writing
    -- at once would just make each finish later.
    if persistenceManager.job then
        if blocked then return end
        stepJob(persistenceManager.job, dt)
        return
    end

    -- Explicit saves come first. Someone is waiting on these; auto-save and snapshots are not urgent.
    if #persistenceManager.manualQueue > 0 then
        if blocked then return end
        startNextManualSave()
        return
    end

    finishManualBatch()

    sessionSnapshot.update(dt, blocked)
    if sessionSnapshot.isActive() then return end

    if blocked then return end

    -- Independent of auto-save: records outlive their elements by design, so without this they would
    -- accumulate for the whole session whenever auto-save is off, and a removed group would keep
    -- holding a claim on its project file until something happened to ask for it.
    local now = os.clock()
    if (now - (persistenceManager.lastPruneAt or 0)) >= PRUNE_INTERVAL_SECONDS then
        persistenceManager.lastPruneAt = now

        local sUI = saveState.spawnedUI
        if sUI and sUI.root then
            saveState.pruneRecords(sUI.root.childs)
        end
    end

    -- Auto-save off means no passes at all; indicators stay correct anyway, since markDirty flips a
    -- group to "edited" on touch. Resetting the clock makes re-enabling run a pass immediately.
    if settings.autoSaveEnabled ~= true then
        persistenceManager.lastPassAt = 0
        return
    end

    if (now - persistenceManager.lastPassAt) < intervalSeconds() then return end

    local rootChild, record, anyPending = pickCandidate()

    if rootChild and record then
        -- Note the interval clock is *not* restarted here. Once a pass opens it drains every modified
        -- group back to back; waiting a full interval between them would mean the last of five groups
        -- saved five intervals late.
        persistenceManager.job = beginJob(rootChild, record)
        return
    end

    if not anyPending then
        -- Everything is settled: close the pass and restart the interval.
        persistenceManager.lastPassAt = now
    end
    -- Otherwise something is modified but still inside its quiet window; re-check next frame.
end

---Completes every explicit save that is still queued or in flight, synchronously.
---
---Called on shutdown. A queued save is work the user asked for and believes is happening, so it must
---survive a mod reload; blocking is acceptable here because nothing is being drawn any more. An
---in-flight write is abandoned rather than finished -- its `.tmp` was never promoted, so redoing it
---through `element:save` is both simpler and safer than trying to resume it.
---@return integer flushed
function persistenceManager.flushPendingManualSaves()
    local pending = {}

    local job = persistenceManager.job
    if job and job.manual then
        config.abortAtomicWrite(job.file, job.tmpPath)
        persistenceManager.job = nil
        pending[#pending + 1] = job.root
    end

    for _, rootChild in ipairs(persistenceManager.manualQueue) do
        pending[#pending + 1] = rootChild
    end

    persistenceManager.manualQueue = {}
    persistenceManager.manualBatch = { total = 0, saved = 0, failed = 0, updatedInExport = 0 }
    persistenceManager.manualAttempts = {}

    for _, rootChild in ipairs(pending) do
        if saveState.isSavableRootGroup(rootChild) then
            -- showToast = false: this runs outside any draw event, where ImGui must not be touched.
            -- autoResolveName: there is nobody left to answer a file name conflict, and writing the
            -- group to the next free name beats dropping a save the user already asked for.
            local ok, err = pcall(rootChild.save, rootChild, false, { autoResolveName = true })
            if not ok then
                logger:error("[Persistence] Shutdown save of \"" .. tostring(rootChild.name) .. "\" failed: " .. tostring(err))
            end
        end
    end

    if #pending > 0 then
        logger:info("[Persistence] Flushed " .. tostring(#pending) .. " pending save(s) on shutdown")
    end

    return #pending
end

---Opens the interval gate so the next update starts a pass immediately.
---Does not bypass the idle window or the blocked checks -- it only skips the wait.
function persistenceManager.runNow()
    persistenceManager.lastPassAt = 0
end

---One-line summary of what the pipeline is doing and why, for the diagnostics readout.
---@return string
function persistenceManager.describeState()
    local job = persistenceManager.job
    if job then
        return string.format("%s \"%s\" (%s)", job.manual and "Saving" or "Working on",
            tostring(job.name), tostring(job.phase))
    end

    if #persistenceManager.manualQueue > 0 then
        return string.format("%d group(s) queued to save", #persistenceManager.manualQueue)
    end

    local blocked, reason = persistenceManager.isBlocked()
    if blocked then
        return "Waiting: " .. tostring(reason)
    end

    if settings.autoSaveEnabled ~= true then
        return "Auto-save off (state is still tracked for the indicators)"
    end

    local remaining = persistenceManager.secondsUntilNextPass()
    if remaining > 0 then
        return string.format("Idle, next pass in %ds", math.floor(remaining))
    end

    return "Idle, scanning for modified groups"
end

---@return number seconds Time until the next pass, or 0 when one is due or running.
function persistenceManager.secondsUntilNextPass()
    if persistenceManager.job then return 0 end
    return math.max(0, intervalSeconds() - (os.clock() - persistenceManager.lastPassAt))
end

function persistenceManager.drawToasts()
    pipelineCommon.drawQueuedToasts(persistenceManager.pendingToasts)
end

---@return string? label Progress text for the toolbar, or nil when idle.
function persistenceManager.getProgressLabel()
    local job = persistenceManager.job
    local queued = #persistenceManager.manualQueue

    if not job then
        if queued > 0 then
            return string.format("Saving... %d queued", queued)
        end
        return nil
    end

    local suffix = queued > 0 and string.format(" (+%d queued)", queued) or ""

    if job.phase == "write" then
        return string.format("Saving \"%s\"... %d KB%s", job.name, math.floor(job.bytesWritten / 1024), suffix)
    end

    return string.format("%s \"%s\"... %d nodes%s",
        job.manual and "Saving" or "Checking", job.name, job.build.nodesVisited, suffix)
end

return persistenceManager
