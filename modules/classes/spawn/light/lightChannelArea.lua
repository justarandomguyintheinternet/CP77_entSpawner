local area = require("modules/classes/spawn/area/area")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local lcHelper = require("modules/utils/lightChannelHelper")

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

function lightChannelArea:calculateAreaShape()
    local shape = GeometryShape.new()
    local vertices = {}
    local indices = {}
    if #self.markers < 3 then return shape end

    for _, marker in pairs(self.markers) do
        local position = utils.subVector(ToVector4(marker), self.position)

        table.insert(vertices, position)
        table.insert(vertices, Vector4.new(position.x, position.y, position.z + self.height, 0))
    end

    -- Builds walls
    for i = 1, #vertices do
        local indexTwo = i % #vertices
        local indexThree = ((i + 1) % #vertices)

        table.insert(indices, i - 1)
        table.insert(indices, indexTwo)
        table.insert(indices, indexThree)
    end

    shape.indices = indices
    shape.vertices = vertices

    return shape
end

function lightChannelArea:save()
    local data = area.save(self)

    data.lightChannels = utils.deepcopy(self.lightChannels)

    return data
end

function lightChannelArea:getGroupedProperties()
    local properties = area.getGroupedProperties(self)

    properties["lcGrouped"] = lcHelper.getGroupedProperties(self)

    return properties
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