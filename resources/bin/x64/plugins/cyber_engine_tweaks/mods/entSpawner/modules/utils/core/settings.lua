local config = require("modules/utils/core/config")

---@class settingsData
---@field public spawnPos integer
---@field public spawnDist number
---@field public posSteps number
---@field public precisionMultiplier number
---@field public coarsePrecisionMultiplier number
---@field public rotSteps number
---@field public rotationShiftClickStep number
---@field public applyRotationWhenDropped boolean Default "Apply Rotation When Dropped" state for newly created elements.
---@field public dropToFloorMode integer Where a dropped element lands: 0 = asset origin on the surface, 1 = bounding box bottom on the surface.
---@field public despawnOnReload boolean
---@field public deleteConfirm boolean
---@field public moveCloneToParent integer
---@field public spawnUIOnlyNames boolean
---@field public spawnUIHierarchyTree boolean
---@field public colliderColor integer
---@field public selectedType string
---@field public lastVariants table
---@field public spawnUIFilter string
---@field public savedUIFilter string
---@field public windowStates table
---@field public editorBottomSize integer
---@field public gizmoOnHover boolean
---@field public gizmoOnSelected boolean
---@field public arrowScaleWithDistance boolean
---@field public arrowSizeMultiplier number
---@field public gizmoRingMode string Rotation rings: "combined" with the arrows, "split" (G and R switch between them) or "off"
---@field public gizmoRingQuarters boolean Rotation rings show only the quarter facing the camera
---@field public gizmoRingSize number Rotation ring radius as a multiple of the arrow length
---@field public rotationSnapStep number Degrees a rotation snaps to while Shift is held
---@field public outlineSelected boolean
---@field public componentParentChain boolean
---@field public componentKindsOpen boolean
---@field public componentHelpersDefault boolean
---@field public componentRadiusHelpersDefault boolean
---@field public selectedVisualizersEnabled boolean
---@field public outlineColor integer
---@field public editorWidth integer
---@field public mainWindowWidth integer
---@field public mainWindowHeight integer
---@field public resetSpawnPopupSearch boolean
---@field public spawnAtCursor boolean
---@field public defaultAISpotNPC string
---@field public defaultAISpotAppearance string
---@field public defaultAISpotSpeed number
---@field public defaultLightColor number[] Default RGB color for newly spawned static lights.
---@field public defaultSplineCurveQuality number
---@field public staticMarkerShowName boolean Default "Show Name" state for newly created Static Markers.
---@field public staticMarkerNameMode integer Static Marker label content: 0 = element name, 1 = simplified NodeRef, 2 = full NodeRef.
---@field public nodeRefPrefix string
---@field public cacheExclusions table
---@field public assetPreviewEnabled table
---@field public prefabsAssetPreviewEnabled boolean Master switch for hover previews in the Prefabs sub-tab.
---@field public prefabPreviewMaxAssets number
---@field public spawnNewVisualizerEnabledByModule table<string, boolean>
---@field public filterTags table
---@field public favoritesFilter string
---@field public favoritesTagsAND boolean
---@field public favoritesGroupingState table
---@field public assetFavoritesFilter string
---@field public assetFavoritesFilterTags table
---@field public assetFavoritesTagsAND boolean
---@field public assetFavoritesGroupOpen table
---@field public mainWindowName string
---@field public draggingThreshold number
---@field public cameraMovementSpeed number
---@field public cameraRotateSpeed number
---@field public cameraZoomSpeed number
---@field public setLoadedGroupAsSpawnNew boolean
---@field public groupLoadSpeedPreset integer
---@field public exportGroupsHeight number
---@field public exportTemplatesHeight number
---@field public skipLossyConversionWarning boolean
---@field public skipTemplateDeleteConfirm boolean
---@field public editorDockLeft boolean
---@field public groupWireframeEnabled boolean
---@field public wireframeColorStyle integer
---@field public spawnedUIPerfEnabled boolean
---@field public spawnedUIPerfShowPanel boolean
---@field public colorPickerStyle integer
---@field public rhtAddonReplacerMode string
---@field public rhtAddonMeshTargetType string
---@field public previewTimelineDockBottom boolean
---@field public previewTimelineDockHeight number
---@field public previewTimelineZoom number
---@field public previewTimelineSnapEnabled boolean
---@field public previewTimelineSnapSec number
---@field public actionLabelDisplayMode integer
---@field public stickyRowsEnabled boolean
---@field public underscoreNames boolean Replace spaces with `_` in element names when edited, added or generated.
---@field public speedUnit integer
---@field public speedTimelineDockBottom boolean
---@field public speedTimelineDockHeight number
---@field public speedTimelineZoom number
---@field public speedTimelineSnapEnabled boolean
---@field public speedTimelineSnapMeters number
---@field public defaultColliderMaterial integer
---@field public defaultGroupProject table? Default project tag ({name, icon, color}) assigned to new groups, or nil for none.
---@field public defaultStreamingPreset integer Default streaming distance preset index (0 = Interior) for new spawnables.
---@field public defaultExportFormat integer Default export XL format (0 = JSON, 1 = YAML).
---@field public defaultVariantOn boolean Default visible state applied when an export variant receives a non-default name.
---@field public previewBindings table<string, string> ImGuiKey names bound to the asset preview controls, keyed by action id. Empty until first resolved from the game language.
---@field public autoSaveEnabled boolean Periodically write modified root groups back to their project file.
---@field public autoSaveIntervalMinutes number Minutes between auto-save passes.
---@field public autoSaveShowToasts boolean Show a toast when a group is auto-saved.
---@field public sessionRestoreEnabled boolean Keep a crash-recovery snapshot of the Spawned tab.
---@field public autoSaveQuietSeconds number Idle time required after the last edit before a group is processed.
---@field public persistenceBudgetMs number Per-frame time budget for the persistence pipeline.
---@field public autoSaveVerifyEvery integer Verify every Nth auto-save against a cache-free rebuild (0 = never).
---@field public autoSaveCacheEnabled boolean Reuse cached per-node JSON. Disable to fall back to full rebuilds.
---@field public validateAssetTypes boolean Refuse to spawn an asset whose resource type the node cannot spawn.
---@field public savedSortMode integer Order of the Projects tab: 1 = alphabetically, 2 = last loaded first.
---@field public savedLoadOrder table<string, integer> Load rank per project file, higher is more recent. Only used by the "last loaded" sort mode.
---@field public savedLoadCounter integer Rank handed to the next loaded entry, so every load orders after all earlier ones.
local settingsData = {
    spawnPos = 1,
    spawnDist = 4,
    posSteps = 0.002,
    precisionMultiplier = 0.2,
    coarsePrecisionMultiplier = 5,
    rotSteps = 0.050,
    rotationShiftClickStep = 90,
    applyRotationWhenDropped = true,
    dropToFloorMode = 0,
    despawnOnReload = true,
    deleteConfirm = true,
    moveCloneToParent = 2,
    spawnUIOnlyNames = false,
    spawnUIHierarchyTree = false,
    colliderColor = 0,
    selectedType = "Entity",
    lastVariants = { Entity = "Template", Lighting = "Static Light", Mesh = "Mesh", Collision = "Collision Shape", ["Deco"] = "Particles", ["Meta"] = "Occluder", ["Area"] = "Outline Marker", ["AI"] = "AI Spot" },
    spawnUIFilter = "",
    savedUIFilter = "",
    windowStates = {},
    editorBottomSize = 200,
    gizmoOnHover = true,
    gizmoOnSelected = true,
    arrowScaleWithDistance = true,
    arrowSizeMultiplier = 1.0,
    gizmoRingMode = "combined",
    gizmoRingQuarters = true,
    gizmoRingSize = 1.05,
    rotationSnapStep = 15,
    outlineSelected = true,
    componentParentChain = true,
    componentKindsOpen = false,
    componentHelpersDefault = false,
    componentRadiusHelpersDefault = false,
    selectedVisualizersEnabled = true,
    outlineColor = 0,
    editorWidth = 0,
    mainWindowWidth = 0,
    mainWindowHeight = 0,
    resetSpawnPopupSearch = true,
    spawnAtCursor = true,
    defaultAISpotNPC = "Character.Judy",
    defaultAISpotAppearance = "default",
    defaultAISpotSpeed = 3,
    defaultLightColor = { 1, 0.99595707654953, 0.6502890586853 },
    defaultSplineCurveQuality = 12,
    staticMarkerShowName = false,
    staticMarkerNameMode = 1, -- Simplified NodeRef
    nodeRefPrefix = "mod",
    cacheExclusions = {},
    assetPreviewEnabled = {},
    prefabsAssetPreviewEnabled = true,
    prefabPreviewMaxAssets = 300,
    spawnNewVisualizerEnabledByModule = {},
    mainWindowName = "World Builder",
    draggingThreshold = 5,
    cameraMovementSpeed = 4,
    cameraRotateSpeed = 0.4,
    cameraZoomSpeed = 2.75,
    setLoadedGroupAsSpawnNew = false,
    groupLoadSpeedPreset = 1,
    exportGroupsHeight = 260,
    exportTemplatesHeight = 160,
    skipLossyConversionWarning = false,
    skipTemplateDeleteConfirm = false,
    editorDockLeft = false,
    groupWireframeEnabled = false,
    wireframeColorStyle = 1,
    spawnedUIPerfEnabled = false,
    spawnedUIPerfShowPanel = false,
    colorPickerStyle = 2,
    rhtAddonReplacerMode = "clone",
    rhtAddonMeshTargetType = "Auto",
    previewTimelineDockBottom = false,
    previewTimelineDockHeight = 320,
    previewTimelineZoom = 90,
    previewTimelineSnapEnabled = true,
    previewTimelineSnapSec = 0.1,
    actionLabelDisplayMode = 2,
    stickyRowsEnabled = false,
    underscoreNames = false,
    speedUnit = 1,
    speedTimelineDockBottom = false,
    speedTimelineDockHeight = 300,
    speedTimelineZoom = 12, -- pixels per meter
    speedTimelineSnapEnabled = true,
    speedTimelineSnapMeters = 0.5,

    filterTags = {},
    favoritesFilter = "",
    favoritesTagsAND = false,
    favoritesGroupingState = {},

    assetFavoritesFilter = "",
    assetFavoritesFilterTags = {},
    assetFavoritesTagsAND = false,
    assetFavoritesGroupOpen = {},

    defaultColliderMaterial = 12,
    -- defaultGroupProject is intentionally omitted (nil) so "none" is the default.
    defaultStreamingPreset = 0, -- Interior
    defaultExportFormat = 0, -- JSON
    defaultVariantOn = false, -- Hidden

    -- Saving & recovery
    autoSaveEnabled = false,
    autoSaveIntervalMinutes = 5,
    autoSaveShowToasts = true,
    sessionRestoreEnabled = true,
    -- Advanced (Debug section)
    autoSaveQuietSeconds = 2,
    persistenceBudgetMs = 4,
    autoSaveVerifyEvery = 4,
    autoSaveCacheEnabled = true,
    validateAssetTypes = true,

    -- Projects tab ordering
    savedSortMode = 1, -- Alphabetically
    savedLoadOrder = {},
    savedLoadCounter = 0,

    -- Resolved from the game language on first use, see previewControls.getBindings
    previewBindings = {},
}

local settingsFNs = {}

function settingsFNs.load()
    config.tryCreateConfig("data/config.json", settingsData)

    local data = config.loadFile("data/config.json")
    if data.gizmoOnHover == nil and data.gizmoActive ~= nil then
        data.gizmoOnHover = data.gizmoActive
        data.gizmoActive = nil
        config.saveFile("data/config.json", data)
    end

    if data.cacheExlusions ~= nil then
        local hasNewValue = type(data.cacheExclusions) == "table" and next(data.cacheExclusions) ~= nil
        if not hasNewValue then
            data.cacheExclusions = data.cacheExlusions
        end

        data.cacheExlusions = nil
        config.saveFile("data/config.json", data)
    end

    data.tabSizes = nil
    settingsData.tabSizes = nil

    config.backwardComp("data/config.json", settingsData)

    data = config.loadFile("data/config.json")
    data.tabSizes = nil
    data.headerState = nil
    data.ignoreHiddenDuringExport = nil
    for k, v in pairs(data) do
        settingsData[k] = v
    end
end

function settingsFNs.save()
    config.saveFile("data/config.json", settingsData)
end

local settings = {
    load = settingsFNs.load,
    save = settingsFNs.save,
    -- Real key on the proxy rather than on `settingsData`, so the labels are not written to disk.
    dropToFloorModes = { "Asset origin", "Bounding box bottom" }
}

settings = setmetatable(settings, {
    __index = settingsData,
    __newindex = settingsData
})

return settings
