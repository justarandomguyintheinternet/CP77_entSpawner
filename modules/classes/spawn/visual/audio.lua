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

function sound:draw()
    spawnable.draw(self)

    self.radius = style.trackedDragFloat(self.object, "Radius", self.radius, 0.01, 0, 9999, "%.2f", 80)
end

function sound:getProperties()
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