local visualized = require("modules/classes/spawn/visualized")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local history = require("modules/utils/history")

local propertyNames = {
    "Preview Outline",
    "Height"
}

---Class for outline marker (Not a node, meta class used for area nodes)
---@class outlineMarker : visualized
---@field private previewMesh string
---@field private intersectionMultiplier number
---@field private previewed boolean
---@field private height number
---@field private dragBeingEdited boolean
local outlineMarker = setmetatable({}, { __index = visualized })

function outlineMarker:new()
	local o = visualized.new(self)

    o.spawnListType = "files"
    o.dataType = "Outline Marker"
    o.spawnDataPath = "data/spawnables/meta/outlineMarker/"
    o.modulePath = "meta/outlineMarker"
    o.node = "---"
    o.description = "Places a marker for an outline. Automatically connects with other outline markers in the same group, to form a outline. The parent group can be used to refernce the contained outline, and use it in worldAreaShapeNode's"
    o.icon = IconGlyphs.SelectMarker

    o.previewed = true
    o.previewShape = "box"
    o.previewColor = "red"

    o.height = 2
    o.maxPropertyWidth = nil
    o.dragBeingEdited = false

    o.streamingMultiplier = 10
    o.primaryRange = 350
    o.secondaryRange = 300

    setmetatable(o, { __index = self })
   	return o
end

function outlineMarker:save()
    local data = visualized.save(self)

    data.height = self.height

    return data
end

function outlineMarker:getNeighbors()
    local neighbors = {}
    local selfIndex = 0

    for _, entry in pairs(self.object.parent.childs) do
        if utils.isA(entry, "spawnableElement") and entry.spawnable.modulePath == self.modulePath and entry ~= self.object then
            table.insert(neighbors, entry.spawnable)
        elseif entry == self.object then
            selfIndex = #neighbors + 1
        end
    end

    return { neighbors = neighbors, selfIndex = selfIndex }
end

function outlineMarker:getTransform()
    return {
        scale = { x = 2, y = 0.005, z = self.height }
    }
end

function outlineMarker:getVisualizerSize()
    local scale = self:getTransform().scale
    return { x = scale.x / 2, y = scale.y / 2, z = scale.z / 2 }
end

function outlineMarker:updateHeight()
    self:updateScale()

    for _, neighbor in pairs(self:getNeighbors().neighbors) do
        neighbor.height = self.height
        neighbor:updateScale()
    end
end

function outlineMarker:draw()
    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth(propertyNames) + 4 * ImGui.GetStyle().ItemSpacing.x
    end

    style.mutedText("Preview Outline")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.previewed, changed = style.trackedCheckbox(self.object, "##visualize", self.previewed)
    if changed then
        self:setPreview(self.previewed)
    end

    style.mutedText("Height")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    ImGui.SetNextItemWidth(110 * style.viewSize)
    local newValue, changed = ImGui.DragFloat("##height", self.height, 0.01, 0, 50, "%.2f Height")
    local finished = ImGui.IsItemDeactivatedAfterEdit()
	if finished then
		self.dragBeingEdited = false
	end
	if changed and not self.dragBeingEdited then
        local elements = { self.object }
        for _, neighbor in pairs(self:getNeighbors().neighbors) do
            table.insert(elements, neighbor.object)
        end

        history.addAction(history.getMultiSelectChange(elements))
		self.dragBeingEdited = true
	end

    if changed then
        newValue = math.max(newValue, 0)
        newValue = math.min(newValue, 50)

        self.height = newValue
        self:updateHeight()
    end
end

function outlineMarker:getProperties()
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

return outlineMarker