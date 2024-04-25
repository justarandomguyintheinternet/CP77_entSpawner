local utils = require("modules/utils/utils")

spawnable = {}

function spawnable:new()
	local o = {}

    o.dataType = "Spawnable"
    o.spawnListType = "list"
    o.spawnListPath = "data/spawnables/entity/templates/"
    o.modulePath = "spawnable"
    o.boxColor = {255, 0, 0}

    o.spawnData = "base\\fallback\\helper_no_entity.ent"

    o.position = Vector4.new(0, 0, 0, 0)
    o.rotation = EulerAngles.new(0, 0, 0)
    o.entityID = entEntityID.new({hash = 0})

	self.__index = self
   	return setmetatable(o, self)
end

function spawnable:spawn()
    local transform = WorldTransform.new()
    transform:SetOrientation(self.rotation:ToQuat())
    transform:SetPosition(self.position)
    self.entityID = exEntitySpawner.Spawn(self.spawnData, transform, self.app)
end

function spawnable:isSpawned()
    if Game.FindEntityByID(self.entityID) == nil then
        return false
    end

    return true
end

function spawnable:despawn()
    if not self:isSpawned() then return end

    Game.FindEntityByID(self.entityID):GetEntity():Destroy()
end

function spawnable:update()
    if not self:isSpawned() then return end

    local tpSuccess = pcall(function ()
        Game.GetTeleportationFacility():Teleport(Game.FindEntityByID(self.entityID), self.position,  self.rotation)
    end)
    if not tpSuccess then
        self:despawn()
        self:spawn()
    end
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

---Load data blob, position and rotation for spawning
---@param data table
function spawnable:loadSpawnData(data, position, rotation)
    for key, value in pairs(data) do
        self[key] = value
    end

    self.position = position
    self.rotation = rotation
end

return spawnable