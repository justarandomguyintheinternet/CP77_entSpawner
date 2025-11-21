local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local history = require("modules/utils/history")
local style = require("modules/ui/style")
local scatteredValue = require("modules/classes/editor/scatteredValue")

local positionTypes = { "CYLINDER", "RECTANGLE" }

-- Class for scattered config elements with randomization features
---@class scatteredConfig
---@field position {x: scatteredValue, y: scatteredValue, z: scatteredValue, r: scatteredValue, type: string}
---@field rotation {x: scatteredValue, y: scatteredValue, z: scatteredValue}
---@field scale scatteredValue
---@field count scatteredValue
---@field owner element
local scatteredConfig = {}

function scatteredConfig:new(owner)
	local o = {}
	o.owner = owner

	local posX = scatteredValue:new(-5, 5, "MIRROR")
	posX.label = "X"
	posX.lowerBound = -10000
	posX.upperBound = 10000
	posX.owner = owner

	local posY = scatteredValue:new(-5, 5, "MIRROR")
	posY.label = "Y"
	posY.lowerBound = -10000
	posY.upperBound = 10000
	posY.owner = owner

	local posZ = scatteredValue:new(0, 0, "MIRROR")
	posZ.label = "Z"
	posZ.lowerBound = -10000
	posZ.upperBound = 10000
	posZ.owner = owner

	local posR = scatteredValue:new(5, 5, "EQUAL")
	posR.label = "R"
	posR.lowerBound = 0
	posR.upperBound = 10000
	posR.owner = owner

	o.position = { x = posX,
				   y = posY,
				   z = posZ,
				   r = posR,
				   type = "CYLINDER" }
	
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

	o.count = scatteredValue:new(1, 5, "OFF", "INT")
	o.count.label = "Count"
	o.count.lowerBound = 0
	o.count.upperBound = 1000
	o.count.owner = owner

	self.__index = self
   	return setmetatable(o, self)
end

function scatteredConfig:draw()
	style.styledText("Position Randomization:")
	style.mutedText("Type:")
	ImGui.SameLine()
	ImGui.PushItemWidth(120 * style.viewSize)
	local posType, posTypeChanged = ImGui.Combo("##posTypeCombo", utils.indexValue(positionTypes, self.position.type) - 1, positionTypes, #positionTypes)
	if posTypeChanged then
		self.position.type = positionTypes[posType + 1]
	end
	
	if self.position.type == "RECTANGLE" then
		self.position.x:draw()
		self.position.y:draw()
		self.position.z:draw()
	elseif self.position.type == "CYLINDER" then
		self.position.r:draw()
		self.position.z:draw()
	end

	ImGui.Separator()
	style.styledText("Rotation Randomization:")
	self.rotation.x:draw()
	self.rotation.y:draw()
	self.rotation.z:draw()

	ImGui.Separator()
	style.styledText("Scale Randomization:")
	self.scale:draw()

	ImGui.Separator()
	style.styledText("Count Randomization:")
	self.count:draw()
end

function scatteredConfig:load(owner, data)
	local new = self:new(owner)
	if data == nil then
		return new
	end
	new.position = { x = scatteredValue:load(owner, data.position.x),
					  y = scatteredValue:load(owner, data.position.y),
					  z = scatteredValue:load(owner, data.position.z),
					  r = scatteredValue:load(owner, data.position.r) }
	new.rotation = { x = scatteredValue:load(owner, data.rotation.x),
					   y = scatteredValue:load(owner, data.rotation.y),
					   z = scatteredValue:load(owner, data.rotation.z) }
	new.scale = scatteredValue:load(owner, data.scale)
	new.count = scatteredValue:load(owner, data.count)
	return new
end

function scatteredConfig:serialize()
	local data = {}

	data.position = { x = self.position.x:serialize(),
					  y = self.position.y:serialize(),
					  z = self.position.z:serialize(),
					  r = self.position.r:serialize() }
	data.rotation = {  x = self.rotation.x:serialize(),
					   y = self.rotation.y:serialize(),
					   z = self.rotation.z:serialize() }
	data.scale = self.scale:serialize()
	data.count = self.count:serialize()

	return data
end

return scatteredConfig