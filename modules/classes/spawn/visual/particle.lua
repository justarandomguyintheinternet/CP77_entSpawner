local spawnable = require("modules/classes/spawn/spawnable")
local style = require("modules/ui/style")

---Class for worldStaticParticleNode
---@class particle : spawnable
---@field emissionRate number
---@field respawnOnMove boolean
local particle = setmetatable({}, { __index = spawnable })

function particle:new()
	local o = spawnable.new(self)

    o.spawnListType = "list"
    o.dataType = "Particles"
    o.spawnDataPath = "data/spawnables/visual/particles/"
    o.modulePath = "visual/particle"
    o.node = "worldStaticParticleNode"
    o.description = "Plays a particle system, from a given .particle file"
    o.icon = IconGlyphs.Shimmer

    o.emissionRate = 1
    o.respawnOnMove = false

    setmetatable(o, { __index = self })
   	return o
end

function particle:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    local component = entParticlesComponent.new()
    ResourceHelper.LoadReferenceResource(component, "particleSystem", self.spawnData, true)
    component.name = "particle"
    component.emissionRate = self.emissionRate
    entity:AddComponent(component)
end

function particle:spawn()
    local particle = self.spawnData
    self.spawnData = "base\\spawner\\empty_entity.ent"

    spawnable.spawn(self)
    self.spawnData = particle
end

function particle:update()
    if not self.respawnOnMove then
        spawnable.update(self)
    end
end

function particle:onEdited(edited)
    if self.respawnOnMove and self:isSpawned() and edited then
        self:despawn()
        self:spawn()
    end
end

function particle:save()
    local data = spawnable.save(self)
    data.emissionRate = self.emissionRate
    data.respawnOnMove = self.respawnOnMove

    return data
end

function particle:draw()
    spawnable.draw(self)

    self.emissionRate, changed = style.trackedDragFloat(self.object, "Emission Rate", self.emissionRate, 0.01, 0, 9999, "%.2f", 80)
    if changed then
        self.emissionRate = math.max(self.emissionRate, 0)

        local entity = self:getEntity()
        if entity then
            local component = entity:FindComponentByName("particle")
            component.emissionRate = self.emissionRate
        end
    end

    self.respawnOnMove = style.trackedCheckbox(self.object, "Respawn on Move", self.respawnOnMove)
    style.tooltip("Respawns the particle system when the object is moved. Use this when the particle system does not move, or only parts of it")
end

function particle:getProperties()
    local properties = spawnable.getProperties(self)
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

function particle:export()
    local data = spawnable.export(self)
    data.type = "worldStaticParticleNode"
    data.data = {
        emissionRate = self.emissionRate,
        forcedAutoHideDistance = -1,
        forcedAutoHideRange = -1,
        particleSystem = {
            DepotPath = {
                ["$storage"] = "string",
                ["$value"] = self.spawnData
            }
        }
    }

    return data
end

return particle