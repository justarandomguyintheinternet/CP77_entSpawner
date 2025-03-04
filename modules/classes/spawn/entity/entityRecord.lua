local entity = require("modules/classes/spawn/entity/entity")
local builder = require("modules/utils/entityBuilder")
local utils = require("modules/utils/utils")
local cache = require("modules/utils/cache")
local spawnable = require("modules/classes/spawn/spawnable")
local style = require("modules/ui/style")

---Class for entity records spawned via worldPopulationSpawnerNode
---@class record : entity
---@field public spawnOnStart boolean
local record = setmetatable({}, { __index = entity })

function record:new()
	local o = entity.new(self)

    o.dataType = "Entity Record"
    o.spawnDataPath = "data/spawnables/entity/records/"
    o.modulePath = "entity/entityRecord"
    o.icon = IconGlyphs.AlphaRBoxOutline
    o.node = "worldPopulationSpawnerNode"
    o.description = "Spawns an entity from a given TweakDB record"

    o.assetPreviewType = "none"

    o.spawnOnStart = true

    setmetatable(o, { __index = self })
   	return o
end

function record:loadSpawnData(data, position, rotation)
    spawnable.loadSpawnData(self, data, position, rotation)
    local resRef = ResRef.FromHash(TweakDB:GetFlat(self.spawnData .. ".entityTemplatePath").hash)

    cache.tryGet(self.spawnData .. "_apps")
    .notFound(function (task)
        builder.registerLoadResource(resRef, function (resource)
            local apps = {}

            for _, appearance in ipairs(resource.appearances) do
                table.insert(apps, appearance.name.value)
            end

            cache.addValue(self.spawnData .. "_apps", apps)
            task:taskCompleted()
        end)
    end)
    .found(function ()
        self.apps = cache.getValue(self.spawnData .. "_apps")
        self.appIndex = math.max(utils.indexValue(self.apps, self.app) - 1, 0)
    end)
end

function record:save()
    local data = entity.save(self)
    data.spawnOnStart = self.spawnOnStart
    if data.spawnOnStart == nil then data.spawnOnStart = true end

    return data
end

function record:spawn()
    if self:isSpawned() or self.spawning then return end

    local spec = DynamicEntitySpec.new()
    spec.recordID = self.spawnData
    spec.position = self.position
    spec.orientation = self.rotation:ToQuat()
    spec.alwaysSpawned = true
    spec.appearanceName = self.app
    self.entityID = Game.GetDynamicEntitySystem():CreateEntity(spec)
    self.spawning = true

    builder.registerAssembleCallback(self.entityID, function (entity)
        self:onAssemble(entity)
    end)

    builder.registerAttachCallback(self.entityID, function (entity)
        self:onAttached(entity)
    end)
end

function record:despawn()
    if self.spawning then return end

    Game.GetDynamicEntitySystem():DeleteEntity(self.entityID)
    self.spawned = false
end

function record:update()
    if not self:isSpawned() then return end

    local handle = self:getEntity()
    if not handle then return end

    if handle:GetClassName().value == "NPCPuppet" then
        local cmd = AITeleportCommand.new()
        cmd.position = self.position
        cmd.rotation = self.rotation.yaw
        cmd.doNavTest = false

        handle:GetAIControllerComponent():SendCommand(cmd)
    else
        Game.GetTeleportationFacility():Teleport(handle, self.position,  self.rotation)
    end
end

---@return entEntity?
function record:getEntity()
    return Game.GetDynamicEntitySystem():GetEntity(self.entityID)
end

function record:draw()
    entity.draw(self)

    self.spawnOnStart, _ = style.trackedCheckbox(self.object, "Spawn on start", self.spawnOnStart)
end

function record:export()
    local data = spawnable.export(self)
    data.type = "worldPopulationSpawnerNode"
    data.data = {
        appearanceName = {
            ["$storage"] = "string",
            ["$value"] = self.app
        },
        objectRecordId = {
            ["$storage"] = "string",
            ["$value"] = self.spawnData
        },
        spawnOnStart = self.spawnOnStart and 1 or 0
    }

    return data
end

return record