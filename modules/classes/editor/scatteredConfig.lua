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
local scatteredConfig = {}

function scatteredConfig:new()
	local o = {}

	o.position = { x = scatteredValue:new(-5, 5, "MIRROR"), y =  scatteredValue:new(-5, 5, "MIRROR"), z =  scatteredValue:new(0, 0, "MIRROR"), r = scatteredValue:new(5, 5, "EQUAL"), type = "CYLINDER" }
	o.rotation = { x =  scatteredValue:new(-0, 0, "MIRROR"), y =  scatteredValue:new(-0, 0, "MIRROR"), z =  scatteredValue:new(-180, 180, "MIRROR") }
	o.scale = scatteredValue:new(1, 1, "MIRROR")
	o.count = scatteredValue:new(1, 5, "OFF", "INT")

	self.__index = self
   	return setmetatable(o, self)
end

function scatteredConfig:draw()
	ImGui.PushItemWidth(80 * style.viewSize)
	style.styledText("Position Randomization:")
	local posType, posTypeChanged = ImGui.Combo("##posTypeCombo", utils.indexValue(positionTypes, self.position.type) - 1, positionTypes, #positionTypes)
	if posTypeChanged then
		self.position.type = positionTypes[posType + 1]
	end
	
	if self.position.type == "RECTANGLE" then
		style.mutedText("X")
		ImGui.SameLine()
		self.position.x:draw()
		style.mutedText("Y")
		ImGui.SameLine()
		self.position.y:draw()
		style.mutedText("Z")
		ImGui.SameLine()
		self.position.z:draw()
	elseif self.position.type == "CYLINDER" then
		style.mutedText("R")
		ImGui.SameLine()
		self.position.r:draw()
		style.mutedText("Z")
		ImGui.SameLine()
		self.position.z:draw()
	end

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
	new.position = { x = scatteredValue:load(data.position.x),
					  y = scatteredValue:load(data.position.y),
					  z = scatteredValue:load(data.position.z),
					  r = scatteredValue:load(data.position.r) }
	new.rotation = { x = scatteredValue:load(data.rotation.x),
					   y = scatteredValue:load(data.rotation.y),
					   z = scatteredValue:load(data.rotation.z) }
	new.scale = scatteredValue:load(data.scale)
	new.count = scatteredValue:load(data.count)
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