local visualized = require("modules/classes/spawn/visualized")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local cache = require("modules/utils/cache")

---Class for worldStaticSoundEmitterNode
---@class sound : visualized
---@field private radius number
---@field private emitterMetadataName string
local sound = setmetatable({}, { __index = visualized })

function sound:new()
	local o = visualized.new(self)

    o.spawnListType = "list"
    o.dataType = "Sounds"
    o.spawnDataPath = "data/spawnables/visual/sounds/"
    o.modulePath = "visual/audio"
    o.node = "worldStaticSoundEmitterNode"
    o.description = "Plays a sound"
    o.previewNote = "A lot of the sounds might not work / play.\n\"amb_\" ones usually work.\nRadius is not previewed."
    o.icon = IconGlyphs.VolumeHigh

    o.radius = 5
    o.previewColor = "mediumvioletred"
    o.emitterMetadataName = ""
    o.previewed = true
    o.assetPreviewType = "position"

    setmetatable(o, { __index = self })
   	return o
end

function sound:loadSpawnData(data, position, rotation)
    visualized.loadSpawnData(self, data, position, rotation)

    if self.emitterMetadataName == "" then
        if cache.staticData.staticMetadata[self.spawnData] then
            self.emitterMetadataName = cache.staticData.staticMetadata[self.spawnData][1]
        end
    end
end

function sound:onAssemble(entity)
    visualized.onAssemble(self, entity)

    -- Needed for sound to play
    local component = gameaudioSoundComponent.new()
    component.name = "sound"
    entity:AddComponent(component)

    entity:QueueEvent(SoundPlayEvent.new ({ soundName = self.spawnData }))
end

function sound:spawn()
    local audio = self.spawnData
    self.spawnData = "base\\spawner\\empty_entity.ent"

    visualized.spawn(self)
    self.spawnData = audio
end

function sound:save()
    local data = visualized.save(self)
    data.radius = self.radius
    data.emitterMetadataName = self.emitterMetadataName

    return data
end

function sound:draw()
    visualized.draw(self)

    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth({ "Radius", "Emitter Metadata Name" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    self:drawPreviewCheckbox("Visualize", self.maxPropertyWidth)

    style.mutedText("Radius")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.radius, change = style.trackedDragFloat(self.object, "##radius", self.radius, 0.01, 0, 9999, "%.2f", 80)
    if change then
        self:updateScale()
    end

    style.mutedText("Emitter Metadata Name")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.emitterMetadataName, change = style.trackedSearchDropdown(self.object, "##emitterMetadataName", "Search...", self.emitterMetadataName, cache.staticData.staticMetadataAll, style.getMaxWidth(250))
end

function sound:getArrowSize()
    local max = math.min(math.max(self.radius / 30, 0.6), 0.8)
    return { x = max, y = max, z = max }
end

function sound:getVisualizerSize()
    local x = math.min(math.max(self.radius / 125, 0.125), 0.33)

    return { x = x, y = x, z = x }
end

function sound:getProperties()
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

function sound:export()
    local data = visualized.export(self)
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
        ["emitterMetadataName"] = {
            ["$type"] = "CName",
            ["$storage"] = "string",
            ["$value"] = self.emitterMetadataName or ""
        }
    }

    return data
end

return sound