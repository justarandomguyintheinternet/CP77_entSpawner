local area = require("modules/classes/spawn/area/area")

---Class for worldPreventionFreeAreaNode
---@class preventionFree : area
local preventionFree = setmetatable({}, { __index = area })

function preventionFree:new()
	local o = area.new(self)

    o.spawnListType = "files"
    o.dataType = "Prevention Free Area"
    o.spawnDataPath = "data/spawnables/area/preventionFree/"
    o.modulePath = "area/preventionFree"
    o.node = "worldPreventionFreeAreaNode"
    o.description = "Prevents police from entering the area. Does not clear wanted level."
    o.previewNote = "Does not work in the editor."
    o.icon = IconGlyphs.PoliceBadgeOutline

    setmetatable(o, { __index = self })
   	return o
end

function preventionFree:export()
    local data = area.export(self)
    data.type = "worldPreventionFreeAreaNode"

    return data
end

return preventionFree