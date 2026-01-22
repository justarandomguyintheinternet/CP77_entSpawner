local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local settings = require("modules/utils/settings")

local syncTypes = { "OFF", "MIRROR", "EQUAL" }

-- Class for scattered values
---@class scatteredValue
---@field min number
---@field max number
---@field synced boolean
---@field syncType string
---@field valueType string
---@field id number
---@field lowerBound number
---@field upperBound number
---@field label string
---@field owner element
---@field draw fun(self: scatteredValue)
---@field new fun(self: scatteredValue, min: number, max: number, syncType: string, valueType: string): scatteredValue
---@field load fun(self: scatteredValue, owner: element, data: table): scatteredValue
---@field serialize fun(self: scatteredValue): table
local scatteredValue = {}

function scatteredValue:new(min, max, syncType, valueType)
    local o = {}

    o.min = min or 0
    o.max = max or 0
    o.lowerBound = 0
    o.upperBound = 1000

    o.label = ""

    o.syncType = syncType or "MIRROR"
    o.valueType = valueType or "FLOAT"

    o.owner = nil

    o.id = math.random(1000000)
    self.__index = self
   	return setmetatable(o, self)
end

function scatteredValue:load(owner, data)
    local sv = self:new(data.min, data.max, data.syncType, data.valueType)
    sv.lowerBound = data.lowerBound or 0
    sv.upperBound = data.upperBound or 1000
    sv.label = data.label or ""
    sv.owner = owner
    return sv
end

function scatteredValue:serialize()
    return {
        min = self.min,
        max = self.max,
        lowerBound = self.lowerBound,
        upperBound = self.upperBound,
        label = self.label,
        syncType = self.syncType,
        valueType = self.valueType
    }
end

---@return boolean
function scatteredValue:draw()
    local minLow, minHigh
    local maxLow, maxHigh

    if self.syncType == "EQUAL" then
        minLow = self.lowerBound
        minHigh = self.upperBound
        maxLow = self.lowerBound
        maxHigh = self.upperBound
    elseif self.syncType == "MIRROR" then
        minLow = self.lowerBound
        minHigh = 0
        maxLow = 0
        maxHigh = self.upperBound
    else
        minLow = self.lowerBound
        minHigh = self.max
        maxLow = self.min
        maxHigh = self.upperBound
    end

    local format, step
    if self.valueType == "FLOAT" then
        format = "%.2f "
        step = settings.posSteps
    else 
        format = "%.0f "
        step = 1
    end

    local min, minChanged = style.trackedDragFloat(self.owner, "##min" .. self.id, self.min, step, minLow, minHigh, format .. self.label)
    ImGui.SameLine()
    local max, maxChanged = style.trackedDragFloat(self.owner, "##max" .. self.id, self.max, step, maxLow, maxHigh, format .. self.label)

    ImGui.PushItemWidth(80 * style.viewSize)
    ImGui.SameLine()
    local syncType, syncChanged = ImGui.Combo("##type" .. self.id, utils.indexValue(syncTypes, self.syncType) - 1, syncTypes, #syncTypes)
    if syncChanged then
        self.syncType = syncTypes[syncType + 1]
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

    return minChanged or maxChanged
end

return scatteredValue