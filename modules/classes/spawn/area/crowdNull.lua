local area = require("modules/classes/spawn/area/area")

---Class for worldCrowdNullAreaNode
---@class crowdNull : area
local crowdNull = setmetatable({}, { __index = area })

function crowdNull:new()
	local o = area.new(self)

    o.spawnListType = "files"
    o.dataType = "Crowd Null Area"
    o.spawnDataPath = "data/spawnables/area/crowdNull/"
    o.modulePath = "area/crowdNull"
    o.node = "worldCrowdNullAreaNode"
    o.description = "Prevents crowds from spawning in the area."
    o.previewNote = "Does not work in the editor."
    o.icon = IconGlyphs.AccountMultipleMinusOutline

    setmetatable(o, { __index = self })
   	return o
end

function crowdNull:export()
    local data = area.export(self)
    data.type = "worldCrowdNullAreaNode"

    return data
end

return crowdNull