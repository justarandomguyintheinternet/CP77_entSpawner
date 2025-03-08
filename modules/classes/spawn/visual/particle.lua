local visualized = require("modules/classes/spawn/visualized")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")

---Class for worldStaticParticleNode
---@class particle : visualized
---@field emissionRate number
---@field respawnOnMove boolean
---@field private maxPropertyWidth number
local particle = setmetatable({}, { __index = visualized })

function particle:new()
	local o = visualized.new(self)

    o.spawnListType = "list"
    o.dataType = "Particles"
    o.spawnDataPath = "data/spawnables/visual/particles/"
    o.modulePath = "visual/particle"
    o.node = "worldStaticParticleNode"
    o.description = "Plays a particle system, from a given .particle file"
    o.icon = IconGlyphs.Shimmer

    o.emissionRate = 1
    o.respawnOnMove = false
    o.previewColor = "magenta"

    o.assetPreviewType = "position"
    o.assetPreviewDelay = 0.1

    o.maxPropertyWidth = nil

    setmetatable(o, { __index = self })
   	return o
end

function particle:onAssemble(entity)
    visualized.onAssemble(self, entity)

    local component = entParticlesComponent.new()
    ResourceHelper.LoadReferenceResource(component, "particleSystem", self.spawnData, true)
    component.name = "particle"
    component.emissionRate = self.emissionRate
    entity:AddComponent(component)
end

function particle:spawn()
    local particle = self.spawnData
    self.spawnData = "base\\spawner\\empty_entity.ent"

    visualized.spawn(self)
    self.spawnData = particle
end

function particle:update()
    if not self.respawnOnMove then
        visualized.update(self)
    end
end

function particle:onEdited(edited)
    if self.respawnOnMove and self:isSpawned() and edited then
        self:despawn()
        self:spawn()
    end
end

function particle:save()
    local data = visualized.save(self)
    data.emissionRate = self.emissionRate
    data.respawnOnMove = self.respawnOnMove

    return data
end

function particle:getVisualizerSize()
    return { x = 0.15, y = 0.15, z = 0.15 }
end

function particle:draw()
    visualized.draw(self)

    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth({ "Emission Rate", "Respawn on Move" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    self:drawPreviewCheckbox("Visualize", self.maxPropertyWidth)

    style.mutedText("Emission Rate")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.emissionRate, changed = style.trackedDragFloat(self.object, "##emissionRate", self.emissionRate, 0.01, 0, 9999, "%.2f", 80)
    if changed then
        self.emissionRate = math.max(self.emissionRate, 0)

        local entity = self:getEntity()
        if entity then
            local component = entity:FindComponentByName("particle")
            component.emissionRate = self.emissionRate
        end
    end

    style.mutedText("Respawn on Move")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.respawnOnMove = style.trackedCheckbox(self.object, "##respawnOnMove", self.respawnOnMove)
    style.tooltip("Respawns the particle system when the object is moved. Use this when the particle system does not move, or only parts of it")
end

function particle:getProperties()
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

function particle:export()
    local data = visualized.export(self)
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