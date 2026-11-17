local config = require("modules/utils/core/config")
local pathOrigin = require("modules/utils/data/pathOrigin")
local assetAttribution = require("modules/utils/data/assetAttribution")

---Collects the mod assets referenced by the groups of the export list, one saved project per frame.
local moddedAssets = {}

local RANDOMIZED_GROUP_PATH = "modules/classes/editor/randomizedGroup"

-- Spawnable keys that hold no exported resource path. `defaultComponentData` is the .ent's captured
-- component state, not exported (only `instanceDataChanges` is).
local skippedKeys = { name = true, nodeRef = true, modulePath = true, dataType = true, app = true, defaultComponentData = true }

---@class ModdedAssetUse
---@field uses integer
---@field elements table<string, integer> Element name -> uses.
---@field name string? Export group name, on per-group uses.
---@field types table<string, integer> Type key (see `moddedAssets.parseTypeKey`) -> uses.

---@class ModdedAssetGroupScan
---@field paths table<string, ModdedAssetUse> Lowercase path with `\` -> uses.
---@field display table<string, string> Lowercase path -> path as written.

---@class ModdedAssetEntry
---@field path string Path as written.
---@field key string Lowercase path with `\`.
---@field fileName string
---@field extension string
---@field author AssetAttributionValue?
---@field pack AssetAttributionValue?
---@field uses integer
---@field groups table<string, ModdedAssetUse> Project file name -> uses.
---@field types table<string, integer> Type key -> uses.
---@field typeLabels string[]? Display labels of `types`, cached by the UI.
---@field lists PathOriginListSource[] Spawn lists citing the asset.

---@class ModdedAssetReport
---@field assets ModdedAssetEntry[] Sorted by file name.
---@field uses integer
---@field authors integer Distinct known authors.
---@field packs integer Distinct props packs.
---@field missingGroups string[] Groups whose project file is missing.

---@type table<string, ModdedAssetGroupScan|false> Project file name -> scan, false when missing.
local scans = {}
local signature = nil
---@type { fileName: string, name: string }[]
local entries = {}
---@type ModdedAssetReport?
local report = nil

---@param text string
---@return boolean
local function isDepotPath(text)
    if #text < 5 or #text > 512 then return false end
    if not text:find("[\\/]") then return false end
    if text:find("[%c\"<>|%*%?:]") then return false end
    return text:match("^[^\\/ ][^\\/]*[\\/].*[^\\/ ]%.%w+$") ~= nil
end

local NESTED_TYPE_SUFFIX = "\1nested"

---@param modulePath string Spawnable module path.
---@param nested boolean Whether the path sits below the spawnable's top level (e.g. instance data).
---@return string
local function makeTypeKey(modulePath, nested)
    return nested and (modulePath .. NESTED_TYPE_SUFFIX) or modulePath
end

---@param typeKey string
---@return string modulePath
---@return boolean nested
function moddedAssets.parseTypeKey(typeKey)
    local modulePath = typeKey:match("^(.*)\1nested$")
    if modulePath then return modulePath, true end
    return typeKey, false
end

---@param data any
---@param elementName string
---@param modulePath string
---@param scan ModdedAssetGroupScan
---@param depth integer
local function collectStrings(data, elementName, modulePath, scan, depth)
    if depth > 24 then return end

    for key, value in pairs(data) do
        local valueType = type(value)
        if skippedKeys[key] then
            -- Not exported, or never a path.
        elseif valueType == "string" then
            if isDepotPath(value) then
                local normalized = value:lower():gsub("/", "\\")
                local use = scan.paths[normalized]
                if not use then
                    use = { uses = 0, elements = {}, types = {} }
                    scan.paths[normalized] = use
                    scan.display[normalized] = value
                end
                local typeKey = makeTypeKey(modulePath, depth > 0)
                use.uses = use.uses + 1
                use.elements[elementName] = (use.elements[elementName] or 0) + 1
                use.types[typeKey] = (use.types[typeKey] or 0) + 1
            end
        elseif valueType == "table" then
            collectStrings(value, elementName, modulePath, scan, depth + 1)
        end
    end
end

---Walks a saved element tree, skipping what the export leaves out.
---@param element table
---@param parentModule string?
---@param scan ModdedAssetGroupScan
local function walkElement(element, parentModule, scan)
    if type(element) ~= "table" or element.exportDisabled == true then return end
    if parentModule == RANDOMIZED_GROUP_PATH and element.visible == false then return end

    if type(element.spawnable) == "table" then
        local modulePath = tostring(element.spawnable.modulePath or "")
        collectStrings(element.spawnable, tostring(element.name or "?"), modulePath, scan, 0)
    end

    for _, child in ipairs(element.childs or {}) do
        walkElement(child, element.modulePath, scan)
    end
end

---@param fileName string
---@return ModdedAssetGroupScan|false
local function scanGroup(fileName)
    local path = "data/objects/" .. fileName
    if not config.fileExists(path) then return false end

    local ok, blob = pcall(config.loadFile, path)
    if not ok or type(blob) ~= "table" then return false end

    local scan = { paths = {}, display = {} }
    walkElement(blob, nil, scan)
    return scan
end

local function buildReport()
    local byKey = {}
    local assets = {}
    local missingGroups = {}
    local extraPaths = {}

    for _, entry in ipairs(entries) do
        local scan = scans[entry.fileName]
        if scan == false then
            table.insert(missingGroups, entry.name)
        elseif scan then
            for key, use in pairs(scan.paths) do
                if pathOrigin.isModAsset(key) then
                    local asset = byKey[key]
                    if not asset then
                        local display = scan.display[key]
                        asset = {
                            path = display,
                            key = key,
                            fileName = display:match("([^\\/]+)$") or display,
                            extension = key:match("%.(%w+)$") or "",
                            lists = pathOrigin.getListSources(key),
                            uses = 0,
                            groups = {},
                            types = {}
                        }
                        byKey[key] = asset
                        table.insert(assets, asset)
                        table.insert(extraPaths, key)
                    end

                    local groupUse = asset.groups[entry.fileName]
                    if not groupUse then
                        groupUse = { uses = 0, elements = {}, name = entry.name }
                        asset.groups[entry.fileName] = groupUse
                    end
                    groupUse.uses = groupUse.uses + use.uses
                    for elementName, count in pairs(use.elements) do
                        groupUse.elements[elementName] = (groupUse.elements[elementName] or 0) + count
                    end
                    for typeKey, count in pairs(use.types) do
                        asset.types[typeKey] = (asset.types[typeKey] or 0) + count
                    end
                    asset.uses = asset.uses + use.uses
                end
            end
        end
    end

    assetAttribution.rebuildIndex(extraPaths)

    local authors, packs = {}, {}
    local totalUses = 0
    local authorCount, packCount = 0, 0

    for _, asset in ipairs(assets) do
        local attribution = assetAttribution.resolve(asset.key)
        asset.author = attribution.author
        asset.pack = attribution.pack
        totalUses = totalUses + asset.uses

        if asset.author and not authors[asset.author.name] then
            authors[asset.author.name] = true
            authorCount = authorCount + 1
        end

        local packKey = moddedAssets.getPackKey(asset)
        if asset.pack and not packs[packKey] then
            packs[packKey] = true
            packCount = packCount + 1
        end
    end

    table.sort(assets, function (a, b)
        if a.fileName == b.fileName then return a.key < b.key end
        return a.fileName:lower() < b.fileName:lower()
    end)

    report = {
        assets = assets,
        uses = totalUses,
        authors = authorCount,
        packs = packCount,
        missingGroups = missingGroups
    }
end

---Pack identity, scoped to its author so two authors' "props" stay apart.
---@param asset ModdedAssetEntry
---@return string
function moddedAssets.getPackKey(asset)
    return (asset.author and asset.author.name or "") .. "|" .. (asset.pack and asset.pack.name or "")
end

---Drops the cached scan of one project, after it was saved.
---@param fileName string
function moddedAssets.invalidate(fileName)
    if scans[fileName] ~= nil then
        scans[fileName] = nil
        report = nil
    end
end

---Drops every cached scan.
function moddedAssets.invalidateAll()
    scans = {}
    report = nil
end

---Advances the scan of the export list; call once per frame while the result is shown.
---@param groups table[] Export list entries.
---@param resolveFileName fun(group: table): string?
---@return ModdedAssetReport? report Nil while scanning.
---@return integer scanned
---@return integer total
function moddedAssets.update(groups, resolveFileName)
    local parts = {}
    local current = {}

    for _, group in ipairs(groups) do
        local fileName = resolveFileName(group)
        if fileName then
            local name = tostring(group.name or fileName)
            table.insert(current, { fileName = fileName, name = name })
            table.insert(parts, fileName .. "\0" .. name)
        end
    end

    local newSignature = table.concat(parts, "\1")
    if newSignature ~= signature then
        signature = newSignature
        entries = current
        report = nil
    end

    local scanned = 0
    local pending = nil
    for _, entry in ipairs(entries) do
        if scans[entry.fileName] ~= nil then
            scanned = scanned + 1
        elseif not pending then
            pending = entry
        end
    end

    if pending then
        scans[pending.fileName] = scanGroup(pending.fileName)
        report = nil
        return nil, scanned + 1, #entries
    end

    if not report then
        buildReport()
    end

    return report, #entries, #entries
end

return moddedAssets
