local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")

local positionableGroup = require("modules/classes/editor/positionableGroup")

---Class scattered positionable group
---@class scatteredGroup : positionableGroup
---@field seed number
---@field snapToGround boolean
---@field baseGroup positionableGroup
---@field instanceGroup positionableGroup
local scatteredGroup = setmetatable({}, { __index = positionableGroup })

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

	setmetatable(o, { __index = self })
   	return o
end

function scatteredGroup:load(data, silent)
	positionableGroup.load(self, data, silent)

	self.seed = data.seed
	self.snapToGround = data.snapToGround or false
	if self.seed == -1 then
		self:reSeed()
	end

	local hasBase, hasInstances = false, false
	for _, child in ipairs(self.childs) do
		if child.name == "Base" then
			hasBase = true
			o.baseGroup = child
		elseif child.name == "Instances" then
			hasInstances = true
			o.instanceGroup = child
		end
	end

	if not hasBase then
		o.baseGroup = positionableGroup:new(self.sUI)
		o.baseGroup.name = "Base"
		o.baseGroup:setParent(self)
	end

	if not hasInstances then
		o.instanceGroup = positionableGroup:new(self.sUI)
		o.instanceGroup.name = "Instances"
		o.instanceGroup:setParent(self)
	end
end

function scatteredGroup:applyRandomization()
	self.lastPos = self:getPosition()
	while self.instanceGroup.childs[1] do
		self.instanceGroup.childs[1]:remove()
	end

	print("removed children")
	math.randomseed(self.seed)
	print("set seed to " .. self.seed)
	for ic, child in ipairs(self.baseGroup.childs) do
		print("Applying config element " .. ic .. " / " .. child.modulePath)
		if not child.scatterConfig then
			print("No scatter config, skipping")
			goto continue
		end
		local elementCount = math.random(child.scatterConfig.count.min, child.scatterConfig.count.max)
		print("Spawning " .. elementCount .. " elements")
		for i = 1, elementCount do
			print("Spawning element " .. i)

			local newObjSerialized = child:serialize()
			newObjSerialized.visible = true
			newObjSerialized.hiddenByParent = false
			local newObj = require(child.modulePath):new(self.sUI)
			newObj:load(newObjSerialized, true)

			print("Deepcopied base object")

			local position = Vector4.new((math.random(child.scatterConfig.position.x.min, child.scatterConfig.position.x.max) + self.lastPos.x or 0),
			(math.random(child.scatterConfig.position.y.min, child.scatterConfig.position.y.max) + self.lastPos.y or 0),
			(math.random(child.scatterConfig.position.z.min, child.scatterConfig.position.z.max) + self.lastPos.z or 0), 1)
			newObj:setPosition(position)

			print("Set position")

			local rotation = EulerAngles.new(math.random(child.scatterConfig.rotation.x.min, child.scatterConfig.rotation.x.max),
			math.random(child.scatterConfig.rotation.y.min, child.scatterConfig.rotation.y.max),
			math.random(child.scatterConfig.rotation.z.min, child.scatterConfig.rotation.z.max))
			newObj:setRotation(rotation)

			print("Set rotation")

			local scale = { x = math.random(child.scatterConfig.scale.x.min, child.scatterConfig.scale.x.max),
			y = math.random(child.scatterConfig.scale.y.min, child.scatterConfig.scale.y.max),
			z = math.random(child.scatterConfig.scale.z.min, child.scatterConfig.scale.z.max) }
			newObj:setScale(scale, true)

			print("Set scale")
			newObj:setSilent(false)
			newObj:setVisible(true, true)
			newObj:setParent(self.instanceGroup)
			print("Added child")
		end
		::continue::
	end
	
	print("Finished applying randomization")
	if self.snapToGround then
		self:dropToSurface(Vector4.new(0, 0, -1, 0))
	end
end

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

function scatteredGroup:reSeed()
	self.seed = math.random(0, 999999999)
	self:applyRandomization()

	for _, child in pairs(self.childs) do
		if utils.isA(child, "scatteredGroup") or utils.isA(child, "randomizedGroup") then
			child:reSeed()
		end
	end
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
end

function scatteredGroup:serialize()
	local data = positionableGroup.serialize(self)

	data.seed = self.seed
	data.snapToGround = self.snapToGround

	return data
end

return scatteredGroup