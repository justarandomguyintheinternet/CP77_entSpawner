local area = require("modules/classes/spawn/area/area")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")

---Class for worldLightChannelVolumeNode
---@class lightChannelArea : area
---@field lightChannels boolean[]
local lightChannelArea = setmetatable({}, { __index = area })

function lightChannelArea:new()
	local o = area.new(self)

    o.spawnListType = "files"
    o.dataType = "Light Channel Area"
    o.spawnDataPath = "data/spawnables/lights/lightChannelArea/"
    o.modulePath = "light/lightChannelArea"
    o.node = "worldLightChannelVolumeNode"
    o.description = "Limits light with the corresponding light channel to the specified area."
    o.previewNote = "Does not work in the editor."
    o.icon = IconGlyphs.LightbulbAutoOutline

    o.lightChannels = { true, true, true, true, true, true, true, true, true, false, false, false }

    setmetatable(o, { __index = self })
   	return o
end

function lightChannelArea:save()
    local data = area.save(self)

    data.lightChannels = utils.deepcopy(self.lightChannels)

    return data
end

function lightChannelArea:export()
    local data = area.export(self, 0, 0, -0.01)
    data.type = "worldLightChannelVolumeNode"

    data.data.channels = utils.buildBitfieldString(self.lightChannels, style.lightChannelEnum)

    return data
end

function lightChannelArea:draw()
    area.draw(self)

    if ImGui.TreeNodeEx("Light Channels") then
        self.lightChannels = style.drawLightChannelsSelector(self.object, self.lightChannels)
        ImGui.TreePop()
    end
end

return lightChannelArea