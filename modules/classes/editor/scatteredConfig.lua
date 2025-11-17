local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local history = require("modules/utils/history")
local style = require("modules/ui/style")
local scatteredValue = require("modules/classes/editor/scatteredValue")

-- Class for scattered config elements with randomization features
---@class scatteredConfig
---@field position {x: scatteredValue, y: scatteredValue, z: scatteredValue}
---@field rotation {x: scatteredValue, y: scatteredValue, z: scatteredValue}
---@field scale scatteredValue
---@field count scatteredValue
local scatteredConfig = {}

function scatteredConfig:new()
	local o = {}

	o.position = { x = scatteredValue:new(-5, 5, 0.5, "MIRROR"), y =  scatteredValue:new(-5, 5, 0.5, "MIRROR"), z =  scatteredValue:new(0, 0, 0.5, "MIRROR") }
	o.rotation = { x =  scatteredValue:new(-0, 0, 1, "MIRROR"), y =  scatteredValue:new(-0, 0, 1, "MIRROR"), z =  scatteredValue:new(-180, 180, 1, "MIRROR") }
	o.scale = scatteredValue:new(1, 1, 1, "MIRROR")
	o.count = scatteredValue:new(1, 5, 1, "OFF", "INT")

	self.__index = self
   	return setmetatable(o, self)
end

function scatteredConfig:draw()
	ImGui.PushItemWidth(80 * style.viewSize)
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
	self.scale:draw()

	ImGui.Separator()
	style.styledText("Count Randomization:")
	self.count:draw()
end

function scatteredConfig:load(data)
	local new = self:new()
	if data == nil then
		return new
	end
	new.position = { x = scatteredValue:new(data.position.x.min, data.position.x.max, data.distAmplitude, data.position.x.syncType),
					  y = scatteredValue:new(data.position.y.min, data.position.y.max, data.distAmplitude, data.position.y.syncType),
					  z = scatteredValue:new(data.position.z.min, data.position.z.max, data.distAmplitude, data.position.z.syncType) }
	new.rotation = { x = scatteredValue:new(data.rotation.x.min, data.rotation.x.max, data.distAmplitude, data.rotation.x.syncType),
					   y = scatteredValue:new(data.rotation.y.min, data.rotation.y.max, data.distAmplitude, data.rotation.y.syncType),
					   z = scatteredValue:new(data.rotation.z.min, data.rotation.z.max, data.distAmplitude, data.rotation.z.syncType) }
	new.scale = scatteredValue:new(data.scale.min, data.scale.max, data.distAmplitude, data.scale.syncType)
	new.count = scatteredValue:new(data.count.min, data.count.max, data.distAmplitude, data.count.syncType, "INT")
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