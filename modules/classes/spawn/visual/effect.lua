local spawnable = require("modules/classes/spawn/spawnable")

---Class for worldEffectNode
---@class effect : spawnable
local effect = setmetatable({}, { __index = spawnable })

function effect:new()
	local o = spawnable.new(self)

    o.spawnListType = "list"
    o.dataType = "Effects"
    o.spawnDataPath = "data/spawnables/visual/effects/"
    o.modulePath = "visual/effect"

    setmetatable(o, { __index = self })
   	return o
end

function effect:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    local comp = entEffectSpawnerComponent.new()
end

function effect:spawn()
    local effect = self.spawnData
    self.spawnData = "base\\spawner\\empty_entity.ent"

    spawnable.spawn(self)
    self.spawnData = effect
end

function effect:export()
    local data = spawnable.export(self)
    data.type = "worldEffectNode"
    data.data = {
        streamingDistanceOverride = -1,
        effect = {
            DepotPath = {
                ["$storage"] = "string",
                ["$value"] = self.spawnData
            }
        }
    }

    return data
end

return particle