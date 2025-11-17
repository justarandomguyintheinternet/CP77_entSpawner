local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local Cron = require("modules/utils/Cron")

local positionableGroup = require("modules/classes/editor/positionableGroup")

---Class scattered positionable group
---@class scatteredGroup : positionableGroup
---@field seed number
---@field snapToGround boolean
---@field snapToGroundOffset number
---@field lastPos Vector4
---@field baseGroup positionableGroup
---@field instanceGroup positionableGroup
---@field positionMultiplier number
---@field rotationMultiplier number
---@field scaleMultiplier number
---@field instanceCountMultiplier number
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

	o.lastPos = nil

	o.maxPropertyWidth = nil

	o.baseGroup = positionableGroup:new(sUI)
	o.baseGroup.name = "Base"
	o.instanceGroup = positionableGroup:new(sUI)
	o.instanceGroup.name = "Instances"
	o.baseGroup:setParent(o)
	o.instanceGroup:setParent(o)

	o.positionMultiplier = 1
	o.rotationMultiplier = 1
	o.scaleMultiplier = 1
	o.instanceCountMultiplier = 1
	o.snapToGroundOffset = 100

	setmetatable(o, { __index = self })
   	return o
end

function scatteredGroup:load(data, silent)
	positionableGroup.load(self, data, silent)

	self.seed = data.seed
	self.snapToGround = data.snapToGround or false
	self.snapToGroundOffset = data.snapToGroundOffset or 100
	self.positionMultiplier = data.positionMultiplier or 1
	self.rotationMultiplier = data.rotationMultiplier or 1
	self.scaleMultiplier = data.scaleMultiplier or 1
	self.instanceCountMultiplier = data.instanceCountMultiplier or 1

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

	data.positionMultiplier = self.positionMultiplier
	data.rotationMultiplier = self.rotationMultiplier
	data.scaleMultiplier = self.scaleMultiplier
	data.instanceCountMultiplier = self.instanceCountMultiplier
	data.snapToGroundOffset = self.snapToGroundOffset
	return data
end

-- SECTION: SCATTER LOGIC

---@private
---@param scatterConfig scatteredConfig
---@return Vector4
function scatteredGroup:calculatePosition(scatterConfig)
	return Vector4.new((math.random(scatterConfig.position.x.min * self.positionMultiplier, scatterConfig.position.x.max * self.positionMultiplier) + self.lastPos.x),
				(math.random(scatterConfig.position.y.min * self.positionMultiplier, scatterConfig.position.y.max * self.positionMultiplier) + self.lastPos.y),
				(math.random(scatterConfig.position.z.min * self.positionMultiplier, scatterConfig.position.z.max * self.positionMultiplier) + self.lastPos.z), 1)
end

---@private
---@param scatterConfig scatteredConfig
---@return EulerAngles
function scatteredGroup:calculateRotation(scatterConfig)
	return EulerAngles.new(math.random(scatterConfig.rotation.x.min * self.rotationMultiplier, scatterConfig.rotation.x.max * self.rotationMultiplier),
			math.random(scatterConfig.rotation.y.min * self.rotationMultiplier, scatterConfig.rotation.y.max * self.rotationMultiplier),
			math.random(scatterConfig.rotation.z.min * self.rotationMultiplier, scatterConfig.rotation.z.max * self.rotationMultiplier))
end

---@private
---@param scatterConfig scatteredConfig
---@return number
function scatteredGroup:calculateScale(scatterConfig)
	return math.random(scatterConfig.scale.min * self.scaleMultiplier, scatterConfig.scale.max * self.scaleMultiplier)
end

---@private
---@param scatterConfig scatteredConfig
---@return number
function scatteredGroup:calculateElementCount(scatterConfig)
	return math.random(scatterConfig.count.min * self.instanceCountMultiplier, scatterConfig.count.max * self.instanceCountMultiplier)
end

function scatteredGroup:applyRandomization(pos, recursiveParam)
	self.lastPos = pos or self:getPosition()
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
		self:setPositionDelta(Vector4.new(0, 0, self.snapToGroundOffset, 0))
		Cron.After(0.05, function()
			self:dropToSurface(Vector4.new(0, 0, -1, 0))
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
	local snapToGround, snapToGroundChanged = style.trackedCheckbox(self, "Snap to Ground", self.snapToGround, false)
	if snapToGroundChanged then
		self.snapToGround = snapToGround
	end

	style.styledText("Snap Offset")
	ImGui.SameLine()
	local snapOffset, snapOffsetChanged = ImGui.DragFloat("##SnapOffset", self.snapToGroundOffset, 0.1, 0.1, 1000)
	if snapOffsetChanged then
		self.snapToGroundOffset = snapOffset
	end

	style.styledText("Position Multiplier")
	ImGui.SameLine()
	local posMult, posMultChanged = ImGui.DragFloat("##PositionMultiplier", self.positionMultiplier,  0.1, 0.1, 100)
	if posMultChanged then
		self.positionMultiplier = posMult
	end

	style.styledText("Rotation Multiplier")
	ImGui.SameLine()
	local rotMult, rotMultChanged = ImGui.DragFloat("##RotationMultiplier", self.rotationMultiplier,  0.1, 0.1, 100)
	if rotMultChanged then
		self.rotationMultiplier = rotMult
	end

	style.styledText("Scale Multiplier")
	ImGui.SameLine()
	local scaleMult, scaleMultChanged = ImGui.DragFloat("##ScaleMultiplier", self.scaleMultiplier, 0.1, 0.1, 100)
	if scaleMultChanged then
		self.scaleMultiplier = scaleMult
	end

	style.styledText("Instance Count Multiplier")
	ImGui.SameLine()
	local countMult, countMultChanged = ImGui.DragFloat("##InstanceCountMultiplier", self.instanceCountMultiplier, 0.1, 10)
	if countMultChanged then
		self.instanceCountMultiplier = countMult
	end
end

return scatteredGroup