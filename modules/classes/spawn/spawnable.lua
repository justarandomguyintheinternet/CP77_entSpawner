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
    local spec = DynamicEntitySpec.new()
    spec.templatePath = ResRef.FromString(self.spawnData)
    spec.position = self.position
    spec.orientation = self.rotation:ToQuat()
    spec.alwaysSpawned = true
    self.entityID = Game.GetDynamicEntitySystem():CreateEntity(spec)
end

function spawnable:isSpawned()
    if Game.GetDynamicEntitySystem():GetEntity(self.entityID) == nil then
        return false
    end

    return true
end

function spawnable:despawn()
    Game.GetDynamicEntitySystem():DeleteEntity(self.entityID)
end

function spawnable:update()
    if not self:isSpawned() then return end

    local handle = Game.FindEntityByID(self.entityID)
    if not handle then
        self:despawn()
        self:spawn()
    else
        Game.GetTeleportationFacility():Teleport(Game.GetDynamicEntitySystem():GetEntity(self.entityID), self.position,  self.rotation)
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