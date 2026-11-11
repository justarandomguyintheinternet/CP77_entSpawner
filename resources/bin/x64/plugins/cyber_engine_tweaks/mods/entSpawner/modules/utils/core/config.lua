local logger = require("modules/utils/core/logger")
local pathOrigin = require("modules/utils/data/pathOrigin")
config = {}

---@class ConfigSpawnFileEntry
---@field data any spawn payload extracted from `spawnable` in a JSON file
---@field lastSpawned any always initialized to `nil` by the loader
---@field name string display name read from the JSON payload
---@field fileName string logical file identifier (currently the same value as `name`)

---@class ConfigSpawnPathEntry
---@field data ConfigSpawnPathData wrapper holding one list line as spawn data
---@field lastSpawned any always initialized to `nil` by the loader
---@field name string parsed spawn path
---@field fileName string file name extracted from `name`

---@class ConfigSpawnPathData
---@field spawnData string raw spawn path read from a `.txt` line
---@field deviceClassName string? optional device class name parsed from list line (`{className} {path}`)

---Checks whether a file can be opened for reading.
---@param filename string Relative or absolute file path.
---@return boolean exists `true` when the file exists and is readable.
function config.fileExists(filename)
    local f=io.open(filename,"r")
    if (f~=nil) then io.close(f) return true else return false end
end

---Reads the full text content of a file.
---Unlike `config.loadRaw`, this returns `nil` instead of erroring when the file is missing.
---@param path string Relative or absolute file path.
---@return string? content Full file content, or `nil` when the file cannot be opened.
function config.readAll(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end

    local content = file:read("*a")
    file:close()
    return content
end

local readAll = config.readAll

---Key names a `dir()` entry may use for its modification timestamp, in priority order.
local ENTRY_TIME_KEYS = {
    "modified",
    "modifiedAt",
    "lastModified",
    "lastModifiedAt",
    "modificationTime",
    "writeTime",
    "lastWriteTime",
    "mtime",
    "time",
    "timestamp"
}

---Finds the first timestamp-like value on a `dir()` entry.
---Tries the known key names first, then any string key mentioning time/date/modif.
---The caller supplies the normalizer, because callers disagree on how raw values
---(epoch seconds, FILETIME, numeric strings, ...) should be interpreted and formatted.
---@param entry table? Directory entry as returned by CET's `dir()`.
---@param normalizeTimeValue fun(value: any): string? Returns the formatted timestamp, or `nil` to keep searching.
---@return string? timestamp First value the normalizer accepted, or `nil`.
function config.getEntryTimeValue(entry, normalizeTimeValue)
    if type(entry) ~= "table" then
        return nil
    end

    for _, key in ipairs(ENTRY_TIME_KEYS) do
        local normalized = normalizeTimeValue(entry[key])
        if normalized then
            return normalized
        end
    end

    for key, value in pairs(entry) do
        if type(key) == "string" then
            local lowered = key:lower()
            if lowered:find("time", 1, true) or lowered:find("date", 1, true) or lowered:find("modif", 1, true) then
                local normalized = normalizeTimeValue(value)
                if normalized then
                    return normalized
                end
            end
        end
    end

    return nil
end

---Writes text content to a file in one pass.
---@param path string Relative or absolute destination path.
---@param content string Raw text to write.
---@return boolean success `true` when write completes.
---@return string? err Error code/message when write fails (`open_failed` or runtime error text).
local function writeAll(path, content)
    local file = io.open(path, "w")
    if not file then
        return false, "open_failed"
    end

    local ok, err = pcall(function ()
        file:write(content)
    end)
    file:close()

    if not ok then
        os.remove(path)
        return false, tostring(err)
    end

    return true
end

---Promotes a temporary file to the final target path.
---Attempts direct rename first, then falls back to a `.swap` replacement flow.
---@param path string Final destination path.
---@param tmpPath string Temporary file path created by `saveFile`.
---@return boolean success `true` when the temporary file becomes the target file.
---@return string? err Error code when replacement fails (`swap_failed` or `promote_failed`).
local function replaceFile(path, tmpPath)
    if os.rename(tmpPath, path) then
        return true
    end

    local swapPath = path .. ".swap"
    local hasTarget = config.fileExists(path)

    if hasTarget then
        if config.fileExists(swapPath) then
            os.remove(swapPath)
        end

        if not os.rename(path, swapPath) then
            return false, "swap_failed"
        end
    end

    if os.rename(tmpPath, path) then
        if hasTarget then
            os.remove(swapPath)
        end
        return true
    end

    if hasTarget and config.fileExists(swapPath) then
        os.rename(swapPath, path)
    end

    return false, "promote_failed"
end

---Recovers from interrupted swap-based replacement.
---If `path.swap` exists and `path` is missing, the swap file is restored.
---@param path string Final destination path without the `.swap` suffix.
local function recoverSwapFile(path)
    local swapPath = path .. ".swap"
    if not config.fileExists(swapPath) then
        return
    end

    if config.fileExists(path) then
        os.remove(swapPath)
        return
    end

    os.rename(swapPath, path)
end

-- Public aliases of the crash-safe write primitives, for callers that stream their own bytes into a
-- `.tmp` file instead of handing a table to `config.saveFile` (see the persistence pipeline).
-- The locals above stay in use internally so existing call sites keep their direct upvalue access.

---Writes text content to a file in one pass. Returns `success, err`.
config.writeAll = writeAll

---Promotes a temporary file to a final path, with `.swap` fallback and rollback. Returns `success, err`.
config.promoteTempFile = replaceFile

---Recovers from an interrupted swap-based replacement at a path.
config.recoverSwapFile = recoverSwapFile

---Closes a file handle, ignoring any error.
---A close can throw on a handle whose write already failed, and every caller here is already on an
---error path or about to drop the handle anyway.
---@param file file*? Handle to close. `nil` is a no-op.
function config.closeFileQuietly(file)
    if not file then return end
    pcall(file.close, file)
end

---Opens the temporary file for a crash-safe streamed write.
---
---The counterpart of `config.promoteTempFile`: callers that stream their own bytes (rather than
---handing a table to `config.saveFile`) write here first and promote on success, so an interrupted
---write can never leave the real file truncated. Any leftover `.swap` from a previous interrupted
---promotion is recovered first, and a stale `.tmp` is cleared.
---@param path string Final destination path.
---@return file*? file Open write handle, or `nil` when it could not be opened.
---@return string tmpPath The temporary path, whether or not the open succeeded.
---@return string? err Error text when the open failed.
function config.beginAtomicWrite(path)
    local tmpPath = path .. ".tmp"

    recoverSwapFile(path)
    os.remove(tmpPath)

    local file, err = io.open(tmpPath, "w")
    if not file and config.isHandleLimitError(err) then
        -- Finalizes file handles left unclosed in the Lua state, then retries once.
        collectgarbage("collect")
        file, err = io.open(tmpPath, "w")
    end

    if not file then
        return nil, tmpPath, tostring(err)
    end

    return file, tmpPath, nil
end

---@param err any Error returned by `io.open`.
---@return boolean
function config.isHandleLimitError(err)
    return type(err) == "string" and err:lower():find("too many open files", 1, true) ~= nil
end

---Readable reason for a failed `io.open` of `path`.
---@param path string
---@param err any Error returned by `io.open`.
---@return string
function config.describeOpenError(path, err)
    if config.isHandleLimitError(err) then
        return "could not open " .. path .. ": the game process has reached its open-file limit, which is shared by all mods "
            .. "(usually another mod not closing its files). The existing file is unchanged; restarting the game clears it"
    end

    local text = tostring(err)
    local prefix = path .. ": "
    if text:sub(1, #prefix) == prefix then
        text = text:sub(#prefix + 1)
    end

    return "could not open " .. path .. ": " .. text
end

---Throws away an in-progress streamed write. The destination file is left exactly as it was.
---@param file file*?
---@param tmpPath string?
function config.abortAtomicWrite(file, tmpPath)
    config.closeFileQuietly(file)

    if tmpPath then
        os.remove(tmpPath)
    end
end

---Cleans up write artifacts left behind by an interrupted save (typically a game crash mid-write).
---Deletes orphaned `.tmp` files and completes any pending `.swap` replacement. `config.loadFile`
---recovers `.swap` per file as it reads, but nothing ever removed stale `.tmp` files.
---@param directory string Directory to sweep, without a trailing slash.
---@return integer removed Number of stale temp files deleted.
function config.sweepTempFiles(directory)
    local ok, entries = pcall(dir, directory)
    if not ok or type(entries) ~= "table" then
        return 0
    end

    local removed = 0

    for _, entry in pairs(entries) do
        local name = entry.name
        if type(name) == "string" then
            if name:sub(-4) == ".tmp" then
                if os.remove(directory .. "/" .. name) then
                    removed = removed + 1
                end
            elseif name:sub(-5) == ".swap" then
                recoverSwapFile(directory .. "/" .. name:sub(1, -6))
            end
        end
    end

    return removed
end

---Creates a JSON config file only when it does not already exist.
---@param path string Destination JSON path.
---@param data table<string, any> Default payload used when creating the file.
function config.tryCreateConfig(path, data)
	if not config.fileExists(path) then
        config.saveFile(path, data)
    end
end

---Loads and decodes a JSON file.
---Returns an empty table when the file is missing, invalid, or not a JSON object/array.
---@param path string Source JSON path.
---@return table<string, any> decoded Decoded JSON table, or `{}` on failure.
function config.loadFile(path)
    recoverSwapFile(path)

    local raw = readAll(path)
    if raw == nil then
        logger:warn("Failed to load file: " .. path .. ", restoring empty state")
        return {}
    end

    local decoded = {}
    local success = pcall(function ()
        decoded = json.decode(raw)
    end)
    if not success or type(decoded) ~= "table" then
        logger:warn("Failed to load file: " .. path .. ", restoring empty state")
        return {}
    end

    return decoded
end

---Returns whether a table is a dense 1-based array.
---@param value table
---@return boolean isArray
---@return integer arrayLength
local function isArrayTable(value)
    local maxKey = 0
    local count = 0

    for key, _ in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false, 0
        end

        if key > maxKey then
            maxKey = key
        end

        count = count + 1
    end

    if count == 0 then
        return true, 0
    end

    if maxKey ~= count then
        return false, 0
    end

    return true, maxKey
end

---Escapes one Lua string as a JSON string literal.
---@param value string
---@return string
local function encodeJSONString(value)
    local replacements = {
        ["\\"] = "\\\\",
        ["\""] = "\\\"",
        ["\b"] = "\\b",
        ["\f"] = "\\f",
        ["\n"] = "\\n",
        ["\r"] = "\\r",
        ["\t"] = "\\t"
    }

    local escaped = value:gsub("[%z\1-\31\\\"]", function(char)
        return replacements[char] or string.format("\\u%04x", string.byte(char))
    end)

    return "\"" .. escaped .. "\""
end

---Recursively encodes a value to stable JSON order.
---Returns false for unsupported structures and lets callers fall back to `json.encode`.
---@param value any
---@param out string[]
---@param seen table<table, boolean>
---@param skipKeys table<string, boolean>? Object keys to omit. Applies to `value` itself only, never
---to nested tables, so a filtered field name cannot accidentally strip an unrelated nested key.
---@return boolean ok
---@return string? err
local function encodeStableJSONValue(value, out, seen, skipKeys)
    local valueType = type(value)

    if valueType == "nil" then
        out[#out + 1] = "null"
        return true
    end

    if valueType == "boolean" then
        out[#out + 1] = value and "true" or "false"
        return true
    end

    if valueType == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            out[#out + 1] = "null"
        else
            out[#out + 1] = string.format("%.17g", value)
        end
        return true
    end

    if valueType == "string" then
        out[#out + 1] = encodeJSONString(value)
        return true
    end

    if valueType ~= "table" then
        return false, "unsupported_type:" .. valueType
    end

    if seen[value] then
        return false, "circular_reference"
    end

    seen[value] = true

    local isArray, arrayLength = isArrayTable(value)
    if isArray then
        out[#out + 1] = "["
        for i = 1, arrayLength do
            if i > 1 then
                out[#out + 1] = ","
            end

            local ok, err = encodeStableJSONValue(value[i], out, seen)
            if not ok then
                seen[value] = nil
                return false, err
            end
        end
        out[#out + 1] = "]"
        seen[value] = nil
        return true
    end

    local keys = {}
    for key, _ in pairs(value) do
        if type(key) ~= "string" then
            seen[value] = nil
            return false, "unsupported_object_key_type:" .. type(key)
        end

        if not (skipKeys and skipKeys[key]) then
            table.insert(keys, key)
        end
    end

    table.sort(keys)

    out[#out + 1] = "{"
    for index, key in ipairs(keys) do
        if index > 1 then
            out[#out + 1] = ","
        end

        out[#out + 1] = encodeJSONString(key)
        out[#out + 1] = ":"

        local ok, err = encodeStableJSONValue(value[key], out, seen)
        if not ok then
            seen[value] = nil
            return false, err
        end
    end
    out[#out + 1] = "}"
    seen[value] = nil

    return true
end

---Encodes a Lua value to stable JSON output.
---@param value any
---@return string? encoded
---@return string? err
local function encodeStableJSON(value)
    local out = {}
    local ok, err = encodeStableJSONValue(value, out, {})
    if not ok then
        return nil, err
    end

    return table.concat(out)
end

-- Public aliases of the canonical encoder. Anything that writes a file entSpawner will later compare
-- against MUST go through these rather than reimplementing the format: a single divergence in key
-- ordering, float formatting or string escaping would make identical data hash as different.

---Appends the stable-JSON encoding of `value` to `out`.
---@param value any
---@param out string[] Caller-owned piece list, appended to in place.
---@param seen table<table, boolean>? Cycle-detection set; a fresh table is used when omitted.
---@param skipKeys table<string, boolean>? Object keys to omit from `value` itself (not nested tables).
---@return boolean ok
---@return string? err
function config.encodeStableValueInto(value, out, seen, skipKeys)
    return encodeStableJSONValue(value, out, seen or {}, skipKeys)
end

---Escapes one Lua string as a JSON string literal.
config.encodeJSONString = encodeJSONString

---Encodes a Lua value to stable JSON output. Returns `nil, err` for unsupported structures.
config.encodeStableJSON = encodeStableJSON

---Encodes JSON with a stable encoder first, then falls back to the runtime JSON module.
---@param value any
---@return string? encoded
---@return string? err
local function encodeJSONForSave(value)
    local stableEncoded = encodeStableJSON(value)
    if stableEncoded then
        return stableEncoded
    end

    local encoded
    local encodedOk, encodedErr = pcall(function ()
        encoded = json.encode(value)
    end)
    if not encodedOk then
        return nil, tostring(encodedErr)
    end
    if type(encoded) ~= "string" then
        return nil, "invalid_payload"
    end

    return encoded
end

---Encodes and saves a Lua table as JSON using temp-file replacement.
---This method is resilient to partial writes by using `.tmp` and `.swap` files.
---@param path string Destination JSON path.
---@param data table<string, any> Lua table to serialize as JSON.
---@param options {skipExistingComparison: boolean?}? Optional save behavior.
---@return boolean success `true` when save completes.
---@return string? err Error text/code when encoding, writing, or replacement fails.
function config.saveFile(path, data, options)
    recoverSwapFile(path)

    local encoded, encodeErr = encodeJSONForSave(data)
    if not encoded then
        logger:error("Failed to encode file: " .. path .. " (" .. tostring(encodeErr) .. ")")
        return false, tostring(encodeErr)
    end

    if not (options and options.skipExistingComparison) then
        local existingRaw = readAll(path)
        if existingRaw ~= nil then
            if existingRaw == encoded then
                return true
            end

            local existingDecoded
            local existingDecodeOk = pcall(function ()
                existingDecoded = json.decode(existingRaw)
            end)

            if existingDecodeOk then
                local existingCanonical = encodeJSONForSave(existingDecoded)
                if existingCanonical and existingCanonical == encoded then
                    return true
                end
            end
        end
    end

    local tmpPath = path .. ".tmp"
    if config.fileExists(tmpPath) then
        os.remove(tmpPath)
    end

    local written, writeErr = writeAll(tmpPath, encoded)
    if not written then
        os.remove(tmpPath)
        logger:error("Failed to write temp file: " .. tmpPath .. " (" .. tostring(writeErr) .. ")")
        return false, tostring(writeErr)
    end

    local replaced, replaceErr = replaceFile(path, tmpPath)
    if not replaced then
        os.remove(tmpPath)
        logger:error("Failed to replace file: " .. path .. " (" .. tostring(replaceErr) .. ")")
        return false, tostring(replaceErr)
    end

    return true
end

---Recursively loads spawn definitions from `.json` files in a directory.
---Each JSON file is expected to contain `name` and `spawnable` keys.
---@param path string Directory path (callers pass a trailing `/`).
---@param files ConfigSpawnFileEntry[]? Optional accumulator for recursive calls.
---@return ConfigSpawnFileEntry[] files Sorted by `name` in ascending order.
function config.loadFiles(path, files)
    local files = files or {}

    for _, file in pairs(dir(path)) do
        if file.name:match("^.+(%..+)$") == ".json" then
            local data = config.loadFile(path .. file.name)
            table.insert(files, {data = data.spawnable, lastSpawned = nil, name = data.name, fileName = data.name })
        elseif file.type == "directory" then
            config.loadFiles(path .. file.name .. "/", files)
        end
    end

    table.sort(files, function(a, b) return a.name < b.name end)

    return files
end

---Recursively loads spawn paths from `.txt` files in a directory.
---Each line becomes one spawn entry with `data.spawnData` and optional `data.deviceClassName`.
---Accepted line formats:
--- - `{path}`
--- - `{className} {path}`
--- - ` {path}` (explicit empty class name)
---@param path string Directory path (callers pass a trailing `/`).
---@param paths ConfigSpawnPathEntry[]? Optional accumulator for recursive calls.
---@return ConfigSpawnPathEntry[] paths Sorted by `name` in ascending order.
function config.loadLists(path, paths)
    local utils = require("modules/utils/core/utils")
    local paths = paths or {}

    ---Parses one list line into optional class name + spawn path.
    ---@param line string
    ---@return string className
    ---@return string spawnPath
    local function parseSpawnListLine(line)
        local raw = tostring(line or "")
        local trimmed = utils.trimString(raw)

        if trimmed == "" then
            return "", ""
        end

        if trimmed:find("//", 1, true) == 1 or trimmed:find("#", 1, true) == 1 or trimmed:find(";", 1, true) == 1 then
            return "", ""
        end

        local firstToken, rest = trimmed:match("^(%S+)%s+(.+)$")
        if not firstToken or not rest then
            return "", trimmed
        end

        -- Path-only line with no class prefix.
        if firstToken:find("\\", 1, true) or firstToken:find("/", 1, true) then
            return "", trimmed
        end

        local normalizedRest = utils.trimString(rest)

        -- Only treat first token as class prefix when the remainder is a real path.
        -- This preserves hash-style triplets used by Collision Mesh lists:
        -- "sectorHash shapeHash meshType"
        if normalizedRest:find("\\", 1, true) or normalizedRest:find("/", 1, true) then
            return firstToken, normalizedRest
        end

        return "", trimmed
    end

    for _, file in pairs(dir(path)) do
        local extension = file.name:match("^.+(%..+)$")
        if extension and extension:lower() == ".txt" then
            local data = io.open(path .. file.name)
            local firstIndex = #paths + 1
            for line in data:lines() do
                local className, spawnPath = parseSpawnListLine(line)
                if spawnPath ~= "" then
                    table.insert(paths, {
                        data = { spawnData = spawnPath, deviceClassName = className },
                        lastSpawned = nil,
                        name = spawnPath,
                        fileName = utils.getFileName(spawnPath)
                    })
                end
            end

            data:close()
            pathOrigin.registerList(path .. file.name, paths, firstIndex)
        elseif file.type == "directory" then
            config.loadLists(path .. file.name .. "/", paths)
        end
    end

    table.sort(paths, function(a, b) return a.name < b.name end)

    return paths
end

---Copies keys from `source` into `target` only when missing in `target`.
---Nested tables are merged recursively when both sides are tables.
---@param source table Table containing default values.
---@param target table Table to patch in place.
local function recursiveAddMissingKeys(source, target)
    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
            recursiveAddMissingKeys(v, target[k])
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

---Backfills missing keys in an existing JSON file to preserve backward compatibility.
---@param path string Target JSON path to update.
---@param data table Table containing default keys and values.
function config.backwardComp(path, data)
    local f = config.loadFile(path)

    recursiveAddMissingKeys(data, f)

    config.saveFile(path, f)
end

---Loads a plain text file into a list of lines.
---@param path string Source text file path.
---@return string[] lines One element per line in file order.
function config.loadText(path)
    local lines = {}
    for line in io.lines(path) do
        table.insert(lines, line)
    end
    return lines
end

---Loads a full file as raw text without JSON decoding.
---@param path string Source file path.
---@return string content Full file contents.
function config.loadRaw(path)
    local file = io.open(path, "r")
    local content = file:read("*a")
    file:close()
    return content
end

---Writes raw text to a file without JSON encoding.
---@param path string Destination file path.
---@param data string Raw content to write.
function config.saveRaw(path, data)
    local file = io.open(path, "w")
    file:write(data)
    file:close()
end

---Writes each value from `data` to a new line in a text file.
---@param path string Destination file path.
---@param data table Values to write (each value is converted with Lua concatenation rules).
function config.saveRawTable(path, data)
    local file = io.open(path, "w")
    for _, line in pairs(data) do
        file:write(line .. "\n")
    end
    file:close()
end

return config
