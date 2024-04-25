local spawnable = require("modules/classes/spawn/spawnable")
local entity = setmetatable({}, { __index = spawnable })

function entity:new()
	local o = spawnable.new(self)

    o.boxColor = {255, 255, 0}
    o.spawnListType = "list"
    o.dataType = "Entity"
    o.modulePath = "entity/entity"

    o.spawnData = ""

    setmetatable(o, { __index = self })
   	return o
end

function entity:drawUI()
    -- Copy path / recordID
end

function entity:loadSpawnData(data, position, rotation)
    self.spawnData = data -- Just a simple string

    self.position = position
    self.rotation = rotation
end

return entity