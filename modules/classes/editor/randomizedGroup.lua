local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local Cron = require("modules/utils/Cron")

local positionableGroup = require("modules/classes/editor/positionableGroup")

---Class randomized positionable group
---@class randomizedGroup : positionableGroup
---@field seed number
---@field randomizationRule numbe
---@field fixedAmountRule number
---@field fixedAmountPercentage number
---@field fixedAmountTotal number
---@field maxPropertyWidth number?
---@field blockRandomization boolean
---@field queueRandomize boolean
local randomizedGroup = setmetatable({}, { __index = positionableGroup })

function randomizedGroup:new(sUI)
	local o = positionableGroup.new(self, sUI)

	o.modulePath = "modules/classes/editor/randomizedGroup"

	o.class = utils.combine(o.class, { "randomizedGroup" })
	o.quickOperations = {}
	o.icon = IconGlyphs.Dice5Outline
	o.supportsSaving = false

	o.seed = 1
	o.randomizationRule = 0
	o.fixedAmountRule = 0
	o.fixedAmountPercentage = 0.5
	o.fixedAmountTotal = 1

	o.maxPropertyWidth = nil
	o.blockRandomization = false
	o.queueRandomize = false

	setmetatable(o, { __index = self })
   	return o
end

function randomizedGroup:load(data, silent)
	self.blockRandomization = true
	positionableGroup.load(self, data, silent)
	self.blockRandomization = false

	self.seed = data.seed
	self.randomizationRule = data.randomizationRule
	self.fixedAmountRule = data.fixedAmountRule
	self.fixedAmountPercentage = data.fixedAmountPercentage
	self.fixedAmountTotal = data.fixedAmountTotal

	if self.seed == -1 then
		self:reSeed()
	end
end

--https://stackoverflow.com/questions/35572435/how-do-you-do-the-fisher-yates-shuffle-in-lua
local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

function randomizedGroup:showNChildren(amount)
	local shown = {}
	local hidden = {}

	for _, child in pairs(self.childs) do
		if math.random() < child.randomizationSettings.probability then
			table.insert(shown, {
				child = child,
				probability = child.randomizationSettings.probability
			})
		else
			table.insert(hidden, {
				child = child,
				probability = child.randomizationSettings.probability
			})
		end
	end

	shuffle(shown)
	shuffle(hidden)

	table.sort(shown, function (a, b)
		return a.probability > b.probability
	end)
	table.sort(hidden, function (a, b)
		return a.probability > b.probability
	end)

	utils.combine(shown, hidden)

	for _, entry in ipairs(shown) do
		if amount > 0 then
			if utils.isA(entry.child, "spawnableElement") then
				entry.child:updateRandomization()
			end
			entry.child:setVisible(true, true)
			amount = amount - 1
		else
			entry.child:setVisible(false, true)
		end
	end
end

function randomizedGroup:applyRandomization(apply)
	if self.blockRandomization or self.queueRandomize or not apply then return end

	self.queueRandomize = true

	Cron.NextTick(function ()
		self.queueRandomize = false
		math.randomseed(self.seed)

		if self.randomizationRule == 0 then
			for _, child in pairs(self.childs) do
				if math.random() < child.randomizationSettings.probability then
					child:setVisible(true, true)
				else
					child:setVisible(false, true)
				end
			end
		else
			if self.fixedAmountRule == 0 then
				self:showNChildren(math.floor(self.fixedAmountPercentage * #self.childs))
			else
				self:showNChildren(self.fixedAmountTotal)
			end
		end
	end)
end

function randomizedGroup:remove()
	self.blockRandomization = true

	positionableGroup.remove(self)
end

function randomizedGroup:addChild(new, index)
	positionableGroup.addChild(self, new, index)

	self:applyRandomization(true)
end

function randomizedGroup:removeChild(child)
	positionableGroup.removeChild(self, child)

	self:applyRandomization(true)
end

function randomizedGroup:getProperties()
	local properties = positionableGroup.getProperties(self)

	table.insert(properties, {
		id = "randomizationGroup",
		name = "Group Randomization",
		defaultHeader = false,
		draw = function ()
			self:drawGroupRandomization()
		end
	})

	return properties
end

function randomizedGroup:reSeed()
	self.seed = math.random(0, 999999999)
	self:applyRandomization(true)

	for _, child in pairs(self.childs) do
		if utils.isA(child, "randomizedGroup") then
			child:reSeed()
		end
	end
end

function randomizedGroup:drawGroupRandomization()
	if not self.maxPropertyWidth then
		self.maxPropertyWidth = utils.getTextMaxWidth({ "Seed", "Randomization Rule", "Fixed Amount Rule", "Fixed Amount %", "Fixed Amount Total" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
	end

	style.mutedText("Seed")
	ImGui.SameLine()
	ImGui.SetCursorPosX(self.maxPropertyWidth)
	self.seed, _, finished = style.trackedIntInput(self, "##seed", self.seed, 0, 9999999999)
	self:applyRandomization(finished)

	ImGui.SameLine()
	style.pushButtonNoBG(true)
	if ImGui.Button(IconGlyphs.Reload) then
		history.addAction(history.getElementChange(self))
		self:reSeed()
	end
	style.pushButtonNoBG(false)

	style.mutedText("Randomization Rule")
	ImGui.SameLine()
	ImGui.SetCursorPosX(self.maxPropertyWidth)
	self.randomizationRule, changed = style.trackedCombo(self, "##randomizationRule", self.randomizationRule, { "Per Object", "Fixed" })
	self:applyRandomization(changed)
	style.tooltip("Per Object: For each object, use the probability defined per object.\nFixed: Spawn a fixed amount, taking per object probabilies into account.")

	if self.randomizationRule == 1 then
		style.mutedText("Fixed Amount Rule")
		ImGui.SameLine()
		ImGui.SetCursorPosX(self.maxPropertyWidth)
		self.fixedAmountRule, changed = style.trackedCombo(self, "##randomizationRuleFixed", self.fixedAmountRule, { "Percentage", "Total" })
		self:applyRandomization(changed)
		style.tooltip("Percentage: Spawn a fixed percantage of the objects.\nTotal: Spawn a fixed total amount of objects.")

		if self.fixedAmountRule == 0 then
			style.mutedText("Fixed Amount %")
			ImGui.SameLine()
			ImGui.SetCursorPosX(self.maxPropertyWidth)
			local value, changed, finished = style.trackedDragFloat(self, "##fixedAmountPercentage", self.fixedAmountPercentage * 100, 0.1, 0, 100, "%.2f%%")
			self:applyRandomization(finished)
			if changed then
				self.fixedAmountPercentage = value / 100
			end
		else
			style.mutedText("Fixed Amount Total")
			ImGui.SameLine()
			ImGui.SetCursorPosX(self.maxPropertyWidth)
			self.fixedAmountTotal, _, finished = style.trackedIntInput(self, "##fixedAmountTotal", self.fixedAmountTotal, 0, 9999999999)
			self:applyRandomization(finished)
		end
	end
end

function randomizedGroup:serialize()
	local data = positionableGroup.serialize(self)

	data.seed = self.seed
	data.randomizationRule = self.randomizationRule
	data.fixedAmountRule = self.fixedAmountRule
	data.fixedAmountPercentage = self.fixedAmountPercentage
	data.fixedAmountTotal = self.fixedAmountTotal

	return data
end

return randomizedGroup

-- spawnableElement controls:
	-- randomize app (what apps)
	-- randmize rotation (axis)
	-- randmoized position offset (axis)
	-- probability of spawning
-- group controls:
	-- seed
	-- distributaion type:
		-- fixed amount of things that shall spawn, or range
			-- either as total amount, or percentage
		-- default, each element is determined by its probability