local config = require("modules/utils/core/config")
local utils = require("modules/utils/core/utils")
local pipelineCommon = require("modules/utils/pipeline/common")

local groupExportSidecar = {}
-- 2: entries are keyed by project file rather than display name, and the source revision is a
-- content hash rather than a timestamp. Both make a version 1 sidecar unusable for comparison.
groupExportSidecar.SCHEMA_VERSION = 2
groupExportSidecar.SIDECAR_SUFFIX = ".metadata"
groupExportSidecar.LEGACY_SIDECAR_SUFFIX = "_metadata.json"

local function normalizeNumber(value)
    local num = tonumber(value) or 0
    return string.format("%.17g", num)
end

---Resolves which project file an export entry refers to.
---
---Entries carry the uID (`fileName`) since project files stopped being named after their group; the
---name is the display text and only matches the file for entries that predate the split.
---@param group table? Export list entry, or `{ name = ... }`.
---@return string fileName Including the extension.
function groupExportSidecar.resolveGroupFileName(group)
    local fileName = utils.trimString(group and group.fileName)
    if fileName ~= "" then
        return fileName
    end

    return utils.trimString(group and group.name) .. ".json"
end

---Identifies the on-disk state of a project file, so a group whose content changed can be told apart
---from one that can be reused as-is.
---
---A hash of the file's bytes, not its `lastEditedAt`: the timestamp is absent from files written
---through paths that never injected it, and the `dir()` entries CET hands out carry no modification
---time to fall back on -- both of which made this collapse to one constant value, and a constant
---revision means every group looks unchanged forever. The timestamp is stripped before hashing, so
---re-saving a group without editing it does not force a pointless re-export either.
---@param fileName string? Project file name, including the extension.
---@return string revision
function groupExportSidecar.resolveGroupSourceRevision(fileName)
    local normalizedName = utils.trimString(fileName)
    if normalizedName == "" then
        return "missing"
    end

    local path = "data/objects/" .. normalizedName
    if not config.fileExists(path) then
        return "missing"
    end

    local raw = config.readAll(path)
    if type(raw) ~= "string" or raw == "" then
        return "unreadable"
    end

    local canonical = raw:gsub('"lastEditedAt"%s*:%s*"[^"]*"%s*,?', "")

    return string.format("%s:%d", (tostring(FNV1a64(canonical)):gsub("ULL", "")), #canonical)
end

function groupExportSidecar.getExportPath(projectSlug)
    return "export/" .. tostring(projectSlug) .. "_exported.json"
end

function groupExportSidecar.getSidecarPath(projectSlug)
    return "export/" .. tostring(projectSlug) .. groupExportSidecar.SIDECAR_SUFFIX
end

function groupExportSidecar.getLegacySidecarPath(projectSlug)
    return "export/" .. tostring(projectSlug) .. groupExportSidecar.LEGACY_SIDECAR_SUFFIX
end

---@param projectSlug string
---@return boolean success
---@return boolean migrated
---@return string legacyPath
---@return string sidecarPath
function groupExportSidecar.migrateLegacySidecar(projectSlug)
    local legacyPath = groupExportSidecar.getLegacySidecarPath(projectSlug)
    local sidecarPath = groupExportSidecar.getSidecarPath(projectSlug)

    if not config.fileExists(legacyPath) or config.fileExists(sidecarPath) then
        return true, false, legacyPath, sidecarPath
    end

    if os.rename(legacyPath, sidecarPath) then
        return true, true, legacyPath, sidecarPath
    end

    return false, false, legacyPath, sidecarPath
end

---@param group table
---@param options table?
---@return string signature
function groupExportSidecar.buildGroupSignature(group, options)
    local opts = options or {}
    local parts = {}
    local variantKeys = {}
    local variantData = group and group.variantData or {}

    for key, _ in pairs(variantData or {}) do
        table.insert(variantKeys, tostring(key))
    end

    table.sort(variantKeys, function (a, b)
        local al = a:lower()
        local bl = b:lower()
        if al == bl then
            return a < b
        end
        return al < bl
    end)

    table.insert(parts, "sourceRevision=" .. groupExportSidecar.resolveGroupSourceRevision(groupExportSidecar.resolveGroupFileName(group)))
    table.insert(parts, "scriptVersion=" .. tostring(opts.version or ""))
    table.insert(parts, "name=" .. tostring(group and group.name or ""))
    table.insert(parts, "fileName=" .. groupExportSidecar.resolveGroupFileName(group))
    table.insert(parts, "category=" .. tostring(group and group.category or ""))
    table.insert(parts, "level=" .. tostring(group and group.level or ""))
    -- Bumped when the box derivation changes, so sectors exported with the old box are rebuilt.
    table.insert(parts, "streamingBox=2")
    if group and group.streamingAuto == true then
        -- Extents are derived from the content, which `sourceRevision` already covers.
        table.insert(parts, "streamingAuto=true")
    else
        table.insert(parts, "streamingX=" .. normalizeNumber(group and group.streamingX))
        table.insert(parts, "streamingY=" .. normalizeNumber(group and group.streamingY))
        table.insert(parts, "streamingZ=" .. normalizeNumber(group and group.streamingZ))
    end
    table.insert(parts, "prefabRef=" .. tostring(group and group.prefabRef or ""))
    table.insert(parts, "variantRef=" .. tostring(group and group.variantRef or ""))
    table.insert(parts, "variantCount=" .. tostring(#variantKeys))

    for _, key in ipairs(variantKeys) do
        local variant = variantData[key] or {}
        table.insert(parts, string.format(
            "variant:%s|name=%s|defaultOn=%s|ref=%s",
            key,
            pipelineCommon.normalizeVariantName(variant.name),
            variant.defaultOn and "1" or "0",
            tostring(variant.ref or "")
        ))
    end

    return table.concat(parts, "\n")
end

---@param nodes table?
---@return table
function groupExportSidecar.extractNodeRefs(nodes)
    local result = {}

    for _, node in ipairs(nodes or {}) do
        if node and node.nodeRef and node.nodeRef ~= "" then
            table.insert(result, {
                nodeRef = node.nodeRef,
                name = node.name or ""
            })
        end
    end

    return result
end

---@param exported table?
---@param devices table?
---@param psEntries table?
---@param childs table?
---@param communities table?
---@param spotNodes table?
---@return table
function groupExportSidecar.buildContribution(exported, devices, psEntries, childs, communities, spotNodes)
    local deviceHashes = {}
    local psEntryIds = {}

    for hash, _ in pairs(devices or {}) do
        table.insert(deviceHashes, tostring(hash))
    end
    table.sort(deviceHashes)

    for psid, _ in pairs(psEntries or {}) do
        table.insert(psEntryIds, tostring(psid))
    end
    table.sort(psEntryIds)

    return {
        sectorName = exported and exported.name or "",
        deviceHashes = deviceHashes,
        psEntryIds = psEntryIds,
        childs = utils.deepcopy(childs or {}),
        communities = utils.deepcopy(communities or {}),
        spotNodes = utils.deepcopy(spotNodes or {}),
        nodeRefs = groupExportSidecar.extractNodeRefs(exported and exported.nodes or {})
    }
end

---@param projectName string
---@param version string
---@return table
function groupExportSidecar.createDocument(projectName, version)
    return {
        schemaVersion = groupExportSidecar.SCHEMA_VERSION,
        projectName = projectName,
        version = version,
        groups = {}
    }
end

return groupExportSidecar
