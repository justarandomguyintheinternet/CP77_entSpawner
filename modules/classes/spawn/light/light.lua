local spawnable = require("modules/classes/spawn/spawnable")
local light = setmetatable({}, { __index = spawnable })

function light:new(position, rotation)
	local o = spawnable.new(self, position, rotation)

    o.boxColor = {255, 255, 0}
    o.spawnListType = "files"
    o.dataType = "light"
    o.spawnDataPath = "data/spawnables/lights/"

    setmetatable(o, { __index = self })
   	return o
end

function light:despawn()

end

function light:updatePosition()

end

function light:drawUI()
    -- Change color / strength
end

return light