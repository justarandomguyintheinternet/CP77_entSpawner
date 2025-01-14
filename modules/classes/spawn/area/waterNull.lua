local area = require("modules/classes/spawn/area/area")

---Class for worldWaterNullAreaNode
---@class waterNull : area
local waterNull = setmetatable({}, { __index = area })

function waterNull:new()
	local o = area.new(self)

    o.spawnListType = "files"
    o.dataType = "Water Null Area"
    o.spawnDataPath = "data/spawnables/area/waterNull/"
    o.modulePath = "area/waterNull"
    o.node = "worldWaterNullAreaNode"
    o.description = "Removes the underwater effect, and swimmability from the area. Does not remove the water mesh."
    o.previewNote = "Does not work in the editor."
    o.icon = IconGlyphs.WaterOff

    setmetatable(o, { __index = self })
   	return o
end

function waterNull:export()
    local data = area.export(self)
    data.type = "worldWaterNullAreaNode"

    return data
end

return waterNull