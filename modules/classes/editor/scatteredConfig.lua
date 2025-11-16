local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local history = require("modules/utils/history")
local style = require("modules/ui/style")
local minMaxValue = require("modules/classes/editor/minMaxValue")

-- Class for scattered config elements with randomization features
---@class scatteredConfig
---@field position {x: minMaxValue, y: minMaxValue, z: minMaxValue}
---@field rotation {x: minMaxValue, y: minMaxValue, z: minMaxValue}
---@field scale {x: minMaxValue, y: minMaxValue, z: minMaxValue}
---@field count minMaxValue
local scatteredConfig = {}

function scatteredConfig:new()
	local o = {}

	o.baseObj = nil
	o.position = { x = minMaxValue:new(-1, 1, true, "MIRROR"), y =  minMaxValue:new(-1, 1, true, "MIRROR"), z =  minMaxValue:new(-1, 1, true, "MIRROR") }
	o.rotation = { x =  minMaxValue:new(-180, 180, true, "MIRROR"), y =  minMaxValue:new(-180, 180, true, "MIRROR"), z =  minMaxValue:new(-180, 180, true, "MIRROR") }
	o.scale = { x = minMaxValue:new(0.5, 1.5, false, "NONE"), y = minMaxValue:new(0.5, 1.5, false, "NONE"), z = minMaxValue:new(0.5, 1.5, false, "NONE") }
	o.count = minMaxValue:new(0, 1, false, "NONE", "INT")

	self.__index = self
   	return setmetatable(o, self)
end

function scatteredConfig:draw()

	style.styledText("Position Randomization:")
	style.mutedText("X")
	ImGui.SameLine()
	self.position.x:draw()
	style.mutedText("Y")
	ImGui.SameLine()
	self.position.y:draw()
	style.mutedText("Z")
	ImGui.SameLine()
	self.position.z:draw()

	ImGui.Separator()
	style.styledText("Rotation Randomization:")
	style.mutedText("Roll")
	ImGui.SameLine()
	self.rotation.x:draw()
	style.mutedText("Pitch")
	ImGui.SameLine()
	self.rotation.y:draw()
	style.mutedText("Yaw")
	ImGui.SameLine()
	self.rotation.z:draw()

	ImGui.Separator()
	style.styledText("Scale Randomization:")
	style.mutedText("X")
	ImGui.SameLine()
	self.scale.x:draw()
	style.mutedText("Y")
	ImGui.SameLine()
	self.scale.y:draw()
	style.mutedText("Z")
	ImGui.SameLine()
	self.scale.z:draw()

	ImGui.Separator()
	style.styledText("Count Randomization:")
	self.count:draw()
end

function scatteredConfig:load(data)
	local new = self:new()
	if data == nil then
		return new
	end
	new.position = { x = minMaxValue:new(data.position.x.min, data.position.x.max, data.position.x.synced, data.position.x.syncType),
					  y = minMaxValue:new(data.position.y.min, data.position.y.max, data.position.y.synced, data.position.y.syncType),
					  z = minMaxValue:new(data.position.z.min, data.position.z.max, data.position.z.synced, data.position.z.syncType) }
	new.rotation = { x = minMaxValue:new(data.rotation.x.min, data.rotation.x.max, data.rotation.x.synced, data.rotation.x.syncType),
					   y = minMaxValue:new(data.rotation.y.min, data.rotation.y.max, data.rotation.y.synced, data.rotation.y.syncType),
					   z = minMaxValue:new(data.rotation.z.min, data.rotation.z.max, data.rotation.z.synced, data.rotation.z.syncType) }
	new.scale = { x = minMaxValue:new(data.scale.x.min, data.scale.x.max, data.scale.x.synced, data.scale.x.syncType),
					y = minMaxValue:new(data.scale.y.min, data.scale.y.max, data.scale.y.synced, data.scale.y.syncType),
					z = minMaxValue:new(data.scale.z.min, data.scale.z.max, data.scale.z.synced, data.scale.z.syncType) }
	new.count = minMaxValue:new(data.count.min, data.count.max, data.count.synced, data.count.syncType)
	return new
end

function scatteredConfig:serialize()
	local data = {}

	data.position = self.position
	data.rotation = self.rotation
	data.scale = self.scale
	data.count = self.count

	return data
end

return scatteredConfig