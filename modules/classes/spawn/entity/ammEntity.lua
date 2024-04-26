local entity = require("modules/classes/spawn/entity/entity")
local amm = setmetatable({}, { __index = entity })

function amm:new()
	local o = entity.new(self)

    o.dataType = "Entity Template (AMM)"
    o.spawnDataPath = "data/spawnables/entity/amm/"
    o.spawnListType = "files"

    o.modulePath = "entity/ammEntity"

    setmetatable(o, { __index = self })
   	return o
end

return amm