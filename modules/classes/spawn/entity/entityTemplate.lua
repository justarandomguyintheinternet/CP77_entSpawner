local entity = require("modules/classes/spawn/entity/entity")
local template = setmetatable({}, { __index = entity })

function template:new(position, rotation)
	local o = entity.new(self, position, rotation)

    o.dataType = "entityTemplate"
    o.spawnDataPath = "data/spawnables/entity/templates/"

    setmetatable(o, { __index = self })
   	return o
end

function template:spawn()

end

return template