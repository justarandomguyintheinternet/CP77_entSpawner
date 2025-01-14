local area = require("modules/classes/spawn/area/area")

---Class for gameKillTriggerNode
---@class kill : area
local kill = setmetatable({}, { __index = area })

function kill:new()
	local o = area.new(self)

    o.spawnListType = "files"
    o.dataType = "Kill Area"
    o.spawnDataPath = "data/spawnables/area/kill/"
    o.modulePath = "area/killArea"
    o.node = "gameKillTriggerNode"
    o.description = "Instantly kills the player when inside the area."
    o.previewNote = "Does not kill the player in the editor."
    o.icon = IconGlyphs.SkullCrossbonesOutline

    setmetatable(o, { __index = self })
   	return o
end

function kill:export()
    local data = area.export(self)
    data.type = "gameKillTriggerNode"

    return data
end

return kill