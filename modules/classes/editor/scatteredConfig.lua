local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local history = require("modules/utils/history")
local style = require("modules/ui/style")
local scatteredValue = require("modules/classes/editor/scatteredValue")

-- Class for scattered config elements with randomization features
---@class scatteredConfig
---@field rotation {x: scatteredValue, y: scatteredValue, z: scatteredValue}
---@field scale scatteredValue
---@field density scatteredValue
---@field owner element
local scatteredConfig = {}

function scatteredConfig:new(owner)
	local o = {}
	o.owner = owner
	
	local rotX = scatteredValue:new(-0, 0, "MIRROR")
	rotX.label = "Roll"
	rotX.lowerBound = -180
	rotX.upperBound = 180
	rotX.owner = owner

	local rotY = scatteredValue:new(-0, 0, "MIRROR")
	rotY.label = "Pitch"
	rotY.lowerBound = -180
	rotY.upperBound = 180
	rotY.owner = owner

	local rotZ = scatteredValue:new(-180, 180, "MIRROR")
	rotZ.label = "Yaw"
	rotZ.lowerBound = -180
	rotZ.upperBound = 180
	rotZ.owner = owner

	o.rotation = { x = rotX,
				   y = rotY,
				   z = rotZ }

	o.scale = scatteredValue:new(1, 1, "OFF")
	o.scale.label = "Scale"
	o.scale.lowerBound = 0.01
	o.scale.upperBound = 1000
	o.scale.owner = owner

	o.density = scatteredValue:new(10, 25, "OFF", "INT")
	o.density.label = "Density"
	o.density.lowerBound = 0
	o.density.upperBound = 1000
	o.density.owner = owner

	self.__index = self
   	return setmetatable(o, self)
end

function scatteredConfig:draw()
	ImGui.Separator()
	style.styledText("Rotation Randomization:")
	self.rotation.x:draw()
	self.rotation.y:draw()
	self.rotation.z:draw()

	ImGui.Separator()
	style.styledText("Scale Randomization:")
	self.scale:draw()

	ImGui.Separator()
	style.styledText("Density Randomization:")
	self.density:draw()
end

function scatteredConfig:load(owner, data)
	local new = self:new(owner)
	if data == nil then
		return new
	end
	new.rotation = { x = scatteredValue:load(owner, data.rotation.x),
					   y = scatteredValue:load(owner, data.rotation.y),
					   z = scatteredValue:load(owner, data.rotation.z) }
	new.scale = scatteredValue:load(owner, data.scale)
	new.density = scatteredValue:load(owner, data.density)
	return new
end

function scatteredConfig:serialize()
	local data = {}

	data.rotation = {  x = self.rotation.x:serialize(),
					   y = self.rotation.y:serialize(),
					   z = self.rotation.z:serialize() }
	data.scale = self.scale:serialize()
	data.density = self.density:serialize()

	return data
end

return scatteredConfig