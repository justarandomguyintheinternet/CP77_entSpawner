local entity = require("modules/classes/spawn/entity/entity")

---Class for entity records spawned via worldPopulationSpawnerNode
local record = setmetatable({}, { __index = entity })

function record:new()
	local o = entity.new(self)

    o.dataType = "Entity Record"
    o.spawnDataPath = "data/spawnables/entity/records/"
    o.modulePath = "entity/entityRecord"

    setmetatable(o, { __index = self })
   	return o
end

function record:spawn()
    local spec = DynamicEntitySpec.new()
    spec.recordID = self.spawnData
    spec.position = self.position
    spec.orientation = self.rotation:ToQuat()
    spec.alwaysSpawned = true
    self.entityID = Game.GetDynamicEntitySystem():CreateEntity(spec)
    self.spawned = true
end

function record:despawn()
    Game.GetDynamicEntitySystem():DeleteEntity(self.entityID)
    self.spawned = false
end

function record:update()
    if not self:isSpawned() then return end

    local handle = Game.FindEntityByID(self.entityID)
    if not handle then
        self:despawn()
        self:spawn()
    else
        Game.GetTeleportationFacility():Teleport(handle, self.position,  self.rotation)
    end
end

function record:export()
    local data = spawnable.export(self)
    data.type = "worldPopulationSpawnerNode"
    data.data = {
        objectRecordId = {
            ["$storage"] = "string",
            ["$value"] = self.spawnData
        }
    }

    return data
end

return record