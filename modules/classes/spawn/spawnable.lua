local utils = require("modules/utils/utils")

spawnable = {}

function spawnable:new(position, rotation)
	local o = {}

    o.dataType = "spawnable"
    o.spawnListType = "list"
    o.spawnListPath = "data/spawnables/entity/templates/"

    o.position = position
    o.rotation = rotation

	self.__index = self
   	return setmetatable(o, self)
end

function spawnable:spawn()

end

function spawnable:despawn()

end

function spawnable:update()

end

function spawnable:generateName(name) -- Generate valid name from given name / path
    if string.find(name, "\\") then
        name = name:match("\\[^\\]*$") -- Everything after last \
    end
    name = name:gsub(".ent", ""):gsub("\\", "_") -- Remove .ent, replace \ by _
    return utils.createFileName(name)
end

function spawnable:save()

end

function spawnable:draw()

end

function spawnable:drawSpawnOptions()

end

---Load from saved data
---@param data table
function spawnable:load(data)
    self.position = ToVector4(data.position)
    self.rotation = ToEulerAngles(data.rotation)
end

---Load and store data for when being spawned by user
---@param data table
function spawnable:loadSpawnData(data)
    for key, value in pairs(data) do
        self[key] = value
    end
end

return spawnable