local config = require("modules/utils/core/config")
local utils = require("modules/utils/core/utils")
local logger = require("modules/utils/core/logger")
local settings = require("modules/utils/core/settings")
local saveState = require("modules/utils/project/saveState")
local pipelineCommon = require("modules/utils/pipeline/common")

---Keeps one crash-recovery file describing everything in the Spawned tab.
---
---A game crash gives no warning and no chance to flush, so the only defence is a snapshot that is
---already on disk when it happens. This writes one every so often, covering **all** root children --
---saved projects, brand new groups, and loose spawnables pasted at the root alike -- and works
---whether or not auto-save is enabled.
---
---### File layout
---
---One file, as required, but readable in two steps. The index is emitted on the first line:
---
---```
---{"index":{"version":1,"savedAt":"...","entries":[...]},
---"payload":{"New Group":{...}}}
---```
---
---Startup only needs the first line to populate the restore list, so it reads a few KB instead of
---decoding a payload that can run to tens of megabytes. The full decode happens only if the user
---actually restores something.
---
---### ref vs blob
---
---A group already saved to `data/objects/` and matching that file is stored as a `ref` -- just a
---pointer. Only groups that would otherwise be lost carry their full tree as a `blob`. With auto-save
---enabled the file therefore stays tiny; with it disabled the file carries everything, which is
---exactly the case the feature exists for.
local sessionSnapshot = {
    path = "backup/lastSession.json",
    previousPath = "backup/previousSession.json",

    ---Index of the *previous* run's snapshot, parsed at startup, or nil when there is nothing to
    ---restore. The snapshot this run is writing is never offered -- it becomes restorable only after
    ---a restart, when init rotates it into `previousPath`.
    ---@type table?
    available = nil,
    ---Set once the user starts a new session. Hides the banner; does not delete the file.
    consumed = false,

    dirtyQuietAge = 0,
    dirtyMaxAge = 0,
    pending = false,
    lastSeenEpoch = 0,
    lastWriteAt = nil,
    lastError = nil,

    ---@type table? Active write job.
    job = nil
}

local VERSION = 1
---Collapse bursts of edits into one write.
local QUIET_DELAY = 10
---...but never let changes sit unrecorded longer than this.
local MAX_DELAY = 60
local HEADER_READ_BYTES = 64 * 1024

--------------------------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------------------------

---Reads just the index line of a snapshot file.
---
---The writer guarantees the index is the whole of line one, so this reads a bounded prefix, cuts at
---the newline, and closes the object by hand. Falling back to a full decode keeps it working even if
---a file was written by some other means.
---@param path string
---@return table? index
local function readIndex(path)
    local file = io.open(path, "r")
    if not file then return nil end

    local ok, chunk = pcall(function() return file:read(HEADER_READ_BYTES) end)
    file:close()

    if not ok or type(chunk) ~= "string" then return nil end

    local firstLine = chunk:match("^([^\n]*)\n")
    if firstLine then
        -- "{"index":{...}," -> "{"index":{...}}"
        local trimmed = firstLine:gsub(",%s*$", "")
        local decoded
        local decodeOk = pcall(function() decoded = json.decode(trimmed .. "}") end)

        if decodeOk and type(decoded) == "table" and type(decoded.index) == "table" then
            return decoded.index
        end
    end

    -- Header unreadable: fall back to decoding the whole document.
    local full = config.loadFile(path)
    if type(full) == "table" and type(full.index) == "table" then
        return full.index
    end

    return nil
end

sessionSnapshot.readIndex = readIndex

---Closes out the previous run's snapshot and opens a fresh one for this run.
---
---Rotation happens here, at startup, rather than on the first write. That gives "the previous
---session" one fixed meaning for the whole run: whatever the last run left behind. The snapshot this
---run is building is never offered for restore -- it only becomes restorable after the game is
---restarted, at which point it rotates into place itself.
---
---Nothing is rotated when the last run left no snapshot, so launching, doing nothing and quitting
---cannot destroy a recovery point.
function sessionSnapshot.init()
    sessionSnapshot.consumed = false

    -- Unconditional, even when the feature is switched off: if it were skipped and the user enabled
    -- it mid-run, this run's first write would land on top of the last run's snapshot and destroy the
    -- recovery point without ever moving it aside.
    if config.fileExists(sessionSnapshot.path) then
        os.remove(sessionSnapshot.previousPath)
        os.rename(sessionSnapshot.path, sessionSnapshot.previousPath)
    end

    if settings.sessionRestoreEnabled == false then
        sessionSnapshot.available = nil
        return
    end

    local index = readIndex(sessionSnapshot.previousPath)

    if index and type(index.entries) == "table" and #index.entries > 0 then
        sessionSnapshot.available = index
    else
        sessionSnapshot.available = nil
    end
end

---@return boolean
function sessionSnapshot.canOffer()
    return sessionSnapshot.available ~= nil and not sessionSnapshot.consumed
end

---Marks the beginning of a new session. Hides the restore banner -- restoring on top of work already
---in progress would mix two sessions -- but leaves the file readable from the Projects tab.
---@param reason string?
function sessionSnapshot.consume(reason)
    if sessionSnapshot.consumed then return end

    sessionSnapshot.consumed = true
end

--------------------------------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------------------------------

---Signals that something in the hierarchy changed and the snapshot is stale.
---
---Driven by polling `saveState.mutationEpoch` rather than a callback, because saveState is a
---dependency of this module and must not depend back on it.
function sessionSnapshot.markDirty()
    if not sessionSnapshot.pending then
        sessionSnapshot.pending = true
        sessionSnapshot.dirtyMaxAge = 0
    end

    sessionSnapshot.dirtyQuietAge = 0
end

---@param element element
---@return boolean
local function isRestorable(element)
    -- Everything at root level is worth recovering, not just savable groups: a pasted spawnable or a
    -- randomized group sitting at the root is exactly the sort of unsaved work a crash would eat.
    return utils.isA(element, "positionable")
end

---Counts the spawnables under an element, for display in the restore list.
---
---The index is written before any blob has been built, so the count cannot come from the build. This
---is a plain walk with no allocation or encoding -- fast enough to run for every root child up front,
---and it reads a cached count whenever one is available.
---@param element element
---@return integer
local function countSpawnables(element)
    if utils.isA(element, "spawnableElement") then
        return 1
    end

    local cache = element.__jsonCache
    if cache and cache.valid and cache.elementCount then
        return cache.elementCount
    end

    local total = 0
    for _, child in ipairs(element.childs) do
        total = total + countSpawnables(child)
    end

    return total
end

---Builds the work list for one snapshot pass.
---@return table[] entries
local function collectEntries()
    local sUI = saveState.spawnedUI
    if not sUI or not sUI.root then return {} end

    local entries = {}

    for _, child in ipairs(sUI.root.childs) do
        if isRestorable(child) then
            local record = saveState.getRecord(child)
            -- `state`, not `dirty`: dirty is a "needs re-checking" hint only an auto-save pass
            -- clears, so with auto-save off every group would become a full blob. `state` is
            -- maintained synchronously and means exactly "does this still match its file".
            local upToDate = record.projectFile ~= nil and record.state == "clean"

            entries[#entries + 1] = {
                element = child,
                name = child.name,
                projectFile = record.projectFile,
                kind = upToDate and "ref" or "blob",
                elementCount = countSpawnables(child),
                isGroup = utils.isA(child, "positionableGroup")
            }
        end
    end

    return entries
end

---@param job table
---@param text string
---@return boolean ok
local function emit(job, text)
    -- pcall with the method and its arguments, rather than wrapping it in a closure: this runs once
    -- per fragment of a potentially very large document.
    local ok = pcall(job.file.write, job.file, text)
    if not ok then
        job.failed = true
    end
    return ok
end

---@param job table
---@return boolean ok
local function writeIndexLine(job)
    local indexEntries = {}

    for _, entry in ipairs(job.entries) do
        indexEntries[#indexEntries + 1] = {
            name = entry.name,
            kind = entry.kind,
            projectFile = entry.projectFile,
            elementCount = entry.elementCount or 0,
            isGroup = entry.isGroup == true,
            -- "ref" already means "matches its file"; this distinguishes a blob that has a project
            -- file (saved, then edited) from one that was never saved at all.
            wasProject = entry.projectFile ~= nil
        }
    end

    local index = {
        version = VERSION,
        savedAt = os.date("%Y-%m-%d %H:%M:%S"),
        entries = indexEntries
    }

    local encoded, err = config.encodeStableJSON(index)
    if not encoded then
        job.failed = true
        sessionSnapshot.lastError = "index encode failed: " .. tostring(err)
        logger:error("[Session] " .. sessionSnapshot.lastError)
        return false
    end

    -- The trailing newline is what makes the index cheaply readable later; nothing else may contain
    -- one, which holds because the JSON encoder escapes newlines inside strings.
    return emit(job, "{\"index\":" .. encoded .. ",\n\"payload\":{")
end

---Advances the snapshot job for at most one frame budget.
---@param job table
---@param deadline number
---@return boolean done
---@return string? abortReason Set when the pass has to be thrown away rather than committed.
local function stepJob(job, deadline)
    while job.index <= #job.entries do
        local entry = job.entries[job.index]

        if entry.kind == "ref" then
            -- Nothing to serialize: the data is already on disk under projectFile.
            if job.written > 0 then
                emit(job, ",")
            end
            emit(job, config.encodeJSONString(entry.name) .. ":null")
            job.written = job.written + 1
            job.index = job.index + 1
        elseif not job.emitFragment then
            -- Build phase for this entry. The mutation guard only applies here: once the rope exists
            -- it is a snapshot, and emitting it cannot tear.
            if not job.build then
                job.build = saveState.beginBuild(entry.element)
                job.mutationAtStart = saveState.getRecord(entry.element).mutationCounter or 0
            end

            local record = saveState.getRecord(entry.element)
            if (record.mutationCounter or 0) ~= job.mutationAtStart then
                -- Torn snapshot: drop this entry's progress and retry the whole pass later.
                return true, "mutated"
            end

            local status = saveState.stepBuild(job.build, pipelineCommon.remainingMs(deadline))

            if status == "aborted" then
                return true, job.build.aborted or "aborted"
            end

            if status ~= "done" then
                return false
            end

            entry.elementCount = job.build.result.elementCount

            if job.written > 0 then
                emit(job, ",")
            end
            emit(job, config.encodeJSONString(entry.name) .. ":")

            job.emitFragment = saveState.ropeIterator(job.build.result.pieces)
        else
            -- Emit phase, budgeted. This used to drain the whole iterator in one go, which meant a
            -- single unsaved group of any size was written in one frame -- the exact stall the rest of
            -- the pipeline exists to avoid.
            local status = pipelineCommon.streamFragments(job.emitFragment, job.file, deadline)

            if status == "failed" then
                job.failed = true
            elseif status == "running" then
                return false
            else
                job.emitFragment = nil
                job.build = nil
                job.written = job.written + 1
                job.index = job.index + 1
            end
        end

        if job.failed then
            return true, "write_failed"
        end

        if os.clock() >= deadline then
            return false
        end
    end

    return true
end

---@param job table
local function abortJob(job, reason)
    config.abortAtomicWrite(job.file, job.tmpPath)
    job.file = nil
    sessionSnapshot.job = nil

    if reason and reason ~= "mutated" then
        logger:warn("[Session] Snapshot pass abandoned: " .. tostring(reason))
    end

    -- Still pending, so the next debounce window retries.
    sessionSnapshot.pending = true
    sessionSnapshot.dirtyQuietAge = 0
end

---Records a failed write attempt and arms a retry, without flooding the log.
---
---Every failure here leaves the previous snapshot intact -- nothing is promoted -- so retrying is
---always safe, and giving up permanently would let one transient problem disable crash recovery for
---the rest of the session.
---@param reason string
local function reportWriteFailure(reason)
    if sessionSnapshot.lastError ~= reason then
        logger:error("[Session] " .. reason)
    end

    sessionSnapshot.lastError = reason
    sessionSnapshot.pending = true
    sessionSnapshot.dirtyQuietAge = 0
end

---@param job table
local function finishJob(job)
    emit(job, "}}")
    config.closeFileQuietly(job.file)
    job.file = nil

    if job.failed then
        os.remove(job.tmpPath)
        reportWriteFailure("snapshot write failed")
        sessionSnapshot.job = nil
        return
    end

    local promoted, err = config.promoteTempFile(sessionSnapshot.path, job.tmpPath)
    if not promoted then
        os.remove(job.tmpPath)
        reportWriteFailure("could not replace snapshot: " .. tostring(err))
        sessionSnapshot.job = nil
        return
    end

    sessionSnapshot.lastWriteAt = os.clock()
    sessionSnapshot.lastError = nil
    sessionSnapshot.pending = false
    sessionSnapshot.dirtyQuietAge = 0
    sessionSnapshot.dirtyMaxAge = 0
    sessionSnapshot.job = nil
end

---@return boolean started
local function beginJob()
    local entries = collectEntries()

    if #entries == 0 then
        -- Nothing in the tab. Leave any existing recovery file alone rather than replacing it with an
        -- empty one, which would silently throw away a still-useful snapshot.
        sessionSnapshot.pending = false
        return false
    end

    local file, tmpPath, err = config.beginAtomicWrite(sessionSnapshot.path)
    if not file then
        -- Stays pending so the next quiet window retries. Giving up permanently would mean a transient
        -- problem (the file briefly locked, a full disk) silently disabled crash recovery for the rest
        -- of the session.
        reportWriteFailure(config.describeOpenError(tmpPath, err) .. " (crash-recovery snapshot will retry)")
        return false
    end

    local job = {
        entries = entries,
        index = 1,
        written = 0,
        file = file,
        tmpPath = tmpPath,
        build = nil,
        failed = false
    }

    if not writeIndexLine(job) then
        config.abortAtomicWrite(file, tmpPath)
        reportWriteFailure("could not write the snapshot index")
        return false
    end

    sessionSnapshot.job = job
    return true
end

---Advances the snapshot. Call once per frame from onUpdate.
---@param dt number
---@param blocked boolean True while another pipeline or the user is mid-operation.
function sessionSnapshot.update(dt, blocked)
    if settings.sessionRestoreEnabled == false then
        if sessionSnapshot.job then
            abortJob(sessionSnapshot.job, "disabled")
        end
        return
    end

    if sessionSnapshot.job then
        if blocked then return end

        local done, reason = stepJob(sessionSnapshot.job, pipelineCommon.frameDeadline())

        if done then
            if reason then
                abortJob(sessionSnapshot.job, reason)
            else
                finishJob(sessionSnapshot.job)
            end
        end

        return
    end

    if saveState.mutationEpoch ~= sessionSnapshot.lastSeenEpoch then
        sessionSnapshot.lastSeenEpoch = saveState.mutationEpoch
        sessionSnapshot.markDirty()
    end

    if not sessionSnapshot.pending or blocked then return end

    local delta = math.max(tonumber(dt) or 0, 0)
    sessionSnapshot.dirtyQuietAge = sessionSnapshot.dirtyQuietAge + delta
    sessionSnapshot.dirtyMaxAge = sessionSnapshot.dirtyMaxAge + delta

    if sessionSnapshot.dirtyQuietAge >= QUIET_DELAY or sessionSnapshot.dirtyMaxAge >= MAX_DELAY then
        beginJob()
    end
end

---@return boolean
function sessionSnapshot.isActive()
    return sessionSnapshot.job ~= nil
end

return sessionSnapshot
