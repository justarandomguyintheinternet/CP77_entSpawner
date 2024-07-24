local entity = require("modules/classes/spawn/entity/entity")

---Class for entity templates
local template = setmetatable({}, { __index = entity })

function template:new()
	local o = entity.new(self)

    o.dataType = "Entity Template"
    o.spawnDataPath = "data/spawnables/entity/templates/"
    o.node = "worldEntityNode"
    o.description = "Spawns an entity from a given .ent file"

    o.modulePath = "entity/entityTemplate"

    setmetatable(o, { __index = self })
   	return o
end

return template