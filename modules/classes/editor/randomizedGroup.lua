local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")

local positionableGroup = require("modules/classes/editor/positionableGroup")

---Class randomized positionable group
---@class randomizedGroup : positionableGroup
---@field seed number
---@field randomizationRule numbe
---@field fixedAmountRule number
---@field fixedAmountPercentage number
---@field fixedAmountTotal number
local randomizedGroup = setmetatable({}, { __index = positionableGroup })

function randomizedGroup:new(sUI)
	local o = positionableGroup.new(self, sUI)

	o.modulePath = "modules/classes/editor/randomizedGroup"

	o.class = utils.combine(o.class, { "randomizedGroup" })
	o.quickOperations = {}
	o.icon = IconGlyphs.Dice5Outline
	o.supportsSaving = false

	o.seed = 0
	o.randomizationRule = 0
	o.fixedAmountRule = 0
	o.fixedAmountPercentage = 0.5
	o.fixedAmountTotal = 1

	setmetatable(o, { __index = self })
   	return o
end

function randomizedGroup:load(data, silent)
	positionableGroup.load(self, data, true)

	self.seed = data.seed
	self.randomizationRule = data.randomizationRule
	self.fixedAmountRule = data.fixedAmountRule
	self.fixedAmountPercentage = data.fixedAmountPercentage
	self.fixedAmountTotal = data.fixedAmountTotal
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

function randomizedGroup:drawGroupRandomization()
	style.mutedText("Seed")
	ImGui.SameLine()
	self.seed, _, finished = style.trackedIntInput(self, "##seed", self.seed, 0, 9999999999)
	ImGui.SameLine()
	style.pushButtonNoBG(true)
	if ImGui.Button(IconGlyphs.Reload) then
		history.addAction(history.getElementChange(self))
		self.seed = math.random(0, 999999999)
	end
	style.pushButtonNoBG(false)

	style.mutedText("Randomization Rule")
	ImGui.SameLine()
	self.randomizationRule, changed = style.trackedCombo(self, "##randomizationRule", self.randomizationRule, { "Per Object", "Fixed" })
	style.tooltip("Per Object: For each object, use the probability defined per object.\nFixed: Spawn a fixed amount, taking per object probabilies into account.")

	if self.randomizationRule == 1 then
		style.mutedText("Fixed Amount Rule")
		ImGui.SameLine()
		self.fixedAmountRule, changed = style.trackedCombo(self, "##randomizationRuleFixed", self.fixedAmountRule, { "Percentage", "Total" })
		style.tooltip("Percentage: Spawn a fixed percantage of the objects.\nTotal: Spawn a fixed total amount of objects.")

		if self.fixedAmountRule == 0 then
			style.mutedText("Fixed Amount Percentage")
			ImGui.SameLine()
			local value, changed, finished = style.trackedDragFloat(self, "##fixedAmountPercentage", self.fixedAmountPercentage * 100, 0.1, 0, 100, "%.2f%%")
			if changed then
				self.fixedAmountPercentage = value / 100
			end
		else
			style.mutedText("Fixed Amount Total")
			ImGui.SameLine()
			self.fixedAmountTotal, _, finished = style.trackedIntInput(self, "##fixedAmountTotal", self.fixedAmountTotal, 0, 9999999999)
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