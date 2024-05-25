local config = require("modules/utils/config")

---@class settingsData
---@field public spawnPos integer
---@field public spawnDist number
---@field public spawnNewSortAlphabetical boolean
---@field public posSteps number
---@field public rotSteps number
---@field public despawnOnReload boolean
---@field public groupRot boolean
---@field public headerState boolean
---@field public deleteConfirm boolean
---@field public moveCloneToParent integer
---@field public groupExport boolean
---@field public autoSpawnRange number
---@field public spawnUIOnlyNames boolean
---@field public editor table {color: integer}
local settingsData = {
    spawnPos = 2,
    spawnDist = 3,
    spawnNewSortAlphabetical = false,
    posSteps = 0.002,
    rotSteps = 0.050,
    despawnOnReload = true,
    groupRot = true,
    headerState = true,
    deleteConfirm = true,
    moveCloneToParent = 1,
    groupExport = false,
    autoSpawnRange = 1000,
    spawnUIOnlyNames = false,
    editor = {
        color = 1
    }
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