local config = require("modules/utils/core/config")
local utils = require("modules/utils/core/utils")
local style = require("modules/ui/style")
local settings = require("modules/utils/core/settings")
local amm = require("modules/utils/pipeline/ammUtils")
local history = require("modules/utils/project/history")
local editor = require("modules/utils/editor/editor")
local Cron = require("modules/utils/vendor/Cron")
local groupLoadManager = require("modules/utils/pipeline/groupLoadManager")
local sessionSnapshot = require("modules/utils/pipeline/sessionSnapshot")
local entity = require("modules/classes/spawn/entity/entity")
local entityRecordClass = require("modules/classes/spawn/entity/entityRecord")
local aiSpotClass = require("modules/classes/spawn/ai/aiSpot")
local audioData = require("modules/utils/data/audioData")
local soundSelector = require("modules/utils/ui/soundSelector")
local input = require("modules/utils/core/input")
local logger = require("modules/utils/core/logger")
local prefabPreview = require("modules/utils/preview/prefabPreview")
local previewControls = require("modules/utils/preview/previewControls")
local assetFavorites = require("modules/utils/project/assetFavorites")
local assetValidation = require("modules/utils/game/assetValidation")
local colorUtil = require("modules/utils/ui/color")
local pathOrigin = require("modules/utils/data/pathOrigin")
local workspotSync = require("modules/utils/game/workspotSync")
local spawnableClass = require("modules/classes/spawn/spawnable")

local types = {
    ["Entity"] = {
        variants = {
            ["Template"] = { class = require("modules/classes/spawn/entity/entityTemplate"), index = 1},
            ["Template (AMM)"] = { class = require("modules/classes/spawn/entity/ammEntity"), index = 2},
            ["Record"] = { class = entityRecordClass, index = 3},
            ["Device"] = { class = require("modules/classes/spawn/entity/device"), index = 4}
        },
        index = 1
    },
    ["Lighting"] = {
        variants = {
            ["Static Light"] = { class = require("modules/classes/spawn/light/light"), index = 1 },
            ["Reflection Probe"] = { class = require("modules/classes/spawn/meta/reflectionProbe"), index = 2 },
            ["Light Channel Area"] = { class = require("modules/classes/spawn/light/lightChannelArea"), index = 3 },
            ["Fog Volume"] = { class = require("modules/classes/spawn/visual/fog"), index = 4 }
        },
        index = 3
    },
    ["Mesh"] = {
        variants = {
            ["Static Mesh"] = { class = require("modules/classes/spawn/mesh/mesh"), index = 1 },
            ["Rotating Mesh"] = { class = require("modules/classes/spawn/mesh/rotatingMesh"), index = 2 },
            ["Cloth Mesh"] = { class = require("modules/classes/spawn/mesh/clothMesh"), index = 3 },
            ["Dynamic Mesh"] = { class = require("modules/classes/spawn/physics/dynamicMesh"), index = 4 },
            -- One browser over all three destruction nodes. A mesh eligible for more than one
            -- of them appears once per node type, which is how the type gets picked; the row
            -- icon and the "Node type" filter tell them apart.
            ["Destructible Mesh"] = {
                class = require("modules/classes/spawn/physics/destructibleMesh"),
                index = 5,
                sources = {
                    { modulePath = "physics/destructibleMesh", label = "Instanced Destructible Mesh" },
                    { modulePath = "physics/physicalDestruction", label = "Physical Destruction Mesh" },
                    { modulePath = "physics/bakedDestruction", label = "Baked Destruction Mesh" }
                },
                hostedNote = "The asset decides which node is placed; the Node type filter narrows the list down to one.",
                previewNote = "Destruction is not simulated in-editor. The intact mesh and its physics body are previewed."
            },
            ["Bended Mesh"] = { class = require("modules/classes/spawn/mesh/bendedMesh"), index = 6 },
            ["Proxy Mesh"] = { class = require("modules/classes/spawn/mesh/proxyMesh"), index = 7 },
            ["Static Road Intersection"] = { class = require("modules/classes/spawn/mesh/roadIntersection"), index = 8, separatorBefore = true }
        },
        index = 2
    },
    ["Collision"] = {
        variants = {
            ["Collision Shape"] = { class = require("modules/classes/spawn/collision/collider"), index = 1 },
            ["Collision Mesh"] = { class = require("modules/classes/spawn/collision/meshCollider"), index = 2 }
        },
        index = 6
    },
    ["Deco"] = {
        variants = {
            ["Decals"] = { class = require("modules/classes/spawn/visual/decal"), index = 1 },
            ["Particles"] = { class = require("modules/classes/spawn/visual/particle"), index = 2 },
            ["Effects"] = { class = require("modules/classes/spawn/visual/effect"), index = 3 },
            ["Water Patch"] = { class = require("modules/classes/spawn/visual/waterPatch"), index = 4 }
        },
        index = 4
    },
    ["Audio"] = {
        variants = {
            ["Static Audio Emitter"] = { class = require("modules/classes/spawn/audio/audio"), index = 1 },
            ["Ambient Area"] = { class = require("modules/classes/spawn/area/ambientArea"), index = 2 },
            ["Audio Signpost Area"] = { class = require("modules/classes/spawn/area/audioSignpost"), index = 3 },
            ["Audio Attract Area"] = { class = require("modules/classes/spawn/area/audioAttractArea"), index = 4 },
            ["Audio Tag"] = { class = require("modules/classes/spawn/audio/audioTag"), index = 5 }
        },
        index = 5
    },
    ["Meta"] = {
        variants = {
            ["Occluder"] = { class = require("modules/classes/spawn/meta/occluder"), index = 1 },
            ["Static Marker"] = { class = require("modules/classes/spawn/meta/staticMarker"), index = 2 }
        },
        index = 7
    },
    ["Area"] = {
        variants = {
            ["Outline Marker"] = { class = require("modules/classes/spawn/area/outlineMarker"), index = 1 },
            ["Trigger Area"] = { class = require("modules/classes/spawn/area/triggerArea"), index = 2 },
            ["Kill Area"] = { class = require("modules/classes/spawn/area/killArea"), index = 3 },
            ["Prevention Free"] = { class = require("modules/classes/spawn/area/preventionFree"), index = 4 },
            ["Water Null"] = { class = require("modules/classes/spawn/area/waterNull"), index = 5 },
            ["Crowd Null Area"] = { class = require("modules/classes/spawn/area/crowdNull"), index = 6 },
            ["Dummy Area"] = { class = require("modules/classes/spawn/area/dummyArea"), index = 7 },
            ["World Boundary"] = { class = require("modules/classes/spawn/area/worldBoundary"), index = 8 }
        },
        index = 8
    },
    ["AI"] = {
        variants = {
            ["AI Spot"] = { class = aiSpotClass, index = 1 },
            ["Community"] = { class = require("modules/classes/spawn/ai/communityArea"), index = 2 },
            ["Spline Point"] = { class = require("modules/classes/spawn/meta/splineMarker"), index = 3 },
            -- One browser over all three spline nodes. They share the basic spline's path
            -- pipeline and differ only in what the node adds on top, so the entry picks the
            -- node type and the row icon tells them apart. Three rows show every node type at
            -- once, so there is nothing for a node type filter to narrow down.
            ["Spline"] = {
                class = require("modules/classes/spawn/meta/spline"),
                index = 4,
                sources = {
                    { modulePath = "meta/spline", label = "Spline" },
                    { modulePath = "meta/speedSpline", label = "Speed Spline" },
                    { modulePath = "meta/patrolSpline", label = "Patrol Spline" }
                },
                hideNodeTypeFilter = true
            },
            ["Conversation Area"] = { class = require("modules/classes/spawn/area/conversationArea"), index = 5 },
            ["Guard Area"] = { class = require("modules/classes/spawn/area/guardArea"), index = 6 }
        },
        index = 9
    }
}

local spawnData = {}
local variantNames = {}
local modulePathToSpawnList = {}
local modulePathToVariantLabel = {}
local spawnNewVisualizerClassGroups = {}
local spawnNewVisualizerModuleSet = {}
local STATIC_LIGHT_MODULE_PATH = "light/light"
local AI_SPOT_MODULE_PATH = "ai/aiSpot"
local DEFAULT_STATIC_LIGHT_COLOR = { 1, 0.99595707654953, 0.6502890586853 }
local STATIC_LIGHT_TYPES = {
    [0] = true,
    [1] = true,
    [2] = true
}
local applySpawnNewEntryDefaults
-- Node type label -> icon, for variants hosting several spawnable classes. The entry filter
-- receives only the label, so the icons cannot be read back off the spawn list.
local hostedIconByLabel = {}
-- Module path -> per-entry node type resolver, for the hosted classes whose asset list covers
-- more than one node type group. Kept here rather than on the spawn list because the row
-- icon is resolved from the entry alone.
local hostedGroupResolverByModule = {}

-- `types` is static, so the display order is resolved once instead of re-sorting per call.
local typeNames = utils.getKeys(types)
table.sort(typeNames, function (a, b) return types[a].index < types[b].index end)

local variantNamesByType = {}
-- Type name -> 1-based variant indices drawn after a separator, nil when the type has none.
local variantSeparatorsByType = {}
for _, typeName in ipairs(typeNames) do
    local names = utils.getKeys(types[typeName].variants)
    table.sort(names, function (a, b)
        return types[typeName].variants[a].index < types[typeName].variants[b].index
    end)
    variantNamesByType[typeName] = names

    for index, name in ipairs(names) do
        if types[typeName].variants[name].separatorBefore then
            variantSeparatorsByType[typeName] = variantSeparatorsByType[typeName] or {}
            variantSeparatorsByType[typeName][index] = true
        end
    end
end

---Display-ordered variant names of one type. The returned table is shared, do not mutate it.
---@param typeName string
---@return string[]
local function getSortedVariantNames(typeName)
    return variantNamesByType[typeName] or {}
end

local AMM = nil

---@class spawnUI
---@field filter string
---@field selectedGroup number
---@field selectedType number
---@field selectedVariant number
---@field spawnedUI? spawnedUI
---@field spawner? spawner
---@field filteredList table
---@field openPopup boolean
---@field popupFilter string
---@field currentPopupVariant string
---@field popupSpawnHit table?
---@field popupData table
---@field dragging boolean
---@field dragData table?
---@field lastSpawnedClass table?
---@field lastSpawnedEntry table?
---@field lastSpawnedIsFavorite boolean
---@field lastSpawnedOptions table?
---@field previewInstance spawnable?
---@field previewTimer number?
---@field hoveredEntry table?
---@field assetPreviewActive boolean
---@field lightSuppressionTargetsCache table?
---@field lightSuppressionTargetsCacheEpoch number
---@field activeLightSuppressionStates table
---@field flashlightSuppressionComponent IComponent?
---@field flashlightSuppressionCaptured boolean
---@field flashlightSuppressionPreviousOverride number?
---@field entryFilterStateByModule table<string, table<string, {selections: table<string, boolean>, search: string}>>
---@field pendingFilterUpdate boolean
---@field pendingFilterUpdateAt number
---@field filteredHierarchyTree table?
---@field hierarchyOpenStateByKey table<string, boolean>
---@field hierarchyRows hierarchyRow[]?
---@field hierarchyRowsRoot table?
---@field prefabsUI prefabsUI
---@field favoritesUI favoritesUI
spawnUI = {
    filter = "",
    popupFilter = "",
    selectedGroup = 0,
    selectedType = 0,
    selectedVariant = 0,
    spawnedUI = nil,
    spawner = nil,
    filteredList = {},
    openPopup = false,
    currentPopupVariant = "",
    popupData = {},
    popupSpawnHit = nil,
    dragging = false,
    dragData = nil,
    lastSpawnedClass = nil,
    lastSpawnedEntry = nil,
    lastSpawnedIsFavorite = false,
    lastSpawnedOptions = nil,
    previewInstance = nil,
    previewTimer = nil,
    hoveredEntry = nil,
    assetPreviewActive = false,
    lightSuppressionTargetsCache = nil,
    lightSuppressionTargetsCacheEpoch = -1,
    activeLightSuppressionStates = {},
    flashlightSuppressionComponent = nil,
    flashlightSuppressionCaptured = false,
    flashlightSuppressionPreviousOverride = nil,
    entryFilterStateByModule = {},
    pendingFilterUpdate = false,
    pendingFilterUpdateAt = 0,
    filteredHierarchyTree = nil,
    hierarchyOpenStateByKey = {},
    hierarchyRows = nil,
    hierarchyRowsRoot = nil,
    prefabsUI = require("modules/ui/prefabsUI"),
    favoritesUI = require("modules/ui/favoritesUI")
}

---@param instance spawnable?
---@return boolean
local function supportsSpawnNewVisualizerDefault(instance)
    return instance
        and instance.previewed ~= nil
        and type(instance.setPreview) == "function"
        and type(instance.drawPreviewCheckbox) == "function"
end

---@return table[]
function spawnUI.getVisualizerClassGroups()
    local groups = {}

    for _, typeName in ipairs(typeNames) do
        local entries = spawnNewVisualizerClassGroups[typeName]
        if entries and #entries > 0 then
            table.insert(groups, {
                typeName = typeName,
                entries = entries
            })
        end
    end

    return groups
end

---Replaces a path list with a single generic spawn entry, for spawnables declaring
---`collapseSpawnList`. The concrete asset can be changed later in node properties.
---@param spawnList table
---@param label string
local function collapseSpawnListToSingleEntry(spawnList, label)
    local defaultPath = ""
    for _, entry in ipairs(spawnList.data or {}) do
        local path = entry and entry.data and entry.data.spawnData or ""
        if type(path) == "string" and path ~= "" then
            defaultPath = path
            break
        end
    end

    spawnList.data = {
        {
            data = { spawnData = defaultPath },
            lastSpawned = nil,
            name = label,
            fileName = label
        }
    }

    -- Keep Spawn New focused on a generic item instead of path-browser behavior.
    spawnList.isPaths = false
end

---Builds the entry list of a variant that hosts several spawnable classes, and records the
---hosted sources on the spawn list.
---
---Used when one browser covers more than one world node type: the node types have separate
---spawnable classes and separate lists, but the user picks a row first and the node type
---follows from it. Every entry is tagged with the module that spawns it, so
---`resolveEntryClass` can hand the right class to `spawnNew`, and with a label the
---`nodeType` entry filter groups by.
---@param spawnList table
---@param sources {modulePath: string, label: string}[]
---@return table entries
local function mergeHostedSpawnSources(spawnList, sources)
    local merged = {}
    spawnList.hostedSources = {}

    for _, source in ipairs(sources) do
        local class = require("modules/classes/spawn/" .. source.modulePath)
        local instance = class:new()
        local label = source.label or instance.dataType or source.modulePath

        table.insert(spawnList.hostedSources, {
            modulePath = source.modulePath,
            label = label,
            icon = instance.icon,
            node = instance.node,
            description = instance.description,
            groupsNote = class.nodeTypeGroupsNote,
            -- Each hosted class keeps its own Spawn New visualizer default, the host's does
            -- not stand in for it: they are separate node types with separate previews.
            supportsVisualizer = supportsSpawnNewVisualizerDefault(instance) == true,
            defaultPreviewed = instance.previewed == true
        })
        hostedIconByLabel[label] = instance.icon

        -- A class whose asset list covers several node type groups names them itself, and
        -- decides per entry which one it falls in. Resolving is left to draw time: the rule
        -- needs static data that should not be read at startup for a browser nobody opened.
        if type(class.resolveNodeTypeGroup) == "function" then
            for _, group in ipairs(class.nodeTypeGroups or {}) do
                hostedIconByLabel[group.label] = group.icon or instance.icon
            end
            hostedGroupResolverByModule[source.modulePath] = class.resolveNodeTypeGroup
        end

        -- Hosted classes need not agree on how their list is stored: an asset browser reads
        -- path lists, a preset browser reads exported files. Both yield the same entry shape.
        local loadSpawnDataFn = instance.spawnListType == "list" and config.loadLists or config.loadFiles
        for _, entry in ipairs(loadSpawnDataFn(instance.spawnDataPath)) do
            entry.modulePath = source.modulePath
            entry.nodeTypeLabel = label
            table.insert(merged, entry)
        end
    end

    return merged
end

---Info tooltip of a variant hosting several spawnable classes: one line per hosted node
---type, instead of the host class's own description which only covers one of them.
---@param spawnList table
---@param variant table The `types` entry declaring the hosted sources.
---@param variantInstance spawnable The host class instance, for the notes the variant leaves out.
---@return table info {node, description, previewNote}
local function buildHostedSpawnInfo(spawnList, variant, variantInstance)
    local nodes = {}
    local descriptions = {}

    for _, source in ipairs(spawnList.hostedSources or {}) do
        table.insert(nodes, source.node)

        local description = source.label .. " (" .. source.node .. "): " .. source.description
        if source.groupsNote then
            description = description .. "\n" .. source.groupsNote
        end
        table.insert(descriptions, description)
    end

    local defaultNote = spawnList.hideNodeTypeFilter
        and "Each entry places one of these nodes."
        or "The Node type filter narrows the list down to one."

    return {
        node = table.concat(nodes, ", "),
        description = table.concat(descriptions, "\n\n") .. "\n\n" .. (variant.hostedNote or defaultNote),
        -- The host's own preview note only covers its own node, so a variant spanning several
        -- says it once for all of them; without one the host's still beats leaving it blank.
        previewNote = variant.previewNote or variantInstance.previewNote
    }
end

---Node type one entry of a hosted browser belongs to. Normally the label of the list it came
---from, unless its class splits its own assets into several node type groups.
---@param entry table?
---@return string
local function resolveHostedNodeType(entry)
    if not entry then
        return ""
    end

    local resolve = hostedGroupResolverByModule[entry.modulePath or ""]
    if resolve then
        return tostring(resolve(entry) or "")
    end

    return tostring(entry.nodeTypeLabel or "")
end

---Row icon marking which node type an entry belongs to, in a variant hosting several
---spawnable classes. Empty for every other list, which has nothing to disambiguate.
---@param entry table?
---@return string
local function getHostedEntryIcon(entry)
    return hostedIconByLabel[resolveHostedNodeType(entry)] or ""
end

---Trailing icon of one spawn list row, marking which flavor of node the entry places. Hosted
---browsers mark the node type; a class covering several flavors of one node (a static light's
---point/spot/area) names its own; device entities fall back to their device class. Only one of
---the three ever applies to a given list.
---@param entry table?
---@param spawnList table
---@return string
local function getEntryRowIcon(entry, spawnList)
    local icon = getHostedEntryIcon(entry)

    if icon == "" and spawnList.resolveEntrySecondaryIcon then
        icon = spawnList.resolveEntrySecondaryIcon(entry) or ""
    end

    if icon == "" then
        icon = entity.getEntrySecondaryIcon(entry, spawnList.modulePath)
    end

    return icon
end

---The spawnable class that spawns a given entry. Entries of a variant hosting several
---classes carry their own module path; everything else uses the variant's class.
---@param spawnList table?
---@param entry table?
---@return table class
local function resolveEntryClass(spawnList, entry)
    local modulePath = entry and entry.modulePath
    if type(modulePath) == "string" and modulePath ~= "" then
        return utils.requireSpawnable(modulePath)
    end

    return spawnList.class
end

---Public form of `resolveEntryClass`, for callers outside this module that build a synthetic
---entry and need the class it should spawn as (the RHT clone path).
---@param spawnList table?
---@param entry table?
---@return table class
function spawnUI.resolveEntryClass(spawnList, entry)
    return resolveEntryClass(spawnList, entry)
end

---Display name of a spawnable class, for messages about it.
---@param modulePath string?
---@return string
local function getSpawnableLabel(modulePath)
    return modulePathToVariantLabel[modulePath or ""] or tostring(modulePath or "this node")
end

---Lists the variants that would accept the asset a class just rejected, empty when none does.
---Also used by the Spawned tab, whose asset path editor runs the same check on a typed path.
---@param check assetCheckResult
---@return string
function spawnUI.getVariantSuggestion(check)
    local labels = {}

    for _, modulePath in ipairs(check.acceptedBy) do
        -- Several classes can share one browser, and then they share its label too.
        local label = modulePathToVariantLabel[modulePath]
        if label and not utils.has_value(labels, label) then
            table.insert(labels, label)
        end
    end

    if #labels == 0 then return "" end

    return "Spawn it under: " .. table.concat(labels, ", ")
end

---Refuses a spawn whose asset is of a resource type the target class cannot spawn, and says so.
---Everything that spawns from Spawn New funnels through here, because handing the game a resource
---of the wrong type crashes it rather than failing.
---@param modulePath string?
---@param path string?
---@return boolean rejected
local function rejectIncompatibleAsset(modulePath, path)
    local label = getSpawnableLabel(modulePath)
    local reason = assetValidation.getSpawnBlock(modulePath, path, label)
    if not reason then return false end

    local suggestion = spawnUI.getVariantSuggestion(assetValidation.check(modulePath, path))

    logger:warn(string.format("Refused to spawn \"%s\" as %s: %s", tostring(path), label, reason))
    ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Error, 6000, reason .. (suggestion ~= "" and ("\n" .. suggestion) or "")))

    return true
end

---Public form of `rejectIncompatibleAsset`, for spawns started outside this module.
---@param modulePath string?
---@param path string?
---@return boolean rejected
function spawnUI.rejectIncompatibleAsset(modulePath, path)
    return rejectIncompatibleAsset(modulePath, path)
end

---Sorts one spawn list in the order Spawn New displays it.
---Done once at load so switching category/variant never re-sorts.
---@param spawnList table
local function sortSpawnList(spawnList)
    -- Sorting every list at load means one malformed entry must not take startup
    -- down, hence the tostring coercion in both comparators.
    table.sort(spawnList.data, function (a, b) return tostring(a.name) < tostring(b.name) end)

    if not spawnList.isPaths then return end

    -- Path lists can also be displayed file-name-first ("Strip paths"), so keep a
    -- second ordering ready instead of re-sorting whenever the toggle flips.
    local byFileName = {}
    for index, entry in ipairs(spawnList.data) do
        byFileName[index] = entry
    end
    table.sort(byFileName, function (a, b) return tostring(a.fileName) < tostring(b.fileName) end)

    spawnList.dataByFileName = byFileName
end

---Returns the spawn list entries in the order Spawn New currently displays them.
---@param spawnList table
---@return table[]
local function getOrderedSpawnListData(spawnList)
    if spawnList.isPaths and settings.spawnUIOnlyNames and spawnList.dataByFileName then
        return spawnList.dataByFileName
    end

    return spawnList.data
end

---Loads the spawn data (Either list of e.g. paths, or exported object files) for each data variant
---@param spawner spawner
function spawnUI.loadSpawnData(spawner)
    variantNames = {}
    spawnData = {}
    modulePathToSpawnList = {}
    modulePathToVariantLabel = {}
    hostedIconByLabel = {}
    hostedGroupResolverByModule = {}
    spawnUI.entryFilterStateByModule = {}
    spawnUI.filteredHierarchyTree = nil
    spawnUI.hierarchyOpenStateByKey = {}
    spawnUI.invalidateHierarchyRows()
    spawnUI.invalidateFilterCaches()

    AMM = GetMod("AppearanceMenuMod")
    spawnUI.spawnedUI = spawner.baseUI.spawnedUI
    spawnUI.spawner = spawner
    spawnUI.filter = tostring(settings.spawnUIFilter or "")

    local visualizerGroups = {}
    local visualizerModuleSet = {}
    local settingsChanged = false

    pathOrigin.beginListScan()

    if type(settings.spawnNewVisualizerEnabledByModule) ~= "table" then
        settings.spawnNewVisualizerEnabledByModule = {}
        settingsChanged = true
    end

    -- Both maps below are keyed by module path, so a class that has moved would come back with
    -- its defaults instead of what the user set for it. Re-keyed once, before anything reads them.
    if utils.migrateMovedSpawnableModuleKeys(settings.assetPreviewEnabled) then
        settingsChanged = true
    end
    if utils.migrateMovedSpawnableModuleKeys(settings.spawnNewVisualizerEnabledByModule) then
        settingsChanged = true
    end

    for _, dataName in ipairs(typeNames) do
        spawnData[dataName] = {}
        local visualizerEntries = {}

        for _, variantName in ipairs(getSortedVariantNames(dataName)) do
            local variant = types[dataName].variants[variantName]
            -- One instance per variant serves both the spawn list metadata and the
            -- visualizer catalog below; instantiating spawnables is not cheap.
            local variantInstance = variant.class:new()
            local modulePath = variantInstance.modulePath
            local isPaths = variantInstance.spawnListType == "list"
            local loadSpawnDataFn = isPaths and config.loadLists or config.loadFiles
            local spawnList = {
                data = loadSpawnDataFn(variantInstance.spawnDataPath),
                class = variant.class,
                modulePath = modulePath,
                info = { node = variantInstance.node, description = variantInstance.description, previewNote = variantInstance.previewNote },
                isPaths = isPaths,
                assetPreviewDelay = variantInstance.assetPreviewDelay,
                assetPreviewType = variantInstance.assetPreviewType,
                entryFilter = variantInstance.entryFilter,
                entryNote = variantInstance.entryNote,
                hideNodeTypeFilter = variant.hideNodeTypeFilter == true,
                resolveEntrySecondaryIcon = variant.class.resolveEntrySecondaryIcon
            }

            -- A variant may host several spawnable classes in one browser, when they cover closely
            -- related world nodes. Every entry then carries the module that spawns it, and an
            -- entry filter narrows the list to one node type.
            if variant.sources then
                spawnList.data = mergeHostedSpawnSources(spawnList, variant.sources)
                spawnList.info = buildHostedSpawnInfo(spawnList, variant, variantInstance)
            end

            if isPaths and variant.class.getAssetName ~= spawnableClass.getAssetName then
                for _, entry in ipairs(spawnList.data) do
                    entry.fileName = variant.class.getAssetName(entry.name)
                end
            end

            if variantInstance.collapseSpawnList then
                collapseSpawnListToSingleEntry(spawnList, variantInstance.collapsedSpawnListLabel or variantName)
            end

            sortSpawnList(spawnList)

            spawnData[dataName][variantName] = spawnList
            modulePathToSpawnList[modulePath] = spawnList
            modulePathToVariantLabel[modulePath] = dataName .. " > " .. variantName

            -- Hosted classes resolve back to the browser they live in, so asset preview
            -- settings, favorites and the "Type > Variant" label work for them too.
            for _, source in ipairs(spawnList.hostedSources or {}) do
                modulePathToSpawnList[source.modulePath] = spawnList
                modulePathToVariantLabel[source.modulePath] = dataName .. " > " .. variantName
            end

            if settings.assetPreviewEnabled[modulePath] == nil then
                settings.assetPreviewEnabled[modulePath] = true
                settingsChanged = true
            end

            -- A hosted browser has no single class to preview, so its node types are cataloged
            -- one by one under their own labels; every other variant contributes its own class.
            local visualizerClasses = {}
            if spawnList.hostedSources then
                for _, source in ipairs(spawnList.hostedSources) do
                    if source.supportsVisualizer then
                        table.insert(visualizerClasses, {
                            name = source.label,
                            modulePath = source.modulePath,
                            defaultPreviewed = source.defaultPreviewed
                        })
                    end
                end
            elseif supportsSpawnNewVisualizerDefault(variantInstance) then
                visualizerClasses[1] = {
                    name = variantName,
                    modulePath = modulePath,
                    defaultPreviewed = variantInstance.previewed == true
                }
            end

            for _, visualizerClass in ipairs(visualizerClasses) do
                table.insert(visualizerEntries, visualizerClass)
                visualizerModuleSet[visualizerClass.modulePath] = true

                if type(settings.spawnNewVisualizerEnabledByModule[visualizerClass.modulePath]) ~= "boolean" then
                    settings.spawnNewVisualizerEnabledByModule[visualizerClass.modulePath] = visualizerClass.defaultPreviewed
                    settingsChanged = true
                end
            end
        end

        if #visualizerEntries > 0 then
            visualizerGroups[dataName] = visualizerEntries
        end
    end

    pathOrigin.endListScan()

    spawnNewVisualizerClassGroups = visualizerGroups
    spawnNewVisualizerModuleSet = visualizerModuleSet

    -- Single write, instead of one per newly seen module.
    if settingsChanged then
        settings.save()
    end

    spawnUI.selectedType = math.max(utils.indexValue(typeNames, settings.selectedType) - 1, 0)

    variantNames = getSortedVariantNames(typeNames[spawnUI.selectedType + 1])

    spawnUI.selectedVariant = math.max(utils.indexValue(variantNames, settings.lastVariants[settings.selectedType]) - 1, 0)

    spawnUI.refresh()
end

---Returns a table containing the currently active spawnables list, each entry being structured as {data: String|table, name: String, lastSpawned: table}
---@return table
function spawnUI.getActiveSpawnList()
    return spawnData[typeNames[spawnUI.selectedType + 1]][variantNames[spawnUI.selectedVariant + 1]]
end

---Returns the spawn list owning a given spawnable module path, if any.
---@param modulePath string?
---@return table?
function spawnUI.getSpawnListByModulePath(modulePath)
    if type(modulePath) ~= "string" then
        return nil
    end

    return modulePathToSpawnList[modulePath]
end

---Returns the "Type > Variant" label of a given spawnable module path.
---@param modulePath string?
---@return string?
function spawnUI.getVariantLabelByModulePath(modulePath)
    if type(modulePath) ~= "string" then
        return nil
    end

    return modulePathToVariantLabel[modulePath]
end

-- Defined in `style` so resource selectors outside this browser tag paths the same way.
local pathOriginTagInfoByKey = style.pathOriginTagInfo

---Returns true when at least one option is selected in a filter map.
---@param selections table<string, boolean>?
---@return boolean
local function hasSelectedFilterOption(selections)
    for _, isSelected in pairs(selections or {}) do
        if isSelected then
            return true
        end
    end

    return false
end

---@param spawnList table
---@param entry table
---@return string
local function getEntrySearchName(spawnList, entry)
    if spawnList.isPaths and settings.spawnUIOnlyNames then
        return entry.fileName or entry.name or ""
    end

    return entry.name or ""
end

---@param spawnList table
---@param entry table
---@return boolean
local function matchesSearchFilter(spawnList, entry)
    if spawnUI.filter == "" then
        return true
    end

    return utils.matchSearch(getEntrySearchName(spawnList, entry), spawnUI.filter)
end

---Returns the asset path used for path-origin matching and tagging.
---@param entry table
---@param spawnList table?
---@return string
local function getEntryAssetPath(entry, spawnList)
    if not entry then
        return ""
    end

    if spawnList and spawnList.isPaths and entry.data and type(entry.data.spawnData) == "string" then
        return entry.data.spawnData
    end

    if type(entry.name) == "string" then
        return entry.name
    end

    return ""
end

---Normalizes one asset path for hierarchy splitting.
---Converts slashes to `\` and trims surrounding whitespace.
---@param path string?
---@return string
local function normalizeHierarchyAssetPath(path)
    return utils.normalizePath(path, { separator = "backslash" })
end

---Splits an asset path into non-empty hierarchy segments.
---@param path string?
---@return string[] segments
---@return string normalizedPath
local function splitHierarchyAssetPath(path)
    local normalizedPath = normalizeHierarchyAssetPath(path)
    local segments = {}

    for segment in normalizedPath:gmatch("[^\\]+") do
        if segment ~= "" then
            table.insert(segments, segment)
        end
    end

    return segments, normalizedPath
end

---Creates one hierarchy tree node used by Spawn New path-tree rendering.
---@param label string
---@param key string
---@return table
local function createHierarchyTreeNode(label, key)
    return {
        label = label,
        key = key,
        children = {},
        childOrder = {},
        entries = {}
    }
end

local getPathOriginKeyFromPath = style.getPathOriginKeyFromPath

---Gets the path origin key for one search-list entry.
---@param entry table
---@param spawnList table?
---@return string?
local function getEntryPathOriginKey(entry, spawnList)
    if not spawnList or spawnList.isPaths ~= true then
        return nil
    end

    -- Resolved once per entry, `false` meaning no known origin.
    if entry.pathOriginKey == nil then
        entry.pathOriginKey = getPathOriginKeyFromPath(getEntryAssetPath(entry, spawnList)) or false
    end

    return entry.pathOriginKey or nil
end

---Gets tag display metadata for one search-list entry origin.
---@param entry table
---@param spawnList table?
---@return table?
local function getEntryPathOriginTagInfo(entry, spawnList)
    local originKey = getEntryPathOriginKey(entry, spawnList)
    if not originKey then
        return nil
    end

    return pathOriginTagInfoByKey[originKey]
end

--- Spawn New per-entry filters -----------------------------------------------
--
-- Every filter is described once here and driven generically by
-- `spawnUI.updateFilter` (matching), `drawEntryFilters` (UI) and
-- `getFilterState` (per-module selection/search state). Adding a filter means
-- adding one descriptor plus the `entryFilter` field on the spawnable class.

---@class SpawnEntryFilter
---@field id string Unique id, also used as ImGui ID scope.
---@field label string Row label.
---@field supports fun(spawnList: table): boolean Whether the filter applies to a list.
---@field resolveKey fun(entry: table, spawnList: table): string Option key of one entry.
---@field resolveKeys fun(entry: table, spawnList: table): string[]? Option keys of one entry, for multi-value filters.
---@field defaults table<string, boolean>? Initial selection state.
---@field prune boolean? When false, selections are kept even if no entry carries them.
---@field isActive fun(selections: table<string, boolean>): boolean Whether the filter constrains results.
---@field accepts fun(selections: table<string, boolean>, key: string): boolean Entry test.
---@field acceptsKeys fun(selections: table<string, boolean>, keys: string[], state: table): boolean Multi-key entry test.
---@field showAndFilterToggle boolean? Whether the combo exposes an AND/OR mode toggle.
---@field defaultAndFilter boolean? Initial AND/OR mode for new filter state.
---@field formatOptionLabel fun(option: SpawnEntryFilterOption): string? Optional display label for an option.
---@field formatSelectionLabel fun(key: string): string? Optional display label for a single selected key.
---@field showSelectionTooltip boolean? Whether hovering the combo lists its selected raw keys.
---@field matchesOption fun(option: SpawnEntryFilterOption, searchValue: string, idx: integer): boolean? Optional option-list search matcher.
---@field compareOptions fun(a: SpawnEntryFilterOption, b: SpawnEntryFilterOption): boolean? Optional option-list sort comparator.
---@field createState fun(): table? Extra fields merged into this filter's per-list state on creation.
---@field drawCustom fun(filter: SpawnEntryFilter, spawnList: table, state: table): boolean? Draws the filter widget, returning whether anything changed.
---@field acceptsEntry fun(entry: table, spawnList: table, state: table): boolean? Entry test, replacing the key-based one.
---@field isActiveState fun(state: table): boolean? Activity test over the whole state, replacing `isActive`.

---Default activity test: the filter constrains as soon as one option is picked.
---@param selections table<string, boolean>
---@return boolean
local function anySelected(selections)
    return hasSelectedFilterOption(selections)
end

---Default entry test: the entry must carry a key that is currently selected.
---@param selections table<string, boolean>
---@param key string
---@return boolean
local function acceptsSelectedKey(selections, key)
    return key ~= "" and selections[key] == true
end

---@param keys any
---@return string[]
local function normalizeFilterKeys(keys)
    local normalized = {}
    local dedupe = {}

    if type(keys) == "string" then
        keys = { keys }
    end

    if type(keys) ~= "table" then
        return normalized
    end

    for _, key in ipairs(keys) do
        key = tostring(key or "")
        if key ~= "" and not dedupe[key] then
            dedupe[key] = true
            table.insert(normalized, key)
        end
    end

    return normalized
end

---@param filter SpawnEntryFilter
---@param entry table
---@param spawnList table
---@return string[]
local function resolveEntryFilterKeys(filter, entry, spawnList)
    if type(filter.resolveKeys) == "function" then
        return normalizeFilterKeys(filter.resolveKeys(entry, spawnList))
    end

    if type(filter.resolveKey) == "function" then
        return normalizeFilterKeys(filter.resolveKey(entry, spawnList))
    end

    return {}
end

---@param selections table<string, boolean>
---@param keys string[]
---@return boolean
local function acceptsAnySelectedKey(selections, keys)
    for _, key in ipairs(keys or {}) do
        if acceptsSelectedKey(selections, key) then
            return true
        end
    end

    return false
end

---@param selections table<string, boolean>
---@param keys string[]
---@return boolean
local function acceptsAllSelectedKeys(selections, keys)
    local entryKeys = utils.toKeySet(keys)
    local hasSelection = false

    for key, isSelected in pairs(selections or {}) do
        if isSelected then
            hasSelection = true
            if not entryKeys[key] then
                return false
            end
        end
    end

    return hasSelection
end

---@param filter SpawnEntryFilter
---@param state table
---@param keys string[]
---@return boolean
local function acceptsFilterEntry(filter, state, keys)
    if type(filter.acceptsKeys) == "function" then
        return filter.acceptsKeys(state.selections, keys, state)
    end

    if type(filter.accepts) == "function" and type(filter.resolveKeys) ~= "function" then
        return filter.accepts(state.selections, keys[1] or "")
    end

    if state.andFilter == true then
        return acceptsAllSelectedKeys(state.selections, keys)
    end

    return acceptsAnySelectedKey(state.selections, keys)
end

---Criteria the Spawn New audio list does not offer, read by both the panel and the predicate so
---what is drawn and what is applied cannot drift apart.
---@type table<string, boolean>
local AUDIO_METADATA_HIDDEN = { tags = true, duration = true, documented = true }

---Width the sound-metadata popup needs for its label column plus the widest control row.
local AUDIO_METADATA_POPUP_WIDTH = 420

---Draws the sound-metadata filter: a combo previewing the active criteria, whose popup is the
---selector's own criteria panel. Nothing about the panel is restated here - the browser and the
---dropdown draw the same controls, so a criterion added to `soundSelector` shows up in both.
---@param filter SpawnEntryFilter
---@param state table
---@return boolean changed
local function drawAudioMetadataFilter(filter, state)
    style.fieldLabel(filter.label)

    local selections = soundSelector.resolveSelections(state.sound, nil, AUDIO_METADATA_HIDDEN)
    local summary = soundSelector.summarize(selections)
    local changed = false

    ImGui.SetNextItemWidth(filter.comboWidth * style.viewSize)

    -- Pinned to one width, like every other popup in the mod that carries a form: a combo popup
    -- that has to resize spends the resize frame with its contents outside its own clip rect.
    local popupWidth = AUDIO_METADATA_POPUP_WIDTH * style.viewSize
    ImGui.SetNextWindowSizeConstraints(popupWidth, 1, popupWidth, style.getPopupMaxHeight())

    if ImGui.BeginCombo("##audioMetadataFilterCombo", #summary > 0 and table.concat(summary, ", ") or "Any metadata") then
        -- The popup is its own window, so without this the main window counts as unhovered and the
        -- viewport starts taking the clicks and keys meant for the controls.
        input.updateContext("main")

        changed = soundSelector.drawCriteriaPanel(state.sound, {
            hide = AUDIO_METADATA_HIDDEN,
            resetTooltip = "Show every entry again."
        })

        ImGui.EndCombo()
    end
    style.tooltip("Filter the list on what the audio tables know about each event: whether it loops,\nwhether it carries a position, and how far it reaches.")

    return changed
end

---@type SpawnEntryFilter[]
local entryFilters = {
    {
        id = "pathOrigin",
        label = "Asset origin",
        labelTooltip = "Filter entries based on where they come from.\nThis is determined by the starting path of the asset, for example 'base/' or 'mod/'.\nAssets only listed by a third-party list in data/spawnables count as modded, whatever their path.\nChecking all options will show all entries, while unchecking all will show only entries that don't match any known origin.",
        -- Rendered as an inline checkbox row rather than a combo; its keys are a
        -- fixed set, so they must survive lists that happen to contain none of them.
        checkboxes = {
            { key = "base", idSuffix = "Base" },
            { key = "plDlc", idSuffix = "PlDlc" },
            { key = "modded", idSuffix = "Modded" }
        },
        defaults = { base = true, plDlc = true, modded = true },
        prune = false,
        supports = function (spawnList) return spawnList.isPaths == true end,
        resolveKey = function (entry, spawnList) return getEntryPathOriginKey(entry, spawnList) or "" end,
        isActive = function (selections)
            return not (selections.base == true and selections.plDlc == true and selections.modded == true)
        end,
        accepts = function (selections, key)
            -- With nothing checked, only entries of unknown origin remain.
            if not hasSelectedFilterOption(selections) then
                return key == ""
            end

            return acceptsSelectedKey(selections, key)
        end
    },
    {
        id = "deviceClass",
        label = "Device Class Name",
        allLabel = "All classes",
        multiLabel = "%d classes selected",
        searchHint = "Search class name...",
        emptyText = "No class names available",
        noMatchText = "No matching class names",
        selectAllTooltip = "Select all class names",
        unselectAllTooltip = "Unselect all class names (default behavior: show all)",
        clearTooltip = "Clear selected class-name filters",
        comboWidth = 260,
        supports = function (spawnList) return spawnList.entryFilter == "deviceClass" end,
        resolveKey = function (entry, spawnList) return entity.resolveDeviceClassNameForEntry(entry, spawnList.modulePath) end,
        resolveIcon = entity.getDeviceSecondaryIcon,
        isActive = anySelected,
        accepts = acceptsSelectedKey
    },
    {
        -- For variants hosting several spawnable classes: narrows the merged browser down to
        -- one world node type. The key comes off the entry rather than its data, because it
        -- is the list the entry came from that decides its node type.
        id = "nodeType",
        label = "Node type",
        allLabel = "All node types",
        multiLabel = "%d node types selected",
        searchHint = "Search node type...",
        emptyText = "No node types available",
        noMatchText = "No matching node types",
        selectAllTooltip = "Select all node types",
        unselectAllTooltip = "Unselect all node types (default behavior: show all)",
        clearTooltip = "Clear selected node-type filters",
        comboWidth = 220,
        -- A short hosted list shows every node type at once, so filtering it buys nothing and
        -- the variant opts out; the row icons still say which node each entry places.
        supports = function (spawnList) return spawnList.hostedSources ~= nil and not spawnList.hideNodeTypeFilter end,
        resolveKey = function (entry) return resolveHostedNodeType(entry) end,
        -- resolveIcon only receives the key, so the icons are looked up in the map the
        -- hosted sources filled in rather than off the spawn list.
        resolveIcon = function (key) return hostedIconByLabel[key] end,
        isActive = anySelected,
        accepts = acceptsSelectedKey
    },
    {
        id = "recordType",
        label = "Record type",
        allLabel = "All record types",
        multiLabel = "%d record types selected",
        searchHint = "Search record type...",
        emptyText = "No record types available",
        noMatchText = "No matching record types",
        selectAllTooltip = "Select all record types",
        unselectAllTooltip = "Unselect all record types (default behavior: show all)",
        clearTooltip = "Clear selected record-type filters",
        comboWidth = 200,
        supports = function (spawnList) return spawnList.entryFilter == "recordType" end,
        resolveKey = function (entry) return entityRecordClass.getTypePrefix(entry and entry.data and entry.data.spawnData or nil) end,
        resolveIcon = function () return IconGlyphs.AlphaRBoxOutline end,
        isActive = anySelected,
        accepts = acceptsSelectedKey
    },
    {
        -- Synced workspots are indexed separately from rig metadata. Keep this as a one-click
        -- predicate so it composes with both the text search and the supported-rig filter.
        id = "duoWorkspot",
        label = "Duo workspots",
        supports = function (spawnList) return spawnList.modulePath == AI_SPOT_MODULE_PATH end,
        createState = function ()
            return { enabled = false }
        end,
        isActiveState = function (state)
            return state.enabled == true
        end,
        acceptsEntry = function (entry, spawnList)
            return workspotSync.isSynced(getEntryAssetPath(entry, spawnList))
        end,
        drawCustom = function (filter, spawnList, state)
            style.fieldLabel(filter.label)
            local nextEnabled, changed = style.toggleButton(
                IconGlyphs.AccountMultiple .. "##duoWorkspotFilter",
                state.enabled == true
            )
            state.enabled = nextEnabled
            style.tooltip("Show only workspots that are part of a synced animation.")

            return changed
        end
    },
    {
        id = "workspotRig",
        label = "Supported rig",
        allLabel = "All rigs",
        multiLabel = "%d rigs selected",
        searchHint = "Search rig...",
        emptyText = "No rig metadata available",
        noMatchText = "No matching rigs",
        selectAllTooltip = "Select all rigs",
        unselectAllTooltip = "Unselect all rigs (default behavior: show all)",
        clearTooltip = "Clear selected rig filters",
        comboWidth = 200,
        supports = function (spawnList) return spawnList.entryFilter == "workspotRig" end,
        resolveKeys = function (entry, spawnList)
            return aiSpotClass.getWorkspotRigFilterKeys(getEntryAssetPath(entry, spawnList))
        end,
        resolveIcon = aiSpotClass.getRigIcon,
        formatOptionLabel = function (option)
            return aiSpotClass.getRigDisplayName(option.key)
        end,
        formatSelectionLabel = aiSpotClass.getRigDisplayName,
        showSelectionTooltip = true,
        compareOptions = function (a, b)
            local aCharacter = aiSpotClass.isCharacterRig(a.key)
            local bCharacter = aiSpotClass.isCharacterRig(b.key)
            if aCharacter ~= bCharacter then
                return aCharacter
            end

            local aLabel = string.lower(aiSpotClass.getRigDisplayName(a.key))
            local bLabel = string.lower(aiSpotClass.getRigDisplayName(b.key))
            if aLabel ~= bLabel then
                return aLabel < bLabel
            end

            return string.lower(tostring(a.key or "")) < string.lower(tostring(b.key or ""))
        end,
        matchesOption = function (option, searchValue)
            local search = string.lower(tostring(searchValue or ""))
            if search == "" then
                return true
            end

            local label = string.lower(aiSpotClass.getRigDisplayName(option.key))
            local key = string.lower(tostring(option.key or ""))
            return utils.safePatternMatch(label, search) or utils.safePatternMatch(key, search)
        end,
        showAndFilterToggle = true,
        andFilterTooltip = "Require every selected rig instead of any selected rig.",
        andFilterIcon = IconGlyphs.SetCenter,
        isActive = anySelected
    },
    {
        -- Audio events carry the Wwise authoring hierarchy they sit in as tags, which is the only
        -- grouping the game ships for them. Name prefixes split the same kind of sound across
        -- `amb_bl_`, `amb_g_` and `amb_int_`, so tags group the list far better.
        id = "audioTag",
        label = "Sound tag",
        allLabel = "All tags",
        multiLabel = "%d tags selected",
        searchHint = "Search tag...",
        emptyText = "No tags available",
        noMatchText = "No matching tags",
        selectAllTooltip = "Select all tags",
        unselectAllTooltip = "Unselect all tags (default behavior: show all)",
        clearTooltip = "Clear selected tag filters",
        comboWidth = 260,
        supports = function (spawnList) return spawnList.entryFilter == "audio" end,
        resolveKeys = function (entry, spawnList)
            return audioData.getEventTags(getEntryAssetPath(entry, spawnList))
        end,
        resolveIcon = function () return IconGlyphs.TagOutline end,
        showAndFilterToggle = true,
        andFilterTooltip = "Require every selected tag instead of any selected tag.",
        andFilterIcon = IconGlyphs.SetCenter,
        isActive = anySelected
    },
    {
        -- The same metadata criteria the sound selector filters on, over the browser's own list, so
        -- picking an emitter to place and picking an event for a field are the same act of search.
        -- A predicate filter rather than a key-based one: a range of metres is not a set of names.
        id = "audioMetadata",
        label = "Sound metadata",
        comboWidth = 260,
        supports = function (spawnList) return spawnList.entryFilter == "audio" end,
        -- Which criteria are dropped, and why, is recorded on `AUDIO_METADATA_HIDDEN` - one set,
        -- read by both the panel and the predicate, so what is drawn and what is applied cannot
        -- drift apart.
        createState = function ()
            return { sound = soundSelector.newFilterState() }
        end,
        -- Resolved here rather than per entry: `updateFilter` calls this once per pass, before the
        -- entry loop, so the selections are built once for the whole list instead of 2,799 times.
        isActiveState = function (state)
            state.soundSelections = soundSelector.resolveSelections(state.sound, nil, AUDIO_METADATA_HIDDEN)

            return soundSelector.isFiltering(state.soundSelections)
        end,
        acceptsEntry = function (entry, spawnList, state)
            local selections = state.soundSelections
                or soundSelector.resolveSelections(state.sound, nil, AUDIO_METADATA_HIDDEN)

            return soundSelector.matches(getEntryAssetPath(entry, spawnList), selections)
        end,
        drawCustom = function (filter, spawnList, state)
            return drawAudioMetadataFilter(filter, state)
        end
    }
}

-- Available-key sets and option lists are derived from the whole spawn list, which
-- can hold tens of thousands of entries. Both are cached per module path; the
-- option cache additionally keys on the search text it counted against.
local availableFilterKeysCache = {}
local filterOptionsCache = {}

---Drops every cached filter derivation. Called on load and whenever a list changes.
function spawnUI.invalidateFilterCaches()
    availableFilterKeysCache = {}
    filterOptionsCache = {}
end

---Drops the flattened hierarchy row list so it gets rebuilt on the next draw.
---Call whenever the tree itself or any folder open state changed.
function spawnUI.invalidateHierarchyRows()
    spawnUI.hierarchyRows = nil
    spawnUI.hierarchyRowsRoot = nil
end

---@param filter SpawnEntryFilter
---@param spawnList table
---@return string
local function getFilterCacheKey(filter, spawnList)
    return filter.id .. "\0" .. tostring(spawnList.modulePath)
end

---Gets or lazily creates the per-module selection/search state of one filter.
---@param filter SpawnEntryFilter
---@param spawnList table?
---@return {selections: table<string, boolean>, search: string}?
local function getFilterState(filter, spawnList)
    if not spawnList or not filter.supports(spawnList) then
        return nil
    end

    local byModule = spawnUI.entryFilterStateByModule[filter.id]
    if not byModule then
        byModule = {}
        spawnUI.entryFilterStateByModule[filter.id] = byModule
    end

    local state = byModule[spawnList.modulePath]
    if not state then
        state = {
            selections = utils.deepcopy(filter.defaults or {}),
            search = "",
            andFilter = filter.defaultAndFilter == true
        }

        -- A predicate filter keeps whatever shape it needs beside the standard fields.
        if type(filter.createState) == "function" then
            for key, value in pairs(filter.createState()) do
                state[key] = value
            end
        end

        byModule[spawnList.modulePath] = state
    elseif filter.showAndFilterToggle == true and state.andFilter == nil then
        state.andFilter = filter.defaultAndFilter == true
    end

    return state
end

---Set of option keys present anywhere in the list. Independent of the search text.
---@param filter SpawnEntryFilter
---@param spawnList table
---@return table<string, boolean>
local function getAvailableFilterKeys(filter, spawnList)
    local cacheKey = getFilterCacheKey(filter, spawnList)
    local cached = availableFilterKeysCache[cacheKey]
    if cached then
        return cached
    end

    local availableKeys = {}
    for _, entry in ipairs(spawnList.data) do
        for _, key in ipairs(resolveEntryFilterKeys(filter, entry, spawnList)) do
            availableKeys[key] = true
        end
    end

    availableFilterKeysCache[cacheKey] = availableKeys

    return availableKeys
end

---@class SpawnEntryFilterOption
---@field key string
---@field icon string
---@field count number Entries matching the current search text.

---Builds the option rows (icon + key + count) of one filter for the active list.
---@param filter SpawnEntryFilter
---@param spawnList table
---@return SpawnEntryFilterOption[]
local function getFilterOptions(filter, spawnList)
    local cacheKey = getFilterCacheKey(filter, spawnList)
    local cached = filterOptionsCache[cacheKey]
    if cached and cached.search == spawnUI.filter then
        return cached.options
    end

    local resolveIcon = filter.resolveIcon
    local optionsByKey = {}

    for _, entry in ipairs(spawnList.data) do
        for _, key in ipairs(resolveEntryFilterKeys(filter, entry, spawnList)) do
            local option = optionsByKey[key]
            if not option then
                option = { key = key, icon = resolveIcon and resolveIcon(key) or "", count = 0 }
                optionsByKey[key] = option
            end

            if matchesSearchFilter(spawnList, entry) then
                option.count = option.count + 1
            end
        end
    end

    local options = {}
    for _, option in pairs(optionsByKey) do
        if option.count > 0 then
            table.insert(options, option)
        end
    end

    if filter.compareOptions then
        table.sort(options, filter.compareOptions)
    else
        table.sort(options, function (a, b)
            local aLabel = filter.formatOptionLabel and filter.formatOptionLabel(a) or a.key
            local bLabel = filter.formatOptionLabel and filter.formatOptionLabel(b) or b.key
            return string.lower(aLabel) < string.lower(bLabel)
        end)
    end

    filterOptionsCache[cacheKey] = { search = spawnUI.filter, options = options }

    return options
end

---Formats a search result label while reserving width for an optional secondary icon prefix.
---@param text string
---@param width number
---@param secondaryIcon string?
---@return string
local function formatSearchResultButtonText(text, width, secondaryIcon)
    local icon = tostring(secondaryIcon or "")
    if icon == "" then
        return utils.shortenPath(text, width, true)
    end

    local iconPrefix = icon .. " "
    local iconWidth, _ = ImGui.CalcTextSize(iconPrefix)
    local contentWidth = math.max(1, width - iconWidth)

    return iconPrefix .. utils.shortenPath(text, contentWidth, true)
end

--- Spawn New per-entry notes -------------------------------------------------------------------
--
-- A short annotation drawn at the right edge of a result row, for lists where one fact decides the
-- choice and only shows up after spawning otherwise. Same shape as `entryFilters`: one descriptor
-- here plus an `entryNote` field on the spawnable class.

---@class SpawnEntryNote
---@field id string Value a spawnable's `entryNote` field must carry.
---@field resolve fun(entry: table, spawnList: table): { text: string, tooltip: string, warn: boolean? }?

---@type SpawnEntryNote[]
local entryNotes = {
    {
        -- How far a sound event carries, and a warning on the handful that do not keep playing.
        id = "audioRange",
        resolve = function (entry, spawnList)
            return audioData.getEventRowNote(getEntryAssetPath(entry, spawnList))
        end
    }
}

---@param entry table
---@param spawnList table
---@return { text: string, tooltip: string, warn: boolean? }? note
local function getEntryNote(entry, spawnList)
    if not spawnList or not spawnList.entryNote then
        return nil
    end

    for _, descriptor in ipairs(entryNotes) do
        if descriptor.id == spawnList.entryNote then
            local ok, note = pcall(descriptor.resolve, entry, spawnList)

            return ok and note or nil
        end
    end

    return nil
end

-- Same tone as the "Base" asset origin tag
local FAVORITE_STAR_COLOR = pathOriginTagInfoByKey.base.color

local drawPathOriginTagChip = style.drawPathOriginTagChip

---Persists Spawn New search text only when it actually changed.
local function saveSpawnUIFilterIfChanged()
    local nextFilter = tostring(spawnUI.filter or "")
    if settings.spawnUIFilter == nextFilter then
        return
    end

    settings.spawnUIFilter = nextFilter
    settings.save()
end

---Builds a cached hierarchy tree from current filtered path results.
---Tree folders map to path segments; leaves map to filtered spawn entries.
function spawnUI.rebuildHierarchyTree()
    spawnUI.invalidateHierarchyRows()

    local activeSpawnList = spawnUI.getActiveSpawnList()
    if not activeSpawnList or not activeSpawnList.isPaths then
        spawnUI.filteredHierarchyTree = nil
        return
    end

    local root = createHierarchyTreeNode("", "__root__:" .. tostring(activeSpawnList.modulePath or ""))

    for _, entry in ipairs(spawnUI.filteredList) do
        local segments, normalizedPath = splitHierarchyAssetPath(getEntryAssetPath(entry, activeSpawnList))
        local node = root

        if #segments == 0 then
            local fallbackLabel = tostring(entry.fileName or entry.name or "")
            table.insert(root.entries, {
                entry = entry,
                label = fallbackLabel,
                sortKey = string.lower(fallbackLabel),
                pathKey = fallbackLabel
            })
        else
            for idx = 1, #segments - 1 do
                local segment = segments[idx]
                local child = node.children[segment]
                if not child then
                    local childKey = node.key .. "\\" .. segment
                    child = createHierarchyTreeNode(segment, childKey)
                    node.children[segment] = child
                    table.insert(node.childOrder, segment)
                end

                node = child
            end

            local leafLabel = segments[#segments]
            table.insert(node.entries, {
                entry = entry,
                label = leafLabel,
                sortKey = string.lower(leafLabel),
                pathKey = normalizedPath ~= "" and normalizedPath or tostring(entry.name or leafLabel)
            })
        end
    end

    local function sortHierarchyTreeNode(nodeRef)
        table.sort(nodeRef.childOrder, function(a, b)
            local aLower = string.lower(a)
            local bLower = string.lower(b)
            if aLower == bLower then
                return a < b
            end

            return aLower < bLower
        end)

        table.sort(nodeRef.entries, function(a, b)
            if a.sortKey == b.sortKey then
                return tostring(a.pathKey or "") < tostring(b.pathKey or "")
            end

            return a.sortKey < b.sortKey
        end)

        for _, childKey in ipairs(nodeRef.childOrder) do
            sortHierarchyTreeNode(nodeRef.children[childKey])
        end
    end

    sortHierarchyTreeNode(root)
    spawnUI.filteredHierarchyTree = root
end

---Regenerate the filteredList based on the active filter and the currently selected active spawn list
function spawnUI.updateFilter()
    -- Always the full pass, so any debounced request is now satisfied.
    spawnUI.pendingFilterUpdate = false

    local activeSpawnList = spawnUI.getActiveSpawnList()
    local orderedData = getOrderedSpawnListData(activeSpawnList)
    local activeFilters = {}

    for _, filter in ipairs(entryFilters) do
        local state = getFilterState(filter, activeSpawnList)
        if state then
            -- A predicate filter has no option keys to prune, and decides for itself whether it is
            -- narrowing anything: its state is ranges and tri-states, not a selection set.
            if type(filter.isActiveState) == "function" then
                if filter.isActiveState(state) then
                    table.insert(activeFilters, { filter = filter, state = state })
                end
            else
                if filter.prune ~= false then
                    utils.pruneKeys(state.selections, getAvailableFilterKeys(filter, activeSpawnList))
                end

                if filter.isActive(state.selections) then
                    table.insert(activeFilters, { filter = filter, state = state })
                end
            end
        end
    end

    -- The source lists are pre-sorted at load, so both branches come out ordered
    -- without ever sorting (or mutating) the loaded data.
    if spawnUI.filter == "" and #activeFilters == 0 then
        spawnUI.filteredList = orderedData
        spawnUI.filteredHierarchyTree = nil
        spawnUI.invalidateHierarchyRows()
        return
    end

    spawnUI.filteredList = {}
    for _, data in ipairs(orderedData) do
        if matchesSearchFilter(activeSpawnList, data) then
            local include = true

            for _, active in ipairs(activeFilters) do
                local accepted
                if type(active.filter.acceptsEntry) == "function" then
                    accepted = active.filter.acceptsEntry(data, activeSpawnList, active.state)
                else
                    local keys = resolveEntryFilterKeys(active.filter, data, activeSpawnList)
                    accepted = acceptsFilterEntry(active.filter, active.state, keys)
                end

                if not accepted then
                    include = false
                    break
                end
            end

            if include then
                table.insert(spawnUI.filteredList, data)
            end
        end
    end

    -- Built lazily by `resolveHierarchyRoot`, so the flat view never pays for it.
    spawnUI.filteredHierarchyTree = nil
    spawnUI.invalidateHierarchyRows()
end

-- `updateFilter` rescans every entry of the active list (~47k paths for meshes). Running that on
-- the keystroke frame stretches the frame past ImGui's key repeat delay (0.275s), making one
-- physical Ctrl+V or Delete read as two. Deferring keeps the edit frame cheap and coalesces bursts.
local FILTER_UPDATE_DEBOUNCE = 0.15

---Requests a re-filter after the debounce delay, restarting it if one is already pending.
---Use for the search text; discrete changes (filter toggles, variant switches) stay immediate.
function spawnUI.requestFilterUpdate()
    spawnUI.pendingFilterUpdate = true
    spawnUI.pendingFilterUpdateAt = ImGui.GetTime() + FILTER_UPDATE_DEBOUNCE
end

---Runs a debounced re-filter right away. No-op when nothing is pending.
---Call before anything that consumes `filteredList` outside the results list itself.
function spawnUI.flushPendingFilterUpdate()
    if not spawnUI.pendingFilterUpdate then return end

    spawnUI.updateFilter()
end

---Applies a pending re-filter once its delay has elapsed. Called once per drawn frame.
local function tickPendingFilterUpdate()
    if not spawnUI.pendingFilterUpdate then return end
    if ImGui.GetTime() < spawnUI.pendingFilterUpdateAt then return end

    spawnUI.updateFilter()
end

---Draws one filter as an inline checkbox row (fixed option set).
---@param filter SpawnEntryFilter
---@param selections table<string, boolean>
---@return boolean changed
local function drawFilterCheckboxRow(filter, selections)
    local changed = false

    ImGui.AlignTextToFramePadding()
    style.mutedText(filter.label)
    style.tooltip(filter.labelTooltip)

    for _, option in ipairs(filter.checkboxes) do
        ImGui.SameLine()

        local tagInfo = pathOriginTagInfoByKey[option.key]
        local optionChanged
        selections[option.key], optionChanged = ImGui.Checkbox(
            tagInfo.label .. "##" .. filter.id .. option.idSuffix,
            selections[option.key] == true
        )
        if tostring(tagInfo.tooltip or "") ~= "" then
            style.tooltip(tagInfo.tooltip)
        end

        if optionChanged then
            changed = true
        end
    end

    return changed
end

---Draws one filter as a searchable multi-select combo.
---@param filter SpawnEntryFilter
---@param spawnList table
---@param state {selections: table<string, boolean>, search: string}
---@return boolean changed
local function drawFilterCombo(filter, spawnList, state)
    style.fieldLabel(filter.label)

    local selectionTooltip = nil
    if filter.showSelectionTooltip then
        local selectedKeys = {}
        for key, isSelected in pairs(state.selections) do
            if isSelected == true then
                table.insert(selectedKeys, tostring(key))
            end
        end
        table.sort(selectedKeys)

        selectionTooltip = #selectedKeys > 0
            and ("Selected:\n" .. table.concat(selectedKeys, "\n"))
            or filter.allLabel
    end

    local andFilterChanged = false
    local changed, nextSearch = style.drawSearchableMultiSelectCombo({
        comboId = "##" .. filter.id .. "FilterCombo",
        previewLabel = style.getMultiSelectPreviewLabel(
            state.selections,
            filter.allLabel,
            filter.multiLabel,
            filter.formatSelectionLabel
        ),
        tooltip = selectionTooltip,
        searchHint = filter.searchHint,
        searchValue = state.search,
        getOptions = function ()
            return getFilterOptions(filter, spawnList)
        end,
        selections = state.selections,
        comboWidth = filter.comboWidth * style.viewSize,
        searchWidth = 220 * style.viewSize,
        emptyText = filter.emptyText,
        noMatchText = filter.noMatchText,
        searchInputId = "##" .. filter.id .. "FilterSearch",
        searchClearButtonId = "##" .. filter.id .. "FilterSearchClear",
        selectAllButtonId = "##" .. filter.id .. "SelectAll",
        unselectAllButtonId = "##" .. filter.id .. "UnselectAll",
        optionIdPrefix = "##" .. filter.id .. "Option",
        selectAllTooltip = filter.selectAllTooltip,
        unselectAllTooltip = filter.unselectAllTooltip,
        showAndFilterToggle = filter.showAndFilterToggle == true,
        andFilterState = state.andFilter == true,
        onAndFilterChanged = function (nextState)
            state.andFilter = nextState == true
            andFilterChanged = true
        end,
        andFilterTooltip = filter.andFilterTooltip,
        andFilterIcon = filter.andFilterIcon,
        showClearSelectionButton = true,
        clearSelectionButtonId = "##" .. filter.id .. "FilterSelectionClear",
        clearSelectionTooltip = filter.clearTooltip,
        matchesOption = filter.matchesOption,
        getOptionKey = function (option)
            return option.key
        end,
        getOptionLabel = function (option)
            local labelIcon = option.icon ~= "" and (option.icon .. " ") or ""
            local label = filter.formatOptionLabel and filter.formatOptionLabel(option) or option.key
            return string.format("%s%s (%d)", labelIcon, label, option.count)
        end
    })

    state.search = nextSearch

    return changed or andFilterChanged
end

---Draws every per-entry filter supported by the active spawn list.
---@return boolean changed
local function drawEntryFilters()
    local activeSpawnList = spawnUI.getActiveSpawnList()
    local changed = false

    for _, filter in ipairs(entryFilters) do
        local state = getFilterState(filter, activeSpawnList)
        if state then
            local filterChanged
            if type(filter.drawCustom) == "function" then
                filterChanged = filter.drawCustom(filter, activeSpawnList, state)
            elseif filter.checkboxes then
                filterChanged = drawFilterCheckboxRow(filter, state.selections)
            else
                filterChanged = drawFilterCombo(filter, activeSpawnList, state)
            end

            changed = changed or filterChanged
        end
    end

    return changed
end

---Refresh the visible results. Ordering comes from the pre-sorted spawn lists,
---so this is now just the filter pass.
function spawnUI.refresh()
    spawnUI.updateFilter()
end

---Applies and persists the selected category, then refreshes variant list and results.
function spawnUI.updateCategory()
    settings.selectedType = typeNames[spawnUI.selectedType + 1]
    settings.save()

    variantNames = getSortedVariantNames(typeNames[spawnUI.selectedType + 1])

    spawnUI.selectedVariant = math.max(utils.indexValue(variantNames, settings.lastVariants[settings.selectedType]) - 1, 0)

    spawnUI.refresh()
end

---Applies and persists the selected variant, then refreshes results.
function spawnUI.updateVariant()
    settings.lastVariants[settings.selectedType] = variantNames[spawnUI.selectedVariant + 1]
    settings.save()

    spawnUI.refresh()
end

---Selects a spawn type and variant by display names.
---Returns false when either name is unknown.
---@param typeName string
---@param variantName string
---@return boolean
function spawnUI.selectTypeAndVariant(typeName, variantName)
    if not types[typeName] or not types[typeName].variants[variantName] then
        return false
    end

    local typeIndex = utils.indexValue(typeNames, typeName)
    if typeIndex < 1 then
        return false
    end

    spawnUI.selectedType = typeIndex - 1
    spawnUI.updateCategory()

    local variantIndex = utils.indexValue(variantNames, variantName)
    if variantIndex < 1 then
        return false
    end

    spawnUI.selectedVariant = variantIndex - 1
    spawnUI.updateVariant()

    return true
end

local DEFAULT_HOVER_PREVIEW_DEBOUNCE_SECONDS = 0.1

---@param component IComponent?
---@return boolean
local function getComponentEnabledState(component)
    if not component then
        return false
    end

    local okEnabled, isEnabled = pcall(function ()
        return component:IsEnabled()
    end)

    return okEnabled and isEnabled == true
end

---@param component IComponent?
---@param enabled boolean
local function setComponentEnabled(component, enabled)
    if not component then
        return
    end

    if getComponentEnabledState(component) == enabled then
        return
    end

    pcall(function ()
        component:Toggle(enabled)
    end)
end

---@param entity entEntity?
---@param componentName string
---@return IComponent?
local function findEntityComponent(entity, componentName)
    if not entity or not componentName then
        return nil
    end

    local okComponent, component = pcall(function ()
        return entity:FindComponentByName(componentName)
    end)

    if not okComponent then
        return nil
    end

    return component
end

---Returns the `flashlight` mod logic table when available.
---Uses nil-safe checks because this integration is optional.
---@return table?
local function getExternalFlashlightLogic()
    local flashlightMod = GetMod("flashlight")
    if not flashlightMod or not flashlightMod.logic then
        return nil
    end

    return flashlightMod.logic
end

---Returns the external flashlight light component if it can be resolved safely.
---Falls back to `nil` when the mod is missing, unloaded, or errors.
---@return IComponent?
local function getExternalFlashlightComponent()
    local flashlightLogic = getExternalFlashlightLogic()
    if not flashlightLogic or type(flashlightLogic.getComponent) ~= "function" then
        return nil
    end

    local okComponent, component = pcall(flashlightLogic.getComponent)
    if not okComponent then
        return nil
    end

    return component
end

---Suppresses light contribution from the external flashlight mod while preview is active.
---Primary path sets `brightnessOverride = 0` in flashlight logic, matching how the mod computes light.
---A component-level `SetStrength(0)` call is kept as defensive fallback.
local function suppressExternalFlashlightDuringPreview()
    local flashlightLogic = getExternalFlashlightLogic()
    if flashlightLogic then
        if not spawnUI.flashlightSuppressionCaptured then
            spawnUI.flashlightSuppressionCaptured = true
            spawnUI.flashlightSuppressionPreviousOverride = flashlightLogic.brightnessOverride
        end

        flashlightLogic.brightnessOverride = 0
    end

    local component = spawnUI.flashlightSuppressionComponent
    if not component then
        component = getExternalFlashlightComponent()
    end

    if not component then
        spawnUI.flashlightSuppressionComponent = nil
        return
    end

    local okSuppressed = pcall(function ()
        component:SetStrength(0)
    end)

    if okSuppressed then
        spawnUI.flashlightSuppressionComponent = component
    else
        spawnUI.flashlightSuppressionComponent = nil
    end
end

---Restores external flashlight state after preview is hidden.
---Only restores `brightnessOverride` if WB captured an original value when suppression began.
local function restoreExternalFlashlightAfterPreview()
    local flashlightLogic = getExternalFlashlightLogic()
    if flashlightLogic and spawnUI.flashlightSuppressionCaptured then
        flashlightLogic.brightnessOverride = spawnUI.flashlightSuppressionPreviousOverride
    end

    spawnUI.flashlightSuppressionComponent = nil
    spawnUI.flashlightSuppressionCaptured = false
    spawnUI.flashlightSuppressionPreviousOverride = nil
end

---Collects spawned elements whose spawnable declares `previewSuppressedComponents`.
---@return table
local function buildLightSuppressionTargets()
    local targets = {}
    if not spawnUI.spawnedUI or not spawnUI.spawnedUI.root then
        return targets
    end

    for _, entry in ipairs(spawnUI.spawnedUI.root:getPathsRecursive(true)) do
        local ref = entry.ref
        local suppression = utils.isA(ref, "spawnableElement")
            and ref.spawnable
            and ref.spawnable.previewSuppressedComponents
            or nil

        if suppression then
            table.insert(targets, {
                spawnable = ref.spawnable,
                lightComponentName = suppression.light,
                visualizerComponentNames = suppression.visualizers or {}
            })
        end
    end

    return targets
end

---@param target table
---@return entEntity?
local function resolveLightSuppressionEntity(target)
    if not target or not target.spawnable or type(target.spawnable.getEntity) ~= "function" then
        return nil
    end

    local okEntity, entity = pcall(function ()
        return target.spawnable:getEntity()
    end)

    if not okEntity then
        return nil
    end

    return entity
end

---@return table
function spawnUI.getLightSuppressionTargets()
    local epoch = -1
    if spawnUI.spawnedUI then
        epoch = spawnUI.spawnedUI.cacheEpoch or -1
    end

    if not spawnUI.lightSuppressionTargetsCache or spawnUI.lightSuppressionTargetsCacheEpoch ~= epoch then
        spawnUI.lightSuppressionTargetsCache = buildLightSuppressionTargets()
        spawnUI.lightSuppressionTargetsCacheEpoch = epoch
    end

    return spawnUI.lightSuppressionTargetsCache
end

---@param state boolean
function spawnUI.setAssetPreviewActive(state)
    local shouldBeActive = state == true
    if spawnUI.assetPreviewActive == shouldBeActive then
        return
    end

    spawnUI.assetPreviewActive = shouldBeActive

    if shouldBeActive then
        spawnUI.activeLightSuppressionStates = {}
        spawnUI.flashlightSuppressionComponent = nil
        spawnUI.flashlightSuppressionCaptured = false
        spawnUI.flashlightSuppressionPreviousOverride = nil

        for _, target in ipairs(spawnUI.getLightSuppressionTargets()) do
            local stateEntry = {
                target = target,
                lightSuppressed = false,
                lightWasEnabled = false,
                visualizerWasEnabled = {}
            }

            local entity = resolveLightSuppressionEntity(target)
            if entity then
                if target.lightComponentName and target.spawnable and target.spawnable.cameraFollowEnabled == true then
                    local lightComponent = findEntityComponent(entity, target.lightComponentName)
                    stateEntry.lightSuppressed = true
                    stateEntry.lightWasEnabled = getComponentEnabledState(lightComponent)
                    if stateEntry.lightWasEnabled and lightComponent then
                        setComponentEnabled(lightComponent, false)
                    end
                end

                for _, componentName in ipairs(target.visualizerComponentNames or {}) do
                    local component = findEntityComponent(entity, componentName)
                    local wasEnabled = getComponentEnabledState(component)
                    stateEntry.visualizerWasEnabled[componentName] = wasEnabled
                    if wasEnabled and component then
                        setComponentEnabled(component, false)
                    end
                end
            end

            table.insert(spawnUI.activeLightSuppressionStates, stateEntry)
        end

        suppressExternalFlashlightDuringPreview()

        return
    end

    for _, stateEntry in ipairs(spawnUI.activeLightSuppressionStates) do
        local target = stateEntry.target
        local entity = resolveLightSuppressionEntity(target)

        if entity then
            if stateEntry.lightSuppressed then
                local lightComponent = findEntityComponent(entity, target.lightComponentName)
                if lightComponent then
                    setComponentEnabled(lightComponent, stateEntry.lightWasEnabled)
                end
            end

            for componentName, wasEnabled in pairs(stateEntry.visualizerWasEnabled) do
                local component = findEntityComponent(entity, componentName)
                if wasEnabled ~= nil and component then
                    setComponentEnabled(component, wasEnabled)
                end
            end
        end
    end

    spawnUI.activeLightSuppressionStates = {}
    restoreExternalFlashlightAfterPreview()
end

---Stops pending hover preview timers and disables the active preview instance.
function spawnUI.stopActiveAssetPreview()
    if spawnUI.previewTimer then
        Cron.Halt(spawnUI.previewTimer)
        spawnUI.previewTimer = nil
    end

    if spawnUI.previewInstance then
        spawnUI.previewInstance:assetPreview(false)
        spawnUI.previewInstance = nil
    end

    prefabPreview.stop()
    previewControls.reset()

    spawnUI.setAssetPreviewActive(false)
end

---@param favorite favorite
function spawnUI.handlePrefabPreviewHovered(favorite)
    if spawnUI.hoveredEntry == favorite then return end

    spawnUI.stopActiveAssetPreview()
    spawnUI.hoveredEntry = favorite

    spawnUI.previewTimer = Cron.After(DEFAULT_HOVER_PREVIEW_DEBOUNCE_SECONDS, function ()
        spawnUI.previewTimer = nil
        if spawnUI.hoveredEntry ~= favorite then return end
        if not editor.getCameraRotation() then return end

        prefabPreview.start(favorite.data)
    end)
end

---@param entry table|favorite
---@param isFavorite boolean
---@param spawnListOverride table? Spawn list to preview with, when the entry does not belong to the active one
function spawnUI.handleAssetPreviewHovered(entry, isFavorite, spawnListOverride)
    if spawnUI.hoveredEntry ~= entry then
        spawnUI.stopActiveAssetPreview()

        spawnUI.hoveredEntry = entry

        local activeSpawnList = spawnListOverride or spawnUI.getActiveSpawnList()
        local assetPreviewType = activeSpawnList.assetPreviewType
        local assetPreviewDelay = activeSpawnList.assetPreviewDelay
        if isFavorite then
            -- If its favorite, then entry is just the favorite instance
            if entry.data.modulePath ~= "modules/classes/editor/spawnableElement" then
                assetPreviewType = "none"
            else
                assetPreviewDelay = modulePathToSpawnList[entry.data.spawnable.modulePath].assetPreviewDelay
                assetPreviewType = modulePathToSpawnList[entry.data.spawnable.modulePath].assetPreviewType
            end
        end

        if assetPreviewType == "none" then return end

        local previewDelay = assetPreviewDelay or DEFAULT_HOVER_PREVIEW_DEBOUNCE_SECONDS
        spawnUI.previewTimer = Cron.After(previewDelay, function ()
            spawnUI.previewTimer = nil
            if not spawnUI.hoveredEntry then return end

            local data = utils.deepcopy(entry.data)
            if isFavorite then
                spawnUI.previewInstance = utils.requireSpawnable(data.spawnable.modulePath):new()
                data = data.spawnable
            else
                spawnUI.previewInstance = resolveEntryClass(activeSpawnList, entry):new()
                data.modulePath = spawnUI.previewInstance.modulePath
                applySpawnNewEntryDefaults(data)
            end

            local pos, _ = spawnUI.getSpawnNewPosition()
            local rot = editor.getCameraFacingRotation()
            if not rot then return end

            spawnUI.previewInstance:loadSpawnData(data, pos, rot)

            -- Hovering must never be what takes the game down: an entry whose asset this class
            -- cannot spawn is silently not previewed. Committing to the spawn reports it instead.
            if spawnUI.previewInstance:getAssetSpawnBlock() then
                spawnUI.previewInstance = nil
                return
            end

            spawnUI.previewInstance:assetPreview(true)
            spawnUI.setAssetPreviewActive(true)
        end)
    end
end

---Runs per-frame maintenance for asset previews.
function spawnUI.updateAssetPreview()
    if spawnUI.assetPreviewActive then
        suppressExternalFlashlightDuringPreview()
    end

    -- Has to run before the previews are moved, they read the resulting orbit / zoom this frame
    if spawnUI.previewInstance or prefabPreview.isActive() then
        previewControls.update()
    end

    if spawnUI.previewInstance and spawnUI.previewInstance:isSpawned() then
        spawnUI.previewInstance:assetPreviewSetPosition()
    end

    prefabPreview.update()
end

---Draws spawn-position controls and returns the alignment X coordinate.
---@return number
function spawnUI.drawSpawnPosition()
    style.mutedText("Spawn position")
    ImGui.SameLine()
    local x = ImGui.GetCursorPosX()
    ImGui.PushItemWidth(100 * style.viewSize)
    local spawnPositionOptions = { "At selected", "Screen center" }
    local pos, changed = ImGui.Combo("##spawnPos", settings.spawnPos - 1, spawnPositionOptions, #spawnPositionOptions)
    settings.spawnPos = pos + 1
    if changed then settings.save() end
    if settings.spawnPos == 1 then
        style.comboValueTooltip(pos, spawnPositionOptions, "Spawn the new object at the position of the selected object(s), if none are selected, it will spawn in front of the camera.")
    else
        style.comboValueTooltip(pos, spawnPositionOptions, "Spawn position is relative to the camera position and orientation.")
    end

    ImGui.SameLine()

    style.mutedText(IconGlyphs.InformationOutline)
    style.tooltip("To spawn an object under the cursor, either:\n - Use the Shift-A menu while in editor mode\n - Drag and drop an object from the list to the desired position on the screen.")

    return x
end

---Draws a small drag-follow window while dragging an entry.
function spawnUI.drawDragWindow()
    if not spawnUI.dragging then return end

    local x, y = ImGui.GetMousePos()
    ImGui.SetNextWindowPos(x + 10 * style.viewSize, y + 10 * style.viewSize, ImGuiCond.Always)
    if ImGui.Begin("##wb-drag-wui", ImGuiWindowFlags.NoResize + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoBackground + ImGuiWindowFlags.AlwaysAutoResize) then
        ImGui.Text(spawnUI.dragData.name)
        ImGui.End()
    end
end

---Stages the "Save as prefab" creation popup for one spawn list entry.
---The entry is turned into a transform-less spawnable element first, so the
---created prefab only carries the asset itself.
---@param entry table
---@param class table
function spawnUI.savePrefabFromEntry(entry, class)
    local new = require("modules/classes/editor/spawnableElement"):new(spawnUI.spawnedUI)
    local data = utils.deepcopy(entry.data)
    data.modulePath = class:new().modulePath
    data.position = { x = 0, y = 0, z = 0, w = 0 }
    data.rotation = { roll = 0, pitch = 0, yaw = 0 }

    new:load({
        name = entry.fileName or utils.getFileName(entry.name),
        modulePath = new.modulePath,
        spawnable = data
    })

    spawnUI.prefabsUI.addNewItem(new:serialize(), new.name, new.icon)
end

---Handles the shared "drag a list row out into the world to spawn it" interaction.
---Call right after the clickable widget of the row, when it was not clicked.
---@param payload table Drag payload, shown in the drag window (needs a `name`).
---@param onDrop fun(payload: table) Called once when the drag is released outside the row.
function spawnUI.handleRowDrag(payload, onDrop)
    local dragging = ImGui.IsMouseDragging(0, style.draggingThreshold)

    if dragging then
        if not spawnUI.dragging and ImGui.IsItemHovered() then
            spawnUI.dragging = true
            spawnUI.dragData = payload
        end

        return
    end

    if not spawnUI.dragging then return end

    if not ImGui.IsItemHovered() then
        spawnUI.popupSpawnHit = editor.getCursorSceneHit()
        onDrop(spawnUI.dragData)
    end

    spawnUI.dragging = false
    spawnUI.dragData = nil
    spawnUI.popupSpawnHit = nil
end

---Draws the favorite marker shown at the end of a search-result row.
---@param modulePath string?
---@param path string?
local function drawFavoriteRowMarker(modulePath, path)
    local favorite = assetFavorites.get(modulePath, path)
    if not favorite then
        return
    end

    ImGui.SameLine()
    ImGui.AlignTextToFramePadding()
    style.styledText(IconGlyphs.StarBoxOutline, FAVORITE_STAR_COLOR)
    style.tooltip("Marked as favorite\n" .. spawnUI.favoritesUI.getTagsText(favorite))
end

---Turns spawn list entries into the items the favorites system stores.
---Mirrors what the per-row context menu passes for a single entry.
---@param entries table[]
---@return assetFavoriteBulkItem[]
local function buildFavoriteItems(entries)
    local items = {}

    for _, entry in ipairs(entries) do
        table.insert(items, {
            path = entry.name,
            name = entry.fileName or utils.getFileName(entry.name),
            data = entry.data
        })
    end

    return items
end

---Opens the bulk favorite popup for a set of entries of the active list.
---@param entries table[]
---@param sourceLabel string
local function openBulkFavorite(entries, sourceLabel)
    local activeSpawnList = spawnUI.getActiveSpawnList()

    -- Keyed by the browser's module path, like the per-row favorite action: a variant
    -- hosting several spawnable classes stores all of its assets under the host.
    spawnUI.favoritesUI.openBulkAdd(activeSpawnList.modulePath, buildFavoriteItems(entries), sourceLabel)
end

-- Warmer than the asset origin chips it sits next to, since it is an action and not a label.
local DUO_WORKSPOT_TAG_COLOR = 0xFF2C7DBF
local DUO_WORKSPOT_TAG_HOVERED = 0xFF3E93D8
local DUO_WORKSPOT_TAG_ACTIVE = 0xFF1F63A0

---The pair a synced-workspot entry spawns as a duo: its best documented partner and arrangement.
---Cached on the entry, the mapping behind it does not change within a session.
---@param entry table?
---@param spawnList table?
---@return { partner: table, arrangement: table }?
local function getEntryDuoWorkspot(entry, spawnList)
    if not entry or not spawnList or spawnList.modulePath ~= AI_SPOT_MODULE_PATH then
        return nil
    end

    if entry.duoWorkspot == nil then
        local partner = workspotSync.getPartners(getEntryAssetPath(entry, spawnList))[1]
        local arrangement = partner and partner.arrangements[1]

        entry.duoWorkspot = arrangement and { partner = partner, arrangement = arrangement } or false
    end

    return entry.duoWorkspot or nil
end

---Draws the clickable "Duo workspots" tag of a search-result row.
---@param partner table Entry from `workspotSync.getPartners`
---@return boolean clicked
local function drawDuoWorkspotTag(partner)
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6 * style.viewSize)
    ImGui.PushStyleColor(ImGuiCol.Button, DUO_WORKSPOT_TAG_COLOR)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, DUO_WORKSPOT_TAG_HOVERED)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, DUO_WORKSPOT_TAG_ACTIVE)

    local clicked = ImGui.Button(IconGlyphs.AccountMultiple .. "##duoWorkspot")

    ImGui.PopStyleColor(3)
    ImGui.PopStyleVar()

    style.tooltip("Duo workspots\nThis workspot is part of a synced animation, played together with : \n"
        .. utils.getFileName(partner.path)
        .. "\n\nClick to spawn both workspots."
        .. (workspotSync.hasOffset(partner.arrangements[1]) and ""
            or "\nNo offset is known for this pair, so the second spot lands on the first one and has to be placed by hand."))

    return clicked
end

---Spawns both halves of a synced workspot into a group of their own.
---@param entry table
---@param spawnList table
---@param duo { partner: table, arrangement: table }
local function spawnDuoWorkspot(entry, spawnList, duo)
    if groupLoadManager.isActive() then return end

    local assetPath = getEntryAssetPath(entry, spawnList)
    if rejectIncompatibleAsset(AI_SPOT_MODULE_PATH, assetPath) then return end

    sessionSnapshot.consume("spawned an asset")
    spawnUI.stopActiveAssetPreview()

    local pos, rot = spawnUI.getSpawnNewPosition()

    local group = require("modules/classes/editor/positionableGroup"):new(spawnUI.spawnedUI)
    group.name = utils.getFileName(assetPath)
    group:setParent(spawnUI.getSpawnTargetParent())

    local data = utils.deepcopy(entry.data)
    data.modulePath = AI_SPOT_MODULE_PATH
    applySpawnNewEntryDefaults(data)
    data.position = { x = pos.x, y = pos.y, z = pos.z, w = 0 }
    data.rotation = { roll = rot.roll, pitch = rot.pitch, yaw = rot.yaw }

    local first = require("modules/classes/editor/spawnableElement"):new(spawnUI.spawnedUI)
    first:load({
        name = utils.getFileName(entry.name),
        modulePath = first.modulePath,
        spawnable = data
    })
    first:setParent(group)

    -- The complementary spot places itself off this one, so it is spawned once the first half sits
    -- in the group. Both inserts are covered by the group's own undo entry below.
    local selfLeads = workspotSync.doesSelfLead(duo.partner)
    local success, status = first.spawnable:spawnComplementarySpot(duo.partner, duo.arrangement, selfLeads, {
        recordHistory = false
    })

    if not success then
        logger:warn(string.format("Could not complete the workspot duo of %s: %s", assetPath, status))
    end

    spawnUI.spawnedUI.unselectAll()
    group:setSelected(true)

    history.addAction(history.getInsert({ group }))
end

---Draws one interactive search-result row.
---Used by both the classic flat list and the hierarchy tree leaves.
---@param entry table
---@param activeSpawnList table
---@param xSpace number
---@param buttonTextOverride string?
---@param showFullPathTooltip boolean?
local function drawSpawnResultEntryRow(entry, activeSpawnList, xSpace, buttonTextOverride, showFullPathTooltip)
    local pushedButtonStyle = false
    local forcePathTooltip = showFullPathTooltip == true

    ImGui.PushID(entry.name)

    if entry.lastSpawned ~= nil then
        ImGui.PushStyleColor(ImGuiCol.Button, 0xff009933)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0xff009900)
        pushedButtonStyle = true
    end

    if entry.lastSpawned ~= nil and entry.lastSpawned.parent == nil then entry.lastSpawned = nil end

    if entry.lastSpawned ~= nil then
        if ImGui.Button("Despawn") then
            history.addAction(history.getRemove({ entry.lastSpawned }))
            entry.lastSpawned:remove()
            entry.lastSpawned = nil
        end
        ImGui.SameLine()
    end

    local buttonText = buttonTextOverride or entry.name
    if not buttonTextOverride and activeSpawnList.isPaths and settings.spawnUIOnlyNames then
        buttonText = entry.fileName or utils.getFileName(entry.name)
    end

    local originTagInfo = getEntryPathOriginTagInfo(entry, activeSpawnList)
    if originTagInfo and entry.lastSpawned == nil then
        drawPathOriginTagChip(originTagInfo)
        ImGui.SameLine()
    end

    local duo = getEntryDuoWorkspot(entry, activeSpawnList)
    if duo and entry.lastSpawned == nil then
        if drawDuoWorkspotTag(duo.partner) and not ImGui.IsMouseDragging(0, style.draggingThreshold) then
            spawnDuoWorkspot(entry, activeSpawnList, duo)
        end
        ImGui.SameLine()
    end

    local isFavorite = assetFavorites.isFavorite(activeSpawnList.modulePath, entry.name)
    local favoriteMarkerWidth = 0
    if isFavorite then
        local starWidth, _ = ImGui.CalcTextSize(IconGlyphs.StarBoxOutline)
        favoriteMarkerWidth = starWidth + ImGui.GetStyle().ItemSpacing.x
    end

    local secondaryIcon = getEntryRowIcon(entry, activeSpawnList)
    -- Reserved the same way the favorite star is: the row is one full-width button, so a trailing
    -- annotation has to be taken out of the button before it is drawn.
    local note = getEntryNote(entry, activeSpawnList)
    local noteWidth = 0
    if note then
        local textWidth, _ = ImGui.CalcTextSize(note.text)
        noteWidth = textWidth + ImGui.GetStyle().ItemSpacing.x
    end

    local buttonWidth = xSpace - ImGui.GetCursorPosX() - favoriteMarkerWidth - noteWidth
    local buttonLabel = formatSearchResultButtonText(buttonText, buttonWidth, secondaryIcon)

    local clicked = ImGui.Button(buttonLabel) and not ImGui.IsMouseDragging(0, style.draggingThreshold)

    if clicked then
        entry.lastSpawned = spawnUI.spawnNew(entry, resolveEntryClass(activeSpawnList, entry), false)
    else
        spawnUI.handleRowDrag(entry, function (dragged)
            dragged.lastSpawned = spawnUI.spawnNew(dragged, resolveEntryClass(activeSpawnList, dragged), false)
        end)
    end
    if ImGui.IsItemClicked(ImGuiMouseButton.Middle) then
        ImGui.SetClipboardText(entry.name)
    end
    if ImGui.IsItemHovered() and settings.assetPreviewEnabled[activeSpawnList.modulePath] then
        spawnUI.handleAssetPreviewHovered(entry, false)
    elseif spawnUI.hoveredEntry == entry and (spawnUI.previewInstance or spawnUI.previewTimer) then
        spawnUI.hoveredEntry = nil
        spawnUI.stopActiveAssetPreview()
    end

    if settings.spawnUIOnlyNames or forcePathTooltip then
        style.tooltip(entry.name)
    end

    if ImGui.BeginPopupContextItem("##spawnNewContext", ImGuiPopupFlags.MouseButtonRight) then
        if ImGui.MenuItem(style.resolveActionLabelNoIconOnly(IconGlyphs.Group, "Save as prefab", "spawnNewSavePrefab")) then
            spawnUI.savePrefabFromEntry(entry, resolveEntryClass(activeSpawnList, entry))
        end

        spawnUI.favoritesUI.drawContextMenuItem(
            activeSpawnList.modulePath,
            entry.name,
            entry.fileName or utils.getFileName(entry.name),
            entry.data,
            "SpawnNew"
        )

        ImGui.EndPopup()
    end

    if note then
        ImGui.SameLine()
        ImGui.AlignTextToFramePadding()
        style.styledText(note.text, note.warn and style.warnColor or style.mutedColor)
        style.tooltip(note.tooltip)
    end

    if isFavorite then
        drawFavoriteRowMarker(activeSpawnList.modulePath, entry.name)
    end

    if pushedButtonStyle then
        ImGui.PopStyleColor(2)
    end

    ImGui.PopID()
end

---Draws classic flat search results with clipper-based virtualization.
---@param activeSpawnList table
---@param xSpace number
local function drawFlatSpawnResults(activeSpawnList, xSpace)
    local clipper = ImGuiListClipper.new()
    clipper:Begin(#spawnUI.filteredList, -1)

    while (clipper:Step()) do
        for i = clipper.DisplayStart + 1, clipper.DisplayEnd, 1 do
            drawSpawnResultEntryRow(spawnUI.filteredList[i], activeSpawnList, xSpace)
        end
    end
end

---Returns the only child folder when a node contains exactly one folder and no assets.
---@param node table
---@return table?
local function getSingleFolderOnlyChild(node)
    if #node.entries ~= 0 then
        return nil
    end

    if #node.childOrder ~= 1 then
        return nil
    end

    return node.children[node.childOrder[1]]
end

---Expands the linear single-child folder chain below `node`.
---@param node table
local function expandSingleChildFolderChain(node)
    local current = node
    while current do
        local child = getSingleFolderOnlyChild(current)
        if not child then
            break
        end

        spawnUI.hierarchyOpenStateByKey[child.key] = true
        current = child
    end
end

---Recursively assigns open-state for every folder node under `node`.
---@param node table
---@param isOpen boolean
local function setHierarchyNodeOpenStateRecursive(node, isOpen)
    for _, childKey in ipairs(node.childOrder) do
        local child = node.children[childKey]
        spawnUI.hierarchyOpenStateByKey[child.key] = isOpen
        setHierarchyNodeOpenStateRecursive(child, isOpen)
    end
end

---Draws expand/collapse icon buttons at the top of hierarchy search results.
---@param hierarchyRoot table
local function drawHierarchyResultControls(hierarchyRoot)
    style.drawExpandCollapseButtons(
        "spawnHierarchy",
        function ()
            setHierarchyNodeOpenStateRecursive(hierarchyRoot, true)
            spawnUI.invalidateHierarchyRows()
        end,
        function ()
            setHierarchyNodeOpenStateRecursive(hierarchyRoot, false)
            spawnUI.invalidateHierarchyRows()
        end,
        {
            disabled = #hierarchyRoot.childOrder == 0,
            expandTooltip = "Expand all folders",
            collapseTooltip = "Collapse all folders"
        }
    )

    ImGui.Separator()
end

--- Hierarchy tree virtualization ---------------------------------------------
--
-- Drawing the tree by recursing into open nodes costs one full row emit per
-- visible-or-not entry, every frame. The path lists reach ~150k entries, so
-- "expand all" turned into millions of ImGui calls per frame and stalled the
-- render thread. Instead the open tree is flattened once into a linear row
-- list (mirroring how `spawnedUI` caches `visiblePaths`) and drawn through an
-- `ImGuiListClipper`, so cost tracks the window height, not the list size.
--
-- Rows carry their own indent depth because `TreePush`/`TreePop` nesting
-- cannot survive rows the clipper skips. Every row is one frame-height line,
-- which the clipper needs in order to seek without measuring.

---@class hierarchyRow
---@field folder table? Set on folder rows.
---@field open boolean? Folder open state, only meaningful with `folder`.
---@field leaf table? Set on entry rows.
---@field depth number Indent levels, already resolved for the flat list.

---Appends the visible rows of `node` to `rows`, descending only into open folders.
---@param node table
---@param depth number
---@param rows hierarchyRow[]
local function appendHierarchyRows(node, depth, rows)
    for _, childKey in ipairs(node.childOrder) do
        local child = node.children[childKey]
        local isOpen = spawnUI.hierarchyOpenStateByKey[child.key] == true

        rows[#rows + 1] = { folder = child, open = isOpen, depth = depth }

        if isOpen then
            appendHierarchyRows(child, depth + 1, rows)
        end
    end

    for _, leaf in ipairs(node.entries) do
        rows[#rows + 1] = { leaf = leaf, depth = depth }
    end
end

---Resolves the cached flat row list, rebuilding it when stale.
---@param hierarchyRoot table
---@return hierarchyRow[]
local function resolveHierarchyRows(hierarchyRoot)
    if spawnUI.hierarchyRows and spawnUI.hierarchyRowsRoot == hierarchyRoot then
        return spawnUI.hierarchyRows
    end

    local rows = {}
    appendHierarchyRows(hierarchyRoot, 0, rows)

    spawnUI.hierarchyRows = rows
    spawnUI.hierarchyRowsRoot = hierarchyRoot

    return rows
end

---Collects the entries of one hierarchy folder and of every folder below it.
---The tree only ever holds filtered results, so a narrowed search narrows this too.
---@param node table
---@param collected table[]?
---@return table[] entries
local function collectHierarchyNodeEntries(node, collected)
    collected = collected or {}

    for _, leaf in ipairs(node.entries) do
        table.insert(collected, leaf.entry)
    end

    for _, childKey in ipairs(node.childOrder) do
        collectHierarchyNodeEntries(node.children[childKey], collected)
    end

    return collected
end

---Draws the context menu of one folder row of the hierarchy tree.
---@param node table
local function drawHierarchyFolderContextMenu(node)
    -- Folder rows are drawn flat, without a per-row ID scope, so the popup ID has to
    -- carry the folder key itself. A shared ID would reopen on every folder at once.
    local popupId = "##spawnResultFolderContext:" .. node.key

    if not ImGui.BeginPopupContextItem(popupId, ImGuiPopupFlags.MouseButtonRight) then
        return
    end

    local label, hiddenText = style.resolveActionLabelNoIconOnly(
        IconGlyphs.StarPlusOutline,
        "Add content to favorites",
        "spawnNewFolderFavorite",
        nil,
        true
    )

    local clicked = ImGui.MenuItem(label)
    style.tooltipActionLabel(hiddenText, "Favorite every asset of this folder and its sub folders.\nOnly the results matching the current search are added.")

    if clicked then
        openBulkFavorite(collectHierarchyNodeEntries(node), node.label)
    end

    ImGui.EndPopup()
end

---Draws one folder row, applying and reading back its open state.
---@param node table
---@param isOpen boolean
local function drawHierarchyFolderRow(node, isOpen)
    -- An unframed tree node is only a text line tall, while entry rows are a full
    -- frame. Aligning to frame padding makes both kinds exactly `GetFrameHeight()`,
    -- which the clipper relies on to seek by a fixed row pitch.
    ImGui.AlignTextToFramePadding()

    ImGui.SetNextItemOpen(isOpen, ImGuiCond.Always)

    local nodeLabel = string.format("%s##spawnResultHierarchyNode:%s", node.label, node.key)
    local open = ImGui.TreeNodeEx(nodeLabel, ImGuiTreeNodeFlags.SpanFullWidth)
    local toggled = ImGui.IsItemToggledOpen()

    -- Children are separate flat rows, so the tree scope is popped right away.
    -- Row IDs are globally unique (full path keys), so nothing depends on it.
    if open then
        ImGui.TreePop()
    end

    -- Drawn outside the tree scope, so the popup ID does not depend on the open state.
    drawHierarchyFolderContextMenu(node)

    if not toggled then
        return
    end

    spawnUI.hierarchyOpenStateByKey[node.key] = open
    if open then
        expandSingleChildFolderChain(node)
    end

    spawnUI.invalidateHierarchyRows()
end

---Draws one flattened hierarchy row at its cached indent depth.
---@param row hierarchyRow
---@param activeSpawnList table
---@param xSpace number
---@param indentSpacing number
local function drawHierarchyRow(row, activeSpawnList, xSpace, indentSpacing)
    local indent = row.depth * indentSpacing
    if indent > 0 then
        ImGui.Indent(indent)
    end

    if row.folder then
        drawHierarchyFolderRow(row.folder, row.open)
    else
        drawSpawnResultEntryRow(row.leaf.entry, activeSpawnList, xSpace, row.leaf.label, true)
    end

    if indent > 0 then
        ImGui.Unindent(indent)
    end
end

---Resolves the cached hierarchy tree root, rebuilding it when stale.
---@return table?
local function resolveHierarchyRoot()
    if not spawnUI.filteredHierarchyTree then
        spawnUI.rebuildHierarchyTree()
    end

    return spawnUI.filteredHierarchyTree
end

---Draws hierarchy-based path result nodes from the cached `filteredHierarchyTree`.
---The expand/collapse controls bar is drawn separately, outside the scroll region
---(see `drawAll`), so it stays visible while the tree is scrolled.
---@param activeSpawnList table
---@param xSpace number
---@param hierarchyRoot table?
local function drawHierarchySpawnResults(activeSpawnList, xSpace, hierarchyRoot)
    if not hierarchyRoot then
        drawFlatSpawnResults(activeSpawnList, xSpace)
        return
    end

    if #spawnUI.filteredList == 0 then
        return
    end

    local rows = resolveHierarchyRows(hierarchyRoot)
    if #rows == 0 then
        return
    end

    local imguiStyle = ImGui.GetStyle()
    local indentSpacing = imguiStyle.IndentSpacing
    if type(indentSpacing) ~= "number" or indentSpacing <= 0 then
        indentSpacing = 21 * style.viewSize
    end

    -- Folder and entry rows are both a single framed line, so the pitch is uniform.
    local rowHeight = ImGui.GetFrameHeight() + imguiStyle.ItemSpacing.y

    -- Toggling a folder inside the loop only drops the cache; `rows` stays valid
    -- for the rest of this frame, which keeps the clipper's item count stable.
    local clipper = ImGuiListClipper.new()
    clipper:Begin(#rows, rowHeight)

    while (clipper:Step()) do
        for i = clipper.DisplayStart + 1, clipper.DisplayEnd, 1 do
            drawHierarchyRow(rows[i], activeSpawnList, xSpace, indentSpacing)
        end
    end
end

---Draws the fallback action when no path entries match the search text.
function spawnUI.drawNoMatch()
    local activeSpawnList = spawnUI.getActiveSpawnList()
    if #spawnUI.filteredList ~= 0 or not activeSpawnList.isPaths then return end

    local manualPath = utils.trimString(spawnUI.filter or "")

    style.mutedText("No match found...")
    style.styledTextWrapped(("Spawn \"%s\" anyways?"):format(spawnUI.filter), style.mutedColor)

    -- Typing a path by hand is the one way into Spawn New that no list vouches for, so the
    -- verdict is shown up front rather than only after the click.
    local check = assetValidation.check(activeSpawnList.modulePath, manualPath)
    local label = getSpawnableLabel(activeSpawnList.modulePath)
    local blocked = check.severity == "error" and settings.validateAssetTypes ~= false

    if not check.ok then
        local suggestion = spawnUI.getVariantSuggestion(check)
        local detail = assetValidation.getDetail(check, label)

        style.styledText(IconGlyphs.AlertOutline, blocked and 0xFF0000FF or style.warnColor)
        ImGui.SameLine()
        style.styledTextWrapped(assetValidation.getSummary(check, label), blocked and 0xFF0000FF or style.warnColor)
        style.tooltip(suggestion ~= "" and (detail .. "\n\n" .. suggestion) or detail)
    end

    style.pushGreyedOut(blocked)
    if ImGui.Button("Spawn") then
        if manualPath == "" then
            ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Warning, 2500, "Cannot spawn: path is empty"))
            logger:warn("Spawn attempt ignored: empty manual path in Spawn New")
        else
            logger:info(string.format("Manual spawn attempt from Spawn New: \"%s\" (unverified path)", manualPath))

            -- This path matched no list entry, so there is nothing to read a node type off for
            -- a variant hosting several classes: the variant's own class is the only choice.
            -- `spawnNew` re-runs the check above and reports it, so a blocked path stops there.
            spawnUI.spawnNew({
                data = { spawnData = manualPath }, lastSpawned = nil, name = manualPath, fileName = manualPath
            }, activeSpawnList.class, false)
        end
    end
    if blocked then
        style.tooltip(assetValidation.getDetail(check, label))
    end
    style.popGreyedOut(blocked)
end

---Draws the "Strip paths" toggle, persisting and re-filtering when it changes.
---Shared by the options popin and the quick spawn popup, which label it differently.
---@param labelX number? Cursor X the checkbox is aligned to, for the popup's label column.
local function drawStripPathsCheckbox(labelX)
    if labelX then
        ImGui.Text("Strip paths")
        ImGui.SameLine()
        ImGui.SetCursorPosX(labelX)
    else
        style.mutedText("Strip paths")
        ImGui.SameLine()
    end

    local changed
    settings.spawnUIOnlyNames, changed = ImGui.Checkbox("##strip", settings.spawnUIOnlyNames)
    style.tooltip("Only show the name of the file, without the full path")

    if changed then
        settings.save()
        -- The toggle drives both the displayed label and the list ordering.
        spawnUI.refresh()
    end
end

---Draws Spawn New options for display mode, preview mode, and spawn placement.
function spawnUI.drawOptions()
    local activeList = spawnUI.getActiveSpawnList()
    if activeList.isPaths then
        drawStripPathsCheckbox()
    end

    if activeList.assetPreviewType ~= "none" then
        style.mutedText("Asset Preview")
        ImGui.SameLine()
        local assetPreviewChanged
        settings.assetPreviewEnabled[activeList.modulePath], assetPreviewChanged = ImGui.Checkbox("##assetPreview", settings.assetPreviewEnabled[activeList.modulePath])
        if assetPreviewChanged then
            settings.save()
        end
        style.tooltip("Preview the asset when hovered. Is Experimental.")
        if activeList.assetPreviewType == "backdrop" then
            ImGui.SameLine()
            style.mutedText(IconGlyphs.Checkerboard)
            style.tooltip("Asset gets previewed with a backdrop")
        else
            ImGui.SameLine()
            style.mutedText(IconGlyphs.AxisArrowInfo)
            style.tooltip("Asset gets previewed at the same position it would spawn in")
        end

        ImGui.SameLine()
        style.mutedText(IconGlyphs.InformationOutline)
        style.tooltip(previewControls.getBindingsTooltip())
    end

    spawnUI.drawSpawnPosition()
end

local SPAWN_NEW_OPTIONS_POPIN_ID = "##spawnNewOptionsPopin"

---Describes the current results in the bulk favorite popup, so it is clear what
---the button is about to add.
---@return string
local function getSearchResultsSourceLabel()
    local variantLabel = modulePathToVariantLabel[spawnUI.getActiveSpawnList().modulePath] or ""

    return string.format("%s (search: %s)", variantLabel, spawnUI.filter)
end

---Draws the extra controls of the search row: bulk favorite and tree toggle.
---@param activeSpawnList table
local function drawSpawnNewSearchRowControls(activeSpawnList)
    -- Only about the current results, so it is only offered while a search narrows them down.
    -- Sits right after the search row's info icon.
    if spawnUI.filter ~= "" then
        ImGui.SameLine()

        -- Dimmed rather than disabled, so the tooltip still explains what the button does.
        local hasResults = #spawnUI.filteredList > 0

        style.pushButtonNoBG(true)
        style.pushStyleColor(not hasResults, ImGuiCol.Text, style.mutedColor)
        if ImGui.Button(IconGlyphs.StarPlusOutline .. "##spawnNewFavoriteResults") and hasResults then
            -- Never bulk-add off a list that a debounced edit has not been applied to yet.
            spawnUI.flushPendingFilterUpdate()
            openBulkFavorite(spawnUI.filteredList, getSearchResultsSourceLabel())
        end
        style.popStyleColor(not hasResults)
        style.pushButtonNoBG(false)
        style.tooltip(hasResults
            and "Add every result to favorites, under the same tag"
            or "No result to add to favorites")
    end

    if not activeSpawnList.isPaths then
        return
    end

    style.sameLineWindowRight(25)

    local hierarchyTreeChanged
    settings.spawnUIHierarchyTree, hierarchyTreeChanged = style.toggleButton(
        IconGlyphs.FileTreeOutline .. "##hierarchyTreeToggle",
        settings.spawnUIHierarchyTree
    )
    if hierarchyTreeChanged then
        settings.save()
    end
    style.tooltip("Toggle hierarchy tree results")
end

---Draws a right-aligned options icon button plus its popin, on the current line.
---Shared by every Spawn New sub-tab so the button always sits next to the target group.
---@param buttonId string Unique `##` suffix of the button.
---@param popupId string Unique popin ID.
---@param drawContent fun() Renders the popin body.
---@param tooltip string?
function spawnUI.drawOptionsButton(buttonId, popupId, drawContent, tooltip)
    style.sameLineWindowRight(25)

    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.CogOutline .. buttonId) then
        ImGui.OpenPopup(popupId)
    end
    style.pushButtonNoBG(false)
    style.tooltip(tooltip or "Options")

    if ImGui.BeginPopup(popupId) then
        ImGui.PushID(popupId)
        drawContent()
        ImGui.PopID()
        ImGui.EndPopup()
    end
end

---Draws the target group selector used for new spawns.
function spawnUI.drawTargetGroupSelector()
    if spawnUI.spawnedUI and spawnUI.spawnedUI.ensureCache then
        spawnUI.spawnedUI.ensureCache()
    end

    local groups = { "Root" }
	for _, group in ipairs(spawnUI.spawnedUI.containerPaths) do
		table.insert(groups, group.path)
	end

    if not spawnUI.selectedGroup or spawnUI.selectedGroup >= #groups then
        spawnUI.selectedGroup = 0
    end

    ImGui.BeginGroup()
    style.drawIconLabelRow(IconGlyphs.PlusBoxOutline, "Target group")
    --style.mutedText(IconGlyphs.PlusBoxOutline .. " Target group")
    ImGui.SameLine()
	ImGui.PushItemWidth(200 * style.viewSize)
	spawnUI.selectedGroup = ImGui.Combo("##newSpawnGroup", spawnUI.selectedGroup, groups, #groups)
    style.comboValueTooltip(spawnUI.selectedGroup, groups, "Automatically place any newly spawned object into the selected group.\nPress CTRL-N in \"Spawned\" tab to set or unset this selector to the currently selected group.")
    ImGui.EndGroup()
	ImGui.PopItemWidth()
end

---Returns the parent selected for new spawns, falling back to root.
---@return element
function spawnUI.getSpawnTargetParent()
    if spawnUI.spawnedUI and spawnUI.spawnedUI.ensureCache then
        spawnUI.spawnedUI.ensureCache()
    end

    local selectedGroup = spawnUI.selectedGroup or 0
    local parent = spawnUI.spawnedUI.root
    if selectedGroup ~= 0 and spawnUI.spawnedUI.containerPaths[selectedGroup] then
        parent = spawnUI.spawnedUI.containerPaths[selectedGroup].ref
    end

    return parent
end

---Draws the full "All" tab, including filters, list, and quick actions.
function spawnUI.drawAll()
    -- Before anything reads `filteredList`, so the whole frame sees one consistent list.
    tickPendingFilterUpdate()

    spawnUI.drawTargetGroupSelector()
    spawnUI.drawOptionsButton("##spawnNewOptionsButton", SPAWN_NEW_OPTIONS_POPIN_ID, spawnUI.drawOptions)

    style.spacedSeparator()

	local typeChanged
    style.fieldLabel("Object type")
	spawnUI.selectedType, typeChanged = style.trackedCombo(nil, "##objectType", spawnUI.selectedType, typeNames, 100, {
        maxPopupHeight = style.getPopupMaxHeight()
    })
    if typeChanged then
        spawnUI.updateCategory()
    end

    ImGui.SameLine()
    style.mutedText(IconGlyphs.ChevronRight)
    ImGui.SameLine()

	local variantChanged
    style.fieldLabel("variant")
	spawnUI.selectedVariant, variantChanged = style.trackedCombo(nil, "##objectVariant", spawnUI.selectedVariant, variantNames, 140, {
        maxPopupHeight = style.getPopupMaxHeight(),
        separatorsBefore = variantSeparatorsByType[typeNames[spawnUI.selectedType + 1]],
        tooltipFn = function (currentValue)
            style.spawnableInfo(spawnUI.getActiveSpawnList().info, currentValue)
        end
    })
    if variantChanged then
        spawnUI.updateVariant()
    end

    if variantNames[spawnUI.selectedVariant + 1] == "Template (AMM)" then
        ImGui.SameLine()

        style.pushGreyedOut(not AMM)
        if not amm.importing then
            if ImGui.Button("Generate AMM Props") and AMM then
                amm.generateProps(spawnUI, AMM, spawnUI.spawner)
            end
            style.tooltip("Generate files for spawning, from current list of AMM props")
        else
            ImGui.ProgressBar(amm.progress / amm.total, 200, 30, string.format("%.2f%%", (amm.progress / amm.total) * 100))
        end

        style.popGreyedOut(not AMM)
    end

    style.spacedSeparator()

    local filterChanged, filterCleared
    spawnUI.filter, filterChanged, filterCleared = style.drawSearchFilterRow("##Filter", spawnUI.filter, { maxLength = 500 })
    if filterCleared then
        -- A one-off click, and the empty filter takes the cheap path, so keep it instant.
        saveSpawnUIFilterIfChanged()
        spawnUI.updateFilter()
    elseif filterChanged then
        saveSpawnUIFilterIfChanged()
        spawnUI.requestFilterUpdate()
    end

    local activeSpawnList = spawnUI.getActiveSpawnList()
    drawSpawnNewSearchRowControls(activeSpawnList)

    if drawEntryFilters() then
        spawnUI.updateFilter()
    end

    style.spacedSeparator()

    local useHierarchyTree = settings.spawnUIHierarchyTree and activeSpawnList.isPaths
    local hierarchyRoot = useHierarchyTree and resolveHierarchyRoot() or nil

    -- Draw the expand/collapse bar before the scroll region so it stays visible while scrolling the tree.
    if useHierarchyTree and hierarchyRoot and #spawnUI.filteredList > 0 then
        drawHierarchyResultControls(hierarchyRoot)
    end

    ImGui.BeginChild("list")

    local xSpace, _ = ImGui.GetItemRectSize() - 2 * ImGui.GetStyle().WindowPadding.x - (ImGui.GetScrollMaxY() > 0 and ImGui.GetStyle().ScrollbarSize or 0)

    spawnUI.drawNoMatch()

    if useHierarchyTree then
        drawHierarchySpawnResults(activeSpawnList, xSpace, hierarchyRoot)
    else
        drawFlatSpawnResults(activeSpawnList, xSpace)
    end

    if #spawnUI.filteredList == 0 then
        spawnUI.stopActiveAssetPreview()
    end

    ImGui.EndChild()
end

---Draws the Spawn UI tab bar and delegates per-tab content.
function spawnUI.draw()
    spawnUI.drawDragWindow()
    groupLoadManager.drawProgress(style)

    local tabs = {
        { icon = IconGlyphs.TextBoxSearchOutline, label = "Asset Browser", id = "spawnUITabAll", draw = spawnUI.drawAll },
        { icon = IconGlyphs.Group, label = "Prefabs", id = "spawnUITabPrefabs", draw = function () spawnUI.prefabsUI.draw() end },
        { icon = IconGlyphs.StarBoxMultipleOutline, label = "Favorites", id = "spawnUITabAssetFavorites", draw = function () spawnUI.favoritesUI.draw() end }
    }

    if ImGui.BeginTabBar("##spawnUITabbar", ImGuiTabItemFlags.NoTooltip) then
        for _, tab in ipairs(tabs) do
            local label, hiddenText = style.resolveActionLabel(tab.icon, tab.label, tab.id, nil, true)
            local open = ImGui.BeginTabItem(label)

            -- The tooltip has to be requested while the tab header is the last item,
            -- which is true in both branches.
            style.tooltipActionLabel(hiddenText)

            if open then
                tab.draw()
                ImGui.EndTabItem()
            end
        end

        ImGui.EndTabBar()
    end
end

---Handles Spawn UI being hidden by clearing active preview state.
function spawnUI.hidden()
    if not spawnUI.previewInstance and not spawnUI.previewTimer and not spawnUI.assetPreviewActive and not prefabPreview.isActive() then return end

    spawnUI.hoveredEntry = nil
    spawnUI.stopActiveAssetPreview()
end

---Computes default spawn transform using current settings and selection.
---@return Vector4
---@return EulerAngles
---@return boolean facesCamera The rotation faces the camera rather than copying the selection.
function spawnUI.getSpawnNewPosition()
    local pos = editor.getCameraPosition()
    local cameraRotation = editor.getCameraRotation()
    local forward = editor.getCameraForward()

    if not pos or not cameraRotation or not forward then
        return Vector4.new(0, 0, 0, 0), EulerAngles.new(0, 0, 0), false
    end

    local rot = EulerAngles.new(0, 0, cameraRotation.yaw + 180)
    local facesCamera = true

    pos = utils.addVector(pos, utils.multVector(forward, settings.spawnDist))

    if editor.isCameraAttachedToPlayer() then
        local player = Game.GetPlayer()
        local playerPosition = player and player:GetWorldPosition() or nil
        if playerPosition then
            pos.z = playerPosition.z
        end
    end

    if settings.spawnPos == 1 then
        if #spawnUI.spawnedUI.selectedPaths == 1 and utils.isA(spawnUI.spawnedUI.selectedPaths[1].ref, "spawnableElement") then
            pos = spawnUI.spawnedUI.selectedPaths[1].ref:getPosition()
            rot = spawnUI.spawnedUI.selectedPaths[1].ref:getRotation()
            facesCamera = false
        elseif #spawnUI.spawnedUI.selectedPaths > 1 then
            pos = spawnUI.spawnedUI.multiSelectGroup:getPosition()
            rot = spawnUI.spawnedUI.multiSelectGroup:getDirection("forward"):ToRotation()
            facesCamera = false
        end
    end

    return pos, rot, facesCamera
end

---@param data table?
local function applySpawnNewVisualizerDefault(data)
    if type(data) ~= "table" then
        return
    end

    local modulePath = data.modulePath
    if not modulePath or spawnNewVisualizerModuleSet[modulePath] ~= true then
        return
    end

    local defaults = settings.spawnNewVisualizerEnabledByModule
    if type(defaults) ~= "table" then
        return
    end

    local defaultPreviewed = defaults[modulePath]
    if type(defaultPreviewed) == "boolean" then
        data.previewed = defaultPreviewed
    end
end

---@param data table?
local function applySpawnNewLightDefaults(data)
    if type(data) ~= "table" or data.modulePath ~= STATIC_LIGHT_MODULE_PATH then
        return
    end

    local lightType = tonumber(data.lightType)
    if lightType ~= nil and STATIC_LIGHT_TYPES[lightType] ~= true then
        return
    end

    data.color = colorUtil.normalizeRGB(settings.defaultLightColor, data.color or DEFAULT_STATIC_LIGHT_COLOR)
end

---@param data table?
applySpawnNewEntryDefaults = function(data)
    applySpawnNewVisualizerDefault(data)
    applySpawnNewLightDefaults(data)
end

---Spawns a new entry (or favorite/group) and records history metadata.
---@param entry table|favorite
---@param class table
---@param isFavorite boolean
---@param options table?
---@return any
function spawnUI.spawnNew(entry, class, isFavorite, options)
    if groupLoadManager.isActive() then
        return nil
    end

    -- Whether the asset can be spawned by this class at all decides everything below, so it is
    -- settled first: a refused spawn must not become what Repeat Last Spawn retries. A favorited
    -- group is not checked here, each of its elements is checked as it loads.
    local targetModulePath, targetAssetPath
    if isFavorite then
        local spawnableData = type(entry.data) == "table" and entry.data.spawnable or nil
        if type(spawnableData) == "table" then
            targetModulePath = spawnableData.modulePath
            targetAssetPath = spawnableData.spawnData
        end
    else
        targetModulePath = class:new().modulePath
        targetAssetPath = type(entry.data) == "table" and entry.data.spawnData or nil
    end

    if rejectIncompatibleAsset(targetModulePath, targetAssetPath) then
        return nil
    end

    options = options or {}
    local loadHidden = isFavorite and options.loadHidden == true

    -- Spawning is the clearest signal that this is a fresh session, so the recovery banner goes away.
    sessionSnapshot.consume("spawned an asset")

    spawnUI.lastSpawnedClass = class
    spawnUI.lastSpawnedEntry = entry
    spawnUI.lastSpawnedIsFavorite = isFavorite
    spawnUI.lastSpawnedOptions = {
        loadHidden = loadHidden
    }

    -- Cleanup preview
    spawnUI.stopActiveAssetPreview()

    local parent = spawnUI.getSpawnTargetParent()

    local new = require("modules/classes/editor/spawnableElement"):new(spawnUI.spawnedUI)
    local pos, rot, facesCamera = spawnUI.getSpawnNewPosition()

    local snap = spawnUI.popupSpawnHit and spawnUI.popupSpawnHit.hit
    if snap then
        pos = spawnUI.popupSpawnHit.result.position
        local target = spawnUI.popupSpawnHit.result.normal
        local current = Vector4.new(0, 0, 1, 0)
        local axis = current:Cross(target)
        local angle = Vector4.GetAngleBetween(current, target)

        if math.abs(angle) < 0.1 then
            local cameraRotation = editor.getCameraRotation()
            rot = EulerAngles.new(0, 0, cameraRotation and cameraRotation.yaw + 180 or 0)
            facesCamera = cameraRotation ~= nil
        else
            rot = Quaternion.SetAxisAngle(axis:Normalize(), math.rad(angle)):ToEulerAngles()
            facesCamera = false
        end
    end

    -- Path-like assets run away from the camera instead of facing it.
    if facesCamera and not isFavorite and class and class.spawnAlongView then
        rot = EulerAngles.new(rot.roll, rot.pitch, rot.yaw + 180)
    end

    local favoriteIsGroup = isFavorite and utils.isSerializedGroup(entry.data)
    local data = favoriteIsGroup and entry.data or utils.deepcopy(entry.data)

    if favoriteIsGroup then
        groupLoadManager.start({
            spawner = spawnUI.spawner,
            data = data,
            targetParent = parent,
            clearLocks = true,
            captureBaseTransform = "prefab",
            selectLoaded = not loadHidden,
            loadHidden = loadHidden,
            initialPosition = pos,
            initialRotation = rot
        })

        return nil
    end

    if isFavorite then
        -- Favorites should always load unlocked so initial placement is never blocked.
        utils.clearLockStateRecursive(data)
    end

    if not isFavorite then
        data.modulePath = targetModulePath
        applySpawnNewEntryDefaults(data)
        data.position = { x = pos.x, y = pos.y, z = pos.z, w = 0 }
        data.rotation = { roll = rot.roll, pitch = rot.pitch, yaw = rot.yaw }
    end

    if isFavorite then
        ---@type positionable
        new = require(entry.data.modulePath):new(spawnUI.spawnedUI)
        data.visible = false

        new:load(data, true) -- Load without spawning
        -- Captured before placement, so the reset actions restore what the prefab was saved with.
        new:captureBaseTransform("prefab")
        new:setPosition(pos)
        new:setRotation(rot)
        new:setSilent(false)
        if not loadHidden then
            new:setVisible(true, true) -- Now spawn, but dont record in history
        end
    else
        new:load({
            name = entry.fileName or utils.getFileName(entry.name),
            modulePath = new.modulePath,
            spawnable = data
        })
    end

    if utils.isA(new, "spawnableElement") and new.spawnable.bBoxLoaded == nil and snap then -- Bbox is immediately available
        local adjustedPos = utils.addVector(spawnUI.popupSpawnHit.result.position, utils.multVector(spawnUI.popupSpawnHit.result.normal, math.abs(new.spawnable:getBBox().min.z)))
        local spawnLifetimeToken = new.spawnable.getSpawnLifetimeToken and new.spawnable:getSpawnLifetimeToken() or nil
        Cron.After(0.1, function ()
            if spawnLifetimeToken and (not new.spawnable or not new.spawnable.isSpawnLifetimeTokenCurrent or not new.spawnable:isSpawnLifetimeTokenCurrent(spawnLifetimeToken)) then
                logger:warn(string.format("Skipped stale spawn adjust callback for \"%s\"", tostring(new.name or "unknown")))
                return
            end
            if new.parent == nil then return end
            new:setPosition(adjustedPos)
        end, {})
    end

    new:setParent(parent)
    new.selected = true
    spawnUI.spawnedUI.unselectAll()

    if utils.isA(new, "spawnableElement") and snap and new.spawnable.bBoxLoaded ~= nil then
        local position = spawnUI.popupSpawnHit.result.position
        local normal = spawnUI.popupSpawnHit.result.normal
        local spawnLifetimeToken = new.spawnable.getSpawnLifetimeToken and new.spawnable:getSpawnLifetimeToken() or nil

        Cron.Every(0.05, function (timer)
            if spawnLifetimeToken and (not new.spawnable or not new.spawnable.isSpawnLifetimeTokenCurrent or not new.spawnable:isSpawnLifetimeTokenCurrent(spawnLifetimeToken)) then
                logger:warn(string.format("Halted stale spawn wait callback for \"%s\"", tostring(new.name or "unknown")))
                timer:Halt()
                return
            end
            if new.parent == nil then
                timer:Halt()
                return
            end
            if new.spawnable.bBoxLoaded and new.spawnable:getEntity() then
                Cron.After(0.1, function ()
                    if spawnLifetimeToken and (not new.spawnable or not new.spawnable.isSpawnLifetimeTokenCurrent or not new.spawnable:isSpawnLifetimeTokenCurrent(spawnLifetimeToken)) then
                        logger:warn(string.format("Skipped stale post-BBOX spawn callback for \"%s\"", tostring(new.name or "unknown")))
                        return
                    end
                    if new.parent == nil then return end
                    local adjustedPos = utils.addVector(position, utils.multVector(normal, math.abs(new.spawnable:getBBox().min.z)))
                    new:setPosition(adjustedPos)
                    history.addAction(history.getInsert({ new }))
                end)

                timer:Halt()
            end
        end, {})
    else
        history.addAction(history.getInsert({ new }))
    end

    return new
end

---Repeats the last successful spawn operation using cached context.
function spawnUI.repeatLastSpawn()
    if not spawnUI.lastSpawnedClass or not spawnUI.lastSpawnedEntry then return end

    spawnUI.popupSpawnHit = editor.getCursorSceneHit()

    spawnUI.spawnNew(spawnUI.lastSpawnedEntry, spawnUI.lastSpawnedClass, spawnUI.lastSpawnedIsFavorite, spawnUI.lastSpawnedOptions)
    spawnUI.spawnedUI.cachePaths()
    spawnUI.popupSpawnHit = nil
end

---Builds popup search results for a specific type/variant.
---@param typeName string
---@param variantName string
function spawnUI.loadPopupData(typeName, variantName)
    local data = {}

    for _, entry in pairs(spawnData[typeName][variantName].data) do
        if utils.matchSearch(entry.name, spawnUI.popupFilter) then
            table.insert(data, entry)
        end
    end

    spawnUI.popupData = data
end

---Draws one popup variant submenu and handles spawn selection clicks.
---@param typeName string
---@param variantName string
function spawnUI.drawPopupVariant(typeName, variantName)
    local _, screenHeight = GetDisplayResolution()
    local popupSpawnList = spawnData[typeName][variantName]

    local focusFilter = spawnUI.currentPopupVariant ~= variantName
    if focusFilter then
        spawnUI.loadPopupData(typeName, variantName)
        spawnUI.currentPopupVariant = variantName
    end

    if style.drawSearchClearButton('##FilterClear', spawnUI.popupFilter ~= '') then
        spawnUI.popupFilter = ''
        style.clearSearchInput('##Filter', true)
        spawnUI.loadPopupData(typeName, variantName)
    end
    local xButton, _ = ImGui.GetItemRectSize()

    -- Focus is requested here rather than when the popup opens, so it lands on the input instead of
    -- the glyph button now drawn in front of it.
    if focusFilter then
        ImGui.SetKeyboardFocusHere()
    end

    local popupFilterChanged, popupFilterCleared
    spawnUI.popupFilter, popupFilterChanged, popupFilterCleared = style.searchInputTextWithHint('##Filter', 'Search...', spawnUI.popupFilter, 75)
    local xSpace, _ = ImGui.GetItemRectSize()
    xSpace = xSpace + xButton + ImGui.GetStyle().ItemSpacing.x
    if popupFilterChanged or popupFilterCleared then
        spawnUI.loadPopupData(typeName, variantName)
    end

    if spawnUI.popupFilter ~= "" or #popupSpawnList.data < 100 then
        local y = #spawnUI.popupData * ImGui.GetFrameHeightWithSpacing()

        if ImGui.BeginChild("##list", xSpace, math.max(math.min(y, screenHeight / 2), 1)) then
            local clipper = ImGuiListClipper.new()
            clipper:Begin(#spawnUI.popupData, -1)

            while (clipper:Step()) do
                for i = clipper.DisplayStart + 1, clipper.DisplayEnd, 1 do
                    ImGui.PushID(spawnUI.popupData[i].name)
                    local secondaryIcon = getEntryRowIcon(spawnUI.popupData[i], popupSpawnList)
                    local popupButtonText = formatSearchResultButtonText(
                        spawnUI.popupData[i].name,
                        xSpace - ImGui.GetStyle().ItemSpacing.x * 3,
                        secondaryIcon
                    )

                    if ImGui.Button(popupButtonText) then
                        if not settings.spawnAtCursor then
                            spawnUI.popupSpawnHit = nil
                        elseif not spawnUI.popupSpawnHit then
                            spawnUI.popupSpawnHit = editor.getCursorSceneHit()
                        end

                        spawnUI.popupData[i].lastSpawned = spawnUI.spawnNew(spawnUI.popupData[i], resolveEntryClass(popupSpawnList, spawnUI.popupData[i]), false)
                        ImGui.CloseCurrentPopup()
                    end
                    if ImGui.IsItemClicked(ImGuiMouseButton.Middle) then
                        ImGui.SetClipboardText(spawnUI.popupData[i].name)
                    end

                    ImGui.PopID()
                end
            end
            ImGui.EndChild()
        end
    end
end

---Draws and manages the quick spawn popup.
function spawnUI.drawPopup()
    local x, y = ImGui.GetMousePos()
    ImGui.SetNextWindowPos(x + 10 * style.viewSize, y - 4 * ImGui.GetFrameHeight(), ImGuiCond.Appearing)

    if ImGui.BeginPopup("##spawnNew") then
        local x, _ = ImGui.CalcTextSize("Reset search") + ImGui.GetStyle().ItemSpacing.x

        if not settings.spawnAtCursor then
           x = spawnUI.drawSpawnPosition()
        end
        ImGui.Text("At cursor")
        ImGui.SameLine()
        ImGui.SetCursorPosX(x)
        local spawnAtCursorChanged
        settings.spawnAtCursor, spawnAtCursorChanged = ImGui.Checkbox("##cursor", settings.spawnAtCursor)
        if spawnAtCursorChanged then settings.save() end
        style.tooltip("Spawn the object under the cursor.")

        drawStripPathsCheckbox(x)

        ImGui.Text("Reset search")
        ImGui.SameLine()
        ImGui.SetCursorPosX(x)
        local resetSearchChanged
        settings.resetSpawnPopupSearch, resetSearchChanged = ImGui.Checkbox("##reset", settings.resetSpawnPopupSearch)
        if resetSearchChanged then settings.save() end
        style.tooltip("Resets the search when spawning something or closing the popup")

        ImGui.Separator()

        for _, typeName in pairs(typeNames) do
            if ImGui.BeginMenu(typeName) then
                local variantKeys = getSortedVariantNames(typeName)
                local separators = variantSeparatorsByType[typeName] or {}

                for index, variantName in ipairs(variantKeys) do
                    if separators[index] then
                        ImGui.Separator()
                    end
                    if ImGui.BeginMenu(variantName) then
                        spawnUI.drawPopupVariant(typeName, variantName)
                        ImGui.EndMenu()
                    end
                end
                ImGui.EndMenu()
            end
        end

        ImGui.EndPopup()
    else
        spawnUI.popupSpawnHit = nil
    end

    if spawnUI.openPopup then
        spawnUI.openPopup = false
        spawnUI.currentPopupVariant = ""
        if settings.resetSpawnPopupSearch then
            spawnUI.popupFilter = ""
        end

        spawnUI.popupSpawnHit = settings.spawnAtCursor and editor.getCursorSceneHit() or nil

        ImGui.OpenPopup("##spawnNew")
    end

    spawnUI.prefabsUI.drawEditFavoritePopup()
    spawnUI.prefabsUI.drawCreatePrefabPopup()
    spawnUI.favoritesUI.drawPopups()
end

return spawnUI
