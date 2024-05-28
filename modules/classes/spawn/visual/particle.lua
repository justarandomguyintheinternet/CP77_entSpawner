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

    o.emissionRate = 1
    o.respawnOnMove = false

    setmetatable(o, { __index = self })
   	return o
end

-- function particle:onAssemble(entity)
--     spawnable.onAssemble(self, entity)

--     local component = entParticlesComponent.new()
--     ResourceHelper.LoadReferenceResource(component, "particleSystem", self.spawnData)
--     component.name = "particle"
--     component.emissionRate = self.emissionRate
--     entity:AddComponent(component)
-- end

--TODO: Do this using onAssemble once resource loading waiting is a thing
function particle:spawn()
    local particle = self.spawnData
    self.spawnData = "base\\spawner\\particles\\" .. self.spawnData:gsub("\\", "_") .. ".ent"

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

function particle:getExtraHeight()
    return 4 * ImGui.GetStyle().ItemSpacing.y + ImGui.GetFrameHeight()
end

function particle:draw()
    spawnable.draw(self)

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    ImGui.SetNextItemWidth(150)
    self.emissionRate, changed = ImGui.DragFloat("Emission Rate", self.emissionRate, 0.01, 0, 9999, "%.2f")
    if changed then
        self.emissionRate = math.max(self.emissionRate, 0)

        local entity = self:getEntity()
        if entity then
            local component = entity:FindComponentByName("particle")
            component.emissionRate = self.emissionRate
        end
    end

    ImGui.SameLine()
    self.respawnOnMove, changed = ImGui.Checkbox("Respawn on Move", self.respawnOnMove)
    style.tooltip("Respawns the particle system when the object is moved. Use this when the particle system does not move, or only parts of it")
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