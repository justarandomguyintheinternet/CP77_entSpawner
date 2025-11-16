local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local scatteredElement = require("modules/classes/editor/scatteredConfigElement")

local positionableGroup = require("modules/classes/editor/positionableGroup")

---Class scattered positionable group
---@class scatteredGroup : positionableGroup
---@field seed number
---@field itemRandomizationConfig table<scatteredConfigElement>
---@field snapToGround boolean
---@field positionable positionable
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
    o.itemRandomizationConfig = {}
    o.scaleSpread = 1

	o.lastPos = nil

	o.maxPropertyWidth = nil

	setmetatable(o, { __index = self })
   	return o
end

function scatteredGroup:load(data, silent)
	positionableGroup.load(self, data, silent)

	self.seed = data.seed
	self.snapToGround = data.snapToGround or false
    for _, configData in ipairs(data.itemRandomizationConfig or {}) do
		local configElement = scatteredElement:new(self, self.sUI)
		configElement:load(configData, silent)
		table.insert(self.itemRandomizationConfig, configElement)
	end
    self.scaleSpread = data.scaleSpread or 1

	if self.seed == -1 then
		self:reSeed()
	end
end

function scatteredGroup:addNewConfigElement(element)
	print("Adding new config element")
	self.lastPos = self:getPosition()
	history.addAction(history.getElementChange(self))
	element.spawnable:despawn()
	element.hiddenByParent = true
	element.visible = false
	element.childs = {}
	local newConfigElement = scatteredElement:new(self, self.sUI)
	newConfigElement.baseObj = element
	
	self:removeChild(element)

	table.insert(self.itemRandomizationConfig, newConfigElement)
	print(#self.itemRandomizationConfig)
end

function scatteredGroup:removeConfigElement(configElement)
	history.addAction(history.getElementChange(self))
	for i, element in ipairs(self.itemRandomizationConfig) do
		if element == configElement then
			table.remove(self.itemRandomizationConfig, i)
			return
		end
	end
end

function scatteredGroup:applyRandomization()
	-- if true then return end
	while self.childs[1] do
		self.childs[1]:remove()
	end
	print("removed children")
	math.randomseed(self.seed)
	print("set seed to " .. self.seed)
	for ic, configElement in ipairs(self.itemRandomizationConfig) do
		print("Applying config element " .. ic)
		local elementCount = math.random(configElement.count.min, configElement.count.max)
		print("Spawning " .. elementCount .. " elements")
		for i = 1, elementCount do
			print("Spawning element " .. i)
			print("Config Element Base Obj: " .. configElement.baseObj.modulePath)
			local newObjSerialized = configElement.baseObj:serialize()
			newObjSerialized.visible = true
			newObjSerialized.hiddenByParent = false
			local newObj = require(configElement.baseObj.modulePath):new(self.sUI)
			newObj:load(newObjSerialized, true)

			print("Deepcopied base object")

			local position = Vector4.new((math.random(configElement.position.x.min, configElement.position.x.max) + self.lastPos.x or 0),
			(math.random(configElement.position.y.min, configElement.position.y.max) + self.lastPos.y or 0),
			(math.random(configElement.position.z.min, configElement.position.z.max) + self.lastPos.z or 0), 1)
			newObj:setPosition(position)

			print("Set position")

			local rotation = EulerAngles.new(math.random(configElement.rotation.x.min, configElement.rotation.x.max),
			math.random(configElement.rotation.y.min, configElement.rotation.y.max),
			math.random(configElement.rotation.z.min, configElement.rotation.z.max))
			newObj:setRotation(rotation)

			print("Set rotation")

			local scale = { x = math.random(configElement.scale.x.min, configElement.scale.x.max),
			y = math.random(configElement.scale.y.min, configElement.scale.y.max),
			z = math.random(configElement.scale.z.min, configElement.scale.z.max) }
			newObj:setScale(scale, true)

			print("Set scale")
			newObj:setSilent(false)
			newObj:setVisible(true, true)
			self:addChild(newObj)
			print("Added child")
		end
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
	style.spacedSeparator()
	style.styledText("Config Elements")
	for _, configElement in ipairs(self.itemRandomizationConfig) do
		ImGui.Separator()
		configElement:draw()
	end
	if ImGui.Button("Add New Config Element") then
		history.addAction(history.getElementChange(self))
		local newConfigElement = scatteredElement:new(self, self.sUI)
		table.insert(self.itemRandomizationConfig, newConfigElement)
	end
end

function scatteredGroup:serialize()
	local data = positionableGroup.serialize(self)

	data.seed = self.seed
	data.snapToGround = self.snapToGround
    data.itemRandomizationConfig = {}
	for _, configElement in ipairs(self.itemRandomizationConfig) do
		table.insert(data.itemRandomizationConfig, configElement:serialize())
	end
    data.scaleSpread = self.scaleSpread

	return data
end

return scatteredGroup