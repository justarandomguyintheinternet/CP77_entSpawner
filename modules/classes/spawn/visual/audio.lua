local spawnable = require("modules/classes/spawn/spawnable")
local style = require("modules/ui/style")

---Class for worldStaticSoundEmitterNode
---@class sound : spawnable
---@field private radius number
local sound = setmetatable({}, { __index = spawnable })

function sound:new()
	local o = spawnable.new(self)

    o.spawnListType = "list"
    o.dataType = "Sounds"
    o.spawnDataPath = "data/spawnables/visual/sounds/"
    o.modulePath = "visual/particle"
    o.node = "worldStaticSoundEmitterNode"
    o.description = "Plays a sound"

    o.radius = 10

    setmetatable(o, { __index = self })
   	return o
end

function sound:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    local component = gameaudioSoundComponent.new()
    component.name = "sound"
    component.applyAcousticOcclusion = true
    component.applyObstruction = true
    component.audioName = self.spawnData
    component.maxPlayDistance = self.radius
    component.streamingDistance = self.radius

    entity:AddComponent(component)
end

function sound:spawn()
    local audio = self.spawnData
    self.spawnData = "base\\spawner\\empty_entity.ent"

    spawnable.spawn(self)
    self.spawnData = audio
end

function sound:save()
    local data = spawnable.save(self)


    return data
end

function sound:getExtraHeight()
    return 4 * ImGui.GetStyle().ItemSpacing.y + ImGui.GetFrameHeight()
end

function sound:draw()
    spawnable.draw(self)

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    ImGui.SetNextItemWidth(150)
    self.radius, changed = ImGui.DragFloat("Radius", self.radius, 0.01, 0, 9999, "%.2f")
    if changed then
        self.radius = math.max(self.radius, 0)

        local entity = self:getEntity()
        if entity then
            local component = entity:FindComponentByName("sound")
            component.maxPlayDistance = self.radius
            component.streamingDistance = self.radius
        end
    end
end

function sound:export()
    local data = spawnable.export(self)
    data.type = "worldStaticSoundEmitterNode"
    data.data = {
        occlusionEnabled = 1,
        radius = self.radius,
        usePhysicsObstruction = 1,
        useDoppler = 1,
    }

    return data
end

return sound