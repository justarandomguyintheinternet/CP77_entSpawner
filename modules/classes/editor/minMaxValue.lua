local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local settings = require("modules/utils/settings")

-- Class for min max values
---@class minMaxValue
---@field min number
---@field max number
---@field synced boolean
---@field syncType string
---@filed valueType string
---@field id number
---@field draw fun(self: minMaxValue)
---@field new fun(self: minMaxValue, min: number, max: number, synced: boolean, syncType: string, valueType: string): minMaxValue
local minMaxValue = {}

function minMaxValue:new(min, max, synced, syncType, valueType)
    local o = {}

    o.min = min or 0
    o.max = max or 0
    o.synced = synced or false
    o.syncType = syncType or "MIRROR"
    o.valueType = valueType or "FLOAT"
    o.id = math.random(1000000)
    self.__index = self
   	return setmetatable(o, self)
end

function minMaxValue:draw()
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
    if self.syncType == "MIRROR" then
        ImGui.SameLine()
        local synced, syncedChanged = ImGui.Checkbox("Synced##" .. self.id, self.synced)
    
        if syncedChanged then
            self.synced = synced
        end

        if self.synced then
            if minChanged then
                self.min = min
                self.max = min * -1
            elseif maxChanged then
                self.max = max
                self.min = max * -1
            end
            return
        end
    end

    if minChanged then
        self.min = min
    end
    if maxChanged then
        self.max = max
    end
end

return minMaxValue