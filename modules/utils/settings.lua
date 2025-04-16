local config = require("modules/utils/config")

---@class settingsData
---@field public spawnPos integer
---@field public spawnDist number
---@field public posSteps number
---@field public precisionMultiplier number
---@field public rotSteps number
---@field public despawnOnReload boolean
---@field public headerState boolean
---@field public deleteConfirm boolean
---@field public moveCloneToParent integer
---@field public spawnUIOnlyNames boolean
---@field public editor {color: integer}
---@field public colliderColor integer
---@field public selectedType string
---@field public lastVariants table
---@field public spawnUIFilter string
---@field public savedUIFilter string
---@field public windowStates table
---@field public editorBottomSize integer
---@field public gizmoActive boolean
---@field public gizmoOnSelected boolean
---@field public outlineSelected boolean
---@field public outlineColor integer
---@field public editorWidth integer
---@field public resetSpawnPopupSearch boolean
---@field public spawnAtCursor boolean
---@field public defaultAISpotNPC string
---@field public tabSizes table
---@field public defaultAISpotSpeed number
---@field public nodeRefPrefix string
---@field public cacheExlusions table
---@field public assetPreviewEnabled table
---@field public filterTags table
---@field public favoritesFilter string
---@field public favoritesTagsAND boolean
---@field public mainWindowName string
---@field public draggingThreshold number
---@field public ignoreHiddenDuringExport boolean
local settingsData = {
    spawnPos = 1,
    spawnDist = 4,
    posSteps = 0.002,
    precisionMultiplier = 0.2,
    rotSteps = 0.050,
    despawnOnReload = true,
    headerState = true,
    deleteConfirm = true,
    moveCloneToParent = 1,
    spawnUIOnlyNames = false,
    editor = {
        color = 1
    },
    colliderColor = 0,
    selectedType = "Entity",
    lastVariants = { Entity = "Template", Lights = "Light", Mesh = "Mesh", Collision = "Collision Shape", ["Deco"] = "Particles", ["Meta"] = "Occluder", ["Area"] = "Outline Marker", ["AI"] = "AI Spot" },
    spawnUIFilter = "",
    savedUIFilter = "",
    windowStates = {},
    editorBottomSize = 200,
    gizmoActive = true,
    gizmoOnSelected = true,
    outlineSelected = true,
    outlineColor = 0,
    editorWidth = 0,
    resetSpawnPopupSearch = true,
    spawnAtCursor = true,
    defaultAISpotNPC = "Character.Judy",
    defaultAISpotSpeed = 3,
    nodeRefPrefix = "mod",
    cacheExlusions = {},
    assetPreviewEnabled = {},
    mainWindowName = "World Builder",
    draggingThreshold = 5,
    ignoreHiddenDuringExport = false,

    filterTags = {},
    favoritesFilter = "",
    favoritesTagsAND = false,

    tabSizes = {}
}

local settingsFNs = {}

function settingsFNs.load()
    config.tryCreateConfig("data/config.json", settingsData)
    config.backwardComp("data/config.json", settingsData)

    local data = config.loadFile("data/config.json")
    for k, v in pairs(data) do
        settingsData[k] = v
    end
end

function settingsFNs.save()
    config.saveFile("data/config.json", settingsData)
end

local settings = {
    load = settingsFNs.load,
    save = settingsFNs.save
}

settings = setmetatable(settings, {
    __index = settingsData,
    __newindex = settingsData
})

return settings