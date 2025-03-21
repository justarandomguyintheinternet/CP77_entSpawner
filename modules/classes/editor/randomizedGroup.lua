local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")

local positionableGroup = require("modules/classes/editor/positionableGroup")

---Class randomized positionable group
---@class randomizedGroup : positionableGroup
local randomizedGroup = setmetatable({}, { __index = positionableGroup })

function randomizedGroup:new(sUI)
	local o = positionableGroup.new(self, sUI)

	o.modulePath = "modules/classes/editor/randomizedGroup"

	o.class = utils.combine(o.class, { "randomizedGroup" })
	o.quickOperations = {}
	o.icon = IconGlyphs.Dice5Outline

	o.seed = 0

	setmetatable(o, { __index = self })
   	return o
end

function randomizedGroup:load(data, silent)
	positionableGroup.load(self, data, true)
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