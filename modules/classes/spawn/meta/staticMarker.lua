local visualized = require("modules/classes/spawn/visualized")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")

local propertyNames = {
    "Preview Marker",
    "Quest Marker"
}

---Class for worldStaticMarkerNode
---@class staticMarker : visualized
---@field private questMarker boolean
---@field private previewMesh string
---@field private intersectionMultiplier number
---@field private previewed boolean
local staticMarker = setmetatable({}, { __index = visualized })

function staticMarker:new()
	local o = visualized.new(self)

    o.spawnListType = "files"
    o.dataType = "Static Marker"
    o.spawnDataPath = "data/spawnables/meta/staticMarker/"
    o.modulePath = "meta/staticMarker"
    o.node = "worldStaticMarkerNode"
    o.description = "Places a static marker node. Useful if you need a NodeRef as a reference point."
    o.icon = IconGlyphs.MapMarker

    o.previewed = true
    o.previewShape = "mesh"
    o.previewMesh = "base\\environment\\ld_kit\\marker.mesh"
    o.intersectionMultiplier = 0.3 / 0.005

    o.questMarker = false
    o.maxPropertyWidth = nil

    o.streamingMultiplier = 10
    o.primaryRange = 350
    o.secondaryRange = 300

    setmetatable(o, { __index = self })
   	return o
end

function staticMarker:save()
    local data = visualized.save(self)
    data.questMarker = self.questMarker

    return data
end

function staticMarker:getSize()
    return { x = 0.1, y = 0.1, z = 0.6 }
end

function staticMarker:getBBox()
    return {
        min = { x = -0.075, y = -0.075, z = 0 },
        max = { x = 0.075, y = 0.075, z = self:getSize().z }
    }
end

-- Needed for dropToSurface, uses this and size to get bbox
function staticMarker:getCenter()
    local position = Vector4.new(self.position.x, self.position.y, self.position.z, 1)
    position.z = position.z + self:getSize().z / 2

    return position
end

function staticMarker:getVisualizerSize()
    return { x = 0.005, y = 0.005, z = 0.005 }
end

function staticMarker:draw()
    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth(propertyNames) + 4 * ImGui.GetStyle().ItemSpacing.x
    end

    style.mutedText("Preview Marker")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.previewed, changed = style.trackedCheckbox(self.object, "##visualize", self.previewed)
    if changed then
        self:setPreview(self.previewed)
    end

    style.mutedText("Quest Marker")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.questMarker, _ = style.trackedCheckbox(self.object, "##questMarker", self.questMarker)
end

function staticMarker:getProperties()
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

function staticMarker:export()
    local data = visualized.export(self)
    data.type = "worldStaticMarkerNode"
    data.data = {}

    if self.questMarker then
        data.data = {
            ["data"] = {
                ["Data"] = {
                    ["$type"] = "worldQuestMarker"
                }
            }
        }
    end

    return data
end

return staticMarker