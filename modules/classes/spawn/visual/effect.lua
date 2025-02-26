local visualized = require("modules/classes/spawn/visualized")
local Cron = require("modules/utils/Cron")

---Class for worldEffectNode
---@class effect : visualized
---@field private disableCron integer
local effect = setmetatable({}, { __index = visualized })

function effect:new()
	local o = visualized.new(self)

    o.spawnListType = "list"
    o.dataType = "Effects"
    o.spawnDataPath = "data/spawnables/visual/effects/"
    o.modulePath = "visual/effect"
    o.node = "worldEffectNode"
    o.description = "Plays an effect, from a given .effect file"
    o.icon = IconGlyphs.Creation

    o.previewColor = "brown"
    o.assetPreviewType = "position"
    o.assetPreviewDelay = 0.1

    o.disableCron = nil

    setmetatable(o, { __index = self })
   	return o
end

function effect:onAssemble(entity)
    visualized.onAssemble(self, entity)

    local component = entEffectSpawnerComponent.new()
    component.name = "effect"
    local effect = entEffectDesc.new()
    effect.effect = self.spawnData
    effect.effectName = "effect"
    component.effectDescs = { effect }

    entity:AddComponent(component)

    GameObjectEffectHelper.StartEffectEvent(entity, "effect", true, worldEffectBlackboard.new())
end

function effect:spawn()
    if self.disableCron then
        Cron.Halt(self.disableCron)
        self.disableCron = nil
    end

    local effect = self.spawnData
    self.spawnData = "base\\spawner\\empty_game_object.ent"

    visualized.spawn(self)
    self.spawnData = effect
end

function effect:despawn()
    GameObjectEffectHelper.StopEffectEvent(self:getEntity(), "effect")

    -- Needs some time for StopEffectEvent to be sent to the entity
    self.disableCron = Cron.After(0.1, function ()
        visualized.despawn(self)
        self.disableCron = nil
    end)
end

---Calling despawn and spawn on the same frame might lead to issues with the effect not playing due to being stopped then started
function effect:respawn()
    if self:isSpawned() then
        return
    end
    self:spawn()
end

function effect:getVisualizerSize()
    return { x = 0.15, y = 0.15, z = 0.15 }
end

function effect:draw()
    visualized.draw(self)

    self:drawPreviewCheckbox()
end

function effect:getProperties()
    local properties = visualized.getProperties(self)
    table.insert(properties, {
        id = self.node,
        name = self.dataType,
        defaultHeader = true,
        draw = function()
            self:draw()
        end
    })
    return properties
end

function effect:export()
    local data = visualized.export(self)
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

return effect