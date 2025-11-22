local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local Cron = require("modules/utils/Cron")
local scatteredRectangleArea = require("modules/classes/editor/scatteredRectangleArea")
local scatteredCylinderArea = require("modules/classes/editor/scatteredCylinderArea")

local positionableGroup = require("modules/classes/editor/positionableGroup")

local areaTypes = { "CYLINDER", "RECTANGLE", "AREA" }

---Class scattered positionable group
---@class scatteredGroup : positionableGroup
---@field seed number
---@field snapToGround boolean
---@field snapToGroundOffset number
---@field lastPos Vector4
---@field baseGroup positionableGroup
---@field instanceGroup positionableGroup
---@field applyGroundNormal boolean
---@field area {rectangle: scatteredRectangleArea, cylinder: scatteredCylinderArea, type: string}
local scatteredGroup = setmetatable({}, { __index = positionableGroup })

-- SECTION: "BOILERPLATE"

function scatteredGroup:new(sUI)
	local o = positionableGroup.new(self, sUI)

	o.modulePath = "modules/classes/editor/scatteredGroup"

	o.class = utils.combine(o.class, { "scatteredGroup" })
	o.quickOperations = {}
	o.icon = IconGlyphs.DiceMultipleOutline
	o.supportsSaving = false

	o.seed = 1
    o.snapToGround = false
	o.applyGroundNormal = false

	o.lastPos = nil

	o.maxPropertyWidth = nil

	o.baseGroup = positionableGroup:new(sUI)
	o.baseGroup.name = "Base"
	o.instanceGroup = positionableGroup:new(sUI)
	o.instanceGroup.name = "Instances"
	o.baseGroup:setParent(o)
	o.instanceGroup:setParent(o)

	o.snapToGroundOffset = 100

	o.area = {}
	o.area.rectangle = scatteredRectangleArea:new(o)
	o.area.cylinder = scatteredCylinderArea:new(o)
	o.area.type = "CYLINDER"

	setmetatable(o, { __index = self })
   	return o
end

function scatteredGroup:load(data, silent)
	positionableGroup.load(self, data, silent)

	self.seed = data.seed
	self.snapToGround = data.snapToGround or false
	self.snapToGroundOffset = data.snapToGroundOffset or 100
	self.area = {}
	self.area.rectangle = scatteredRectangleArea:load(self, data.area.rectangle)
	self.area.cylinder = scatteredCylinderArea:load(self, data.area.cylinder)
	self.area.type = data.area.type

	if self.seed == -1 then
		self:reSeed()
	end

	local hasBase, hasInstances = false, false
	for _, child in ipairs(self.childs) do
		if child.name == "Base" then
			hasBase = true
			self.baseGroup = child
		elseif child.name == "Instances" then
			hasInstances = true
			self.instanceGroup = child
		end
	end

	if not hasBase then
		self.baseGroup = positionableGroup:new(self.sUI)
		self.baseGroup.name = "Base"
		self.baseGroup:setParent(self)
	end

	if not hasInstances then
		self.instanceGroup = positionableGroup:new(self.sUI)
		self.instanceGroup.name = "Instances"
		self.instanceGroup:setParent(self)
	end
end

function scatteredGroup:serialize()
	local data = positionableGroup.serialize(self)

	data.seed = self.seed
	data.snapToGround = self.snapToGround
	data.snapToGroundOffset = self.snapToGroundOffset
	data.area = {}
	data.area.rectangle = self.area.rectangle:serialize()
	data.area.cylinder = self.area.cylinder:serialize()
	data.area.type = self.area.type

	return data
end

-- SECTION: SCATTER LOGIC

---@private
---@param scatterConfig scatteredConfig
---@return Vector4
function scatteredGroup:calculatePositionRectangle(scatterConfig)
	local offset = self.area.rectangle:getRandomInstancePositionOffset()
	return utils.addVector(offset, self.lastPos)
end

---@private
---@param scatterConfig scatteredConfig
---@return Vector4
function scatteredGroup:calculatePositionCylinder(scatterConfig)
	local offset = self.area.cylinder:getRandomInstancePositionOffset()
	return utils.addVector(offset, self.lastPos)
end

---@private
---@param scatterConfig scatteredConfig
---@return Vector4
function scatteredGroup:calculatePosition(scatterConfig)
	if self.area.type == "CYLINDER" then
		return self:calculatePositionCylinder(scatterConfig)
	elseif self.area.type == "RECTANGLE" then
		return self:calculatePositionRectangle(scatterConfig)
	else
		print("Unsupported area type: " .. tostring(self.area.type))
		return self.lastPos 
	end
end

---@private
---@param scatterConfig scatteredConfig
---@return EulerAngles
function scatteredGroup:calculateRotation(scatterConfig)
	local Xmin = scatterConfig.rotation.x.min
	local Xmax = scatterConfig.rotation.x.max

	local Ymin = scatterConfig.rotation.y.min
	local Ymax = scatterConfig.rotation.y.max

	local Zmin = scatterConfig.rotation.z.min
	local Zmax = scatterConfig.rotation.z.max

	local rX = math.random(Xmin, Xmax)
	local rY = math.random(Ymin, Ymax)
	local rZ = math.random(Zmin, Zmax)

	return EulerAngles.new(rX, rY, rZ)
end

---@private
---@param scatterConfig scatteredConfig
---@return number
function scatteredGroup:calculateScale(scatterConfig)
	local min = scatterConfig.scale.min
	local max = scatterConfig.scale.max

	return math.random(min, max)
end

---@private
---@param scatterConfig scatteredConfig
---@return number
function scatteredGroup:calculateElementCount(scatterConfig)
	if self.area.type == "RECTANGLE" then
		return self.area.rectangle:getInstancesCount(scatterConfig.density)
	elseif self.area.type == "CYLINDER" then
		return self.area.cylinder:getInstancesCount(scatterConfig.density)
	elseif self.area.type == "AREA" then 
		return 0
	else
		print("Unsupported Area type: " .. tostring(self.area.type))
		return 0
	end
end

function scatteredGroup:applyRandomization(pos, recursiveParam)
	self.lastPos = pos or self.baseGroup:getPosition()
	local recursive = recursiveParam or true
	while self.instanceGroup.childs[1] do
		self.instanceGroup.childs[1]:remove()
	end

	math.randomseed(self.seed)
	for _, child in ipairs(self.baseGroup.childs) do
		if not child.scatterConfig then
			goto continue
		end
		local elementCount = self:calculateElementCount(child.scatterConfig)
		for i = 1, elementCount do

			local newObjSerialized = child:serialize()
			newObjSerialized.visible = true
			newObjSerialized.hiddenByParent = false
			local newObj = require(child.modulePath):new(self.sUI)
			newObj:load(newObjSerialized, true)

			local position = self:calculatePosition(child.scatterConfig)
			newObj:setPosition(position)

			local rotation = self:calculateRotation(child.scatterConfig)
			newObj:setRotation(rotation)

			local scaleValue = self:calculateScale(child.scatterConfig)
			local scale = { x = scaleValue,
			y = scaleValue,
			z = scaleValue }
			newObj:setScale(scale, true)

			newObj:setSilent(false)
			newObj:setVisible(true, true)
			newObj:setParent(self.instanceGroup)

			if recursive and (utils.isA(newObj, "scatteredGroup") or utils.isA(newObj, "randomizedGroup")) then
				Cron.After(0.05, function()
					newObj:applyRandomization()
				end, nil)
			end
		end
		::continue::
	end
	
	if self.snapToGround then
		self:setPosition(utils.addVector(self.lastPos, Vector4.new(0, 0, self.snapToGroundOffset, 0)))
		Cron.After(0.05, function()
			self:dropToSurface(true, Vector4.new(0, 0, -1, 0), true, self.applyGroundNormal)
		end, nil)
	end
end

function scatteredGroup:reSeed()
	self.seed = math.random(0, 999999999)
	self:applyRandomization(nil, false)

	for _, child in pairs(self.instanceGroup.childs) do
		if utils.isA(child, "scatteredGroup") or utils.isA(child, "randomizedGroup") then
			child:reSeed()
		end
	end
end

-- SECTION: UI

function scatteredGroup:getProperties()
	local properties = positionableGroup.getProperties(self)

	table.insert(properties, {
		id = "scatteredGroup",
		name = "Group Scattering",
		defaultHeader = false,
		draw = function ()
			self:drawGroupRandomization()
		end
	})

	return properties
end

function scatteredGroup:drawGroupRandomization()
	if not self.maxPropertyWidth then
		self.maxPropertyWidth = utils.getTextMaxWidth({ "Seed", "Randomization Rule", "Fixed Amount Rule", "Fixed Amount %", "Fixed Amount Total" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
	end

	if ImGui.Button("Apply Randomization") then
		history.addAction(history.getElementChange(self))
		self:applyRandomization()
	end

	style.mutedText("Seed")
	ImGui.SameLine()
	ImGui.SetCursorPosX(self.maxPropertyWidth)
	self.seed, _, finished = style.trackedIntInput(self, "##seed", self.seed, 0, 9999999999)
	if finished then
		self:applyRandomization()
	end 

	ImGui.SameLine()
	style.pushButtonNoBG(true)
	if ImGui.Button(IconGlyphs.Reload) then
		history.addAction(history.getElementChange(self))
		self:reSeed()
	end
	style.pushButtonNoBG(false)

	style.styledText("Snap to Ground")
	ImGui.SameLine()
	local snapToGround, snapToGroundChanged = style.trackedCheckbox(self, "##SnapToGround", self.snapToGround, false)
	if snapToGroundChanged then
		self.snapToGround = snapToGround
	end

	style.styledText("Apply Ground Normal")
	ImGui.SameLine()
	local applyGroundNormal, applyGroundNormalChanged = style.trackedCheckbox(self, "##applyGroundNormal", self.applyGroundNormal, false)
	if applyGroundNormalChanged then
		self.applyGroundNormal = applyGroundNormal
	end

	style.styledText("Snap Offset")
	ImGui.SameLine()
	local snapOffset, snapOffsetChanged = ImGui.DragFloat("##SnapOffset", self.snapToGroundOffset, 0.1, 0.1, 1000)
	if snapOffsetChanged then
		self.snapToGroundOffset = snapOffset
	end

	style.styledText("Position Randomization:")
	style.mutedText("Type:")
	ImGui.SameLine()
	ImGui.PushItemWidth(120 * style.viewSize)
	local posType, posTypeChanged = ImGui.Combo("##posTypeCombo", utils.indexValue(areaTypes, self.area.type) - 1, areaTypes, #areaTypes)
	if posTypeChanged then
		self.area.type = areaTypes[posType + 1]
	end
	
	if self.area.type == "RECTANGLE" then
		self.area.rectangle:draw()
	elseif self.area.type == "CYLINDER" then
		self.area.cylinder:draw()
	end
end

return scatteredGroup