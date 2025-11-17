local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local settings = require("modules/utils/settings")

local syncTypes = { "OFF", "MIRROR", "EQUAL" }

-- Class for scattered values
---@class scatteredValue
---@field min number
---@field max number
---@field mean number
---@field distAmplitude number
---@field synced boolean
---@field syncType string
---@filed valueType string
---@field id number
---@field draw fun(self: scatteredValue)
---@field new fun(self: scatteredValue, min: number, max: number, distAmplitude: number, syncType: string, valueType: string): scatteredValue
local scatteredValue = {}

local function getMean(v1, v2)
    return (v1 + v2) / 2
end

function scatteredValue:new(min, max, distAmplitude, syncType, valueType)
    local o = {}

    o.min = min or 0
    o.max = max or 0
    o.mean = getMean(o.min, o.max)
    o.distAmplitude = distAmplitude or 0.5
    o.syncType = syncType or "MIRROR"
    o.valueType = valueType or "FLOAT"
    o.id = math.random(1000000)
    self.__index = self
   	return setmetatable(o, self)
end

function scatteredValue:draw()
    local min, minChanged
    local max, maxChanged 
    if self.valueType == "FLOAT" then
        min, minChanged = ImGui.DragFloat("##min" .. self.id, self.min, settings.posSteps)
        ImGui.SameLine()
        max, maxChanged = ImGui.DragFloat("##max" .. self.id, self.max, settings.posSteps)
    elseif self.valueType == "INT" then
        min, minChanged = ImGui.DragInt("##min" .. self.id, self.min, 1)
        ImGui.SameLine()
        max, maxChanged = ImGui.DragInt("##max" .. self.id, self.max, 1)
    else 
        style.styledText("Unsupported value type: " .. self.valueType)
    end

    local syncType, syncChanged = ImGui.Combo("##type" .. self.id, utils.indexValue(syncTypes, self.syncType) - 1, syncTypes, #syncTypes)
    if syncChanged then
        self.syncType = syncTypes[syncType + 1]
    end
    ImGui.SameLine()
    local amp, ampChanged = ImGui.DragFloat("##amp" .. self.id, self.distAmplitude, 0.1, 0.1, 100)
    if ampChanged then
        self.distAmplitude = amp
    end

    if self.syncType == "MIRROR" then
        if minChanged then
            self.min = min
            self.max = min * -1
        elseif maxChanged then
            self.max = max
            self.min = max * -1
        end
    elseif self.syncType == "EQUAL" then
        if minChanged then
            self.min = min
            self.max = min
        elseif maxChanged then
            self.max = max
            self.min = max
        end
    elseif self.syncType == "OFF" then
        if minChanged then
            self.min = min
        end
        if maxChanged then
            self.max = max
        end
    end

    if minChanged or maxChanged then
        self.mean = getMean(self.min, self.max)
    end
end

return scatteredValue