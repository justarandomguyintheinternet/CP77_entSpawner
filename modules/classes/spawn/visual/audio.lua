local spawnable = require("modules/classes/spawn/spawnable")
local visualizer = require("modules/utils/visualizer")

---Class for worldStaticSoundEmitterNode
---@class sound : spawnable
---@field private radius number
local sound = setmetatable({}, { __index = spawnable })

function sound:new()
	local o = spawnable.new(self)

    o.spawnListType = "list"
    o.dataType = "Sounds"
    o.spawnDataPath = "data/spawnables/visual/sounds/"
    o.modulePath = "visual/audio"
    o.node = "worldStaticSoundEmitterNode"
    o.description = "Plays a sound"
    o.previewNote = "A lot of the sounds might not work / play.\n\"amb_\" ones usually work.\nRadius is not previewed."
    o.icon = IconGlyphs.VolumeHigh

    o.radius = 5

    setmetatable(o, { __index = self })
   	return o
end

function sound:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    -- Needed for sound to play
    local component = gameaudioSoundComponent.new()
    component.name = "sound"
    entity:AddComponent(component)

    -- visualizer.addSphere(entity, 0.5, "green")

    entity:QueueEvent(SoundPlayEvent.new ({ soundName = self.spawnData }))
end

function sound:spawn()
    local audio = self.spawnData
    self.spawnData = "base\\spawner\\empty_entity.ent"

    spawnable.spawn(self)
    self.spawnData = audio
end

function sound:save()
    local data = spawnable.save(self)
    data.radius = self.radius

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
    self.radius = ImGui.DragFloat("Radius", self.radius, 0.01, 0, 9999, "%.2f")
end

function sound:export()
    local data = spawnable.export(self)
    data.type = "worldStaticSoundEmitterNode"
    data.data = {
        occlusionEnabled = 1,
        radius = self.radius,
        usePhysicsObstruction = 1,
        useDoppler = 1,
        Settings = {
        ["Data"] = {
            ["$type"] = "audioAmbientAreaSettings",
            ["EventsOnActive"] = {
                    {
                        ["$type"] = "audioAudEventStruct",
                        ["event"] = {
                            ["$type"] = "CName",
                            ["$storage"] = "string",
                            ["$value"] = self.spawnData
                        }
                    }
                },
            }
        },
    }

    return data
end

return sound