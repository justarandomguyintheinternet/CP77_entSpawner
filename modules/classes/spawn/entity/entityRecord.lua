local entity = require("modules/classes/spawn/entity/entity")
local record = setmetatable({}, { __index = entity })

function record:new()
	local o = entity.new(self)

    o.dataType = "entityRecord"
    o.spawnDataPath = "data/spawnables/entity/records/"

    setmetatable(o, { __index = self })
   	return o
end

function record:spawn()

end

return record