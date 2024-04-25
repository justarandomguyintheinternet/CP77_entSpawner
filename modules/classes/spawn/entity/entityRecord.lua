local entity = require("modules/classes/spawn/entity/entity")
local record = setmetatable({}, { __index = entity })

function record:new()
	local o = entity.new(self)

    o.dataType = "Entity Record"
    o.spawnDataPath = "data/spawnables/entity/records/"
    o.modulePath = "entity/entityRecord"

    setmetatable(o, { __index = self })
   	return o
end

return record