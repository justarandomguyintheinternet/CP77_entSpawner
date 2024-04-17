local utils = require("modules/utils/utils")

spawnable = {}

function spawnable:new()
	local o = {}

    o.dataType = "spawnable"
    o.spawnListType = "list"
    o.spawnListPath = "data/spawnables/entity/templates/"

	self.__index = self
   	return setmetatable(o, self)
end

function spawnable:spawn()

end

function spawnable:despawn()

end

function spawnable:update()

end

function spawnable:generateNameFromPath(path) -- Generate valid name from path or if no path given current name
    local text = path or self.name
    if string.find(self.name, "\\") then
        self.name = text:match("\\[^\\]*$") -- Everything after last \
    end
    self.name = self.name:gsub(".ent", ""):gsub("\\", "_") -- Remove .ent, replace \ by _
    self.name = utils.createFileName(self.name)
end

function spawnable:save()

end

function spawnable:draw()

end

function spawnable:drawSpawnOptions()

end

function spawnable:load(data)
    self.name = data.name
end

function spawnable:verifyMove(to)
	local allowed = true

	if to == self.parent then
		allowed = false
	end

	return allowed
end

function spawnable:getOwnPath(first)
    if self.parent == nil then
        if first then
            return "-- No group --"
        else
            return self.name
        end
    else
        if first then
            return self.parent:getOwnPath()
        else
            return tostring(self.parent:getOwnPath() .. "/" .. self.name)
        end
    end
end

return spawnable