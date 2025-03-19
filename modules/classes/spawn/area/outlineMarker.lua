local connectedMarker = require("modules/classes/spawn/connectedMarker")
local spawnable = require("modules/classes/spawn/spawnable")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local history = require("modules/utils/history")
local visualizer = require("modules/utils/visualizer")

---Class for outline marker (Not a node, meta class used for area nodes)
---@class outlineMarker : connectedMarker
---@field private height number
---@field private dragBeingEdited boolean
local outlineMarker = setmetatable({}, { __index = connectedMarker })

function outlineMarker:new()
	local o = connectedMarker.new(self)

    o.spawnListType = "files"
    o.dataType = "Outline Marker"
    o.spawnDataPath = "data/spawnables/area/outlineMarker/"
    o.modulePath = "area/outlineMarker"
    o.node = "---"
    o.description = "Places a marker for an outline. Automatically connects with other outline markers in the same group, to form an outline. The parent group can be used to reference the contained outline, and use it in worldAreaShapeNode's"
    o.icon = IconGlyphs.SelectMarker

    o.height = 2
    o.dragBeingEdited = false
    o.previewText = "Preview Outline"

    setmetatable(o, { __index = self })
   	return o
end

function outlineMarker:midAssemble()
    self:enforceSameZ()
end

function outlineMarker:save()
    local data = connectedMarker.save(self)

    data.height = self.height

    return data
end

function outlineMarker:update()
    self.rotation = EulerAngles.new(0, 0, 0)

    self:enforceSameZ()
    self:updateTransform(self.object.parent)
    self:updateHeight()

    for _, neighbor in pairs(self:getNeighbors().neighbors) do
        neighbor:updateTransform(neighbor.object.parent)
        neighbor.height = self.height
        neighbor:updateHeight()
    end
end

function outlineMarker:getNeighbors(parent)
    parent = parent or self.object.parent
    local neighbors = {}
    local selfIndex = 0

    for _, entry in pairs(parent.childs) do
        if utils.isA(entry, "spawnableElement") and entry.spawnable.modulePath == self.modulePath and entry ~= self.object then
            table.insert(neighbors, entry.spawnable)
        elseif entry == self.object then
            selfIndex = #neighbors + 1
        end
    end

    local previous = selfIndex == 1 and neighbors[#neighbors] or neighbors[selfIndex - 1]
    local nxt = selfIndex > #neighbors and neighbors[1] or neighbors[selfIndex]

    return { neighbors = neighbors, selfIndex = selfIndex, previous = previous, nxt = nxt }
end

function outlineMarker:getTransform(parent)
    local neighbors = self:getNeighbors(parent)
    local width = 0.005
    local yaw = self.rotation.yaw

    if #neighbors.neighbors > 1 then
        local diff = utils.subVector(neighbors.nxt.position, self.position)
        yaw = diff:ToRotation().yaw + 90
        width = diff:Length() / 2
    end

    return {
        scale = { x = width, y = 0.005, z = self.height },
        rotation = { roll = 0, pitch = 0, yaw = yaw },
    }
end

---Updates the x scale and yaw rotation of the outline marker based on the neighbors
function outlineMarker:updateTransform(parent)
    spawnable.update(self)

    local entity = self:getEntity()
    if not entity then return end

    local transform = self:getTransform(parent)
    local mesh = entity:FindComponentByName("mesh")
    mesh.visualScale = Vector3.new(transform.scale.x, 0.005, transform.scale.z / 2)
    mesh:SetLocalOrientation(EulerAngles.new(0, 0, transform.rotation.yaw):ToQuat())

    mesh:RefreshAppearance()
end

-- Enforce same z for all neighbors
---@protected
function outlineMarker:enforceSameZ()
    for _, neighbor in pairs(self:getNeighbors().neighbors) do
        neighbor.position.z = self.position.z
        local entity = neighbor:getEntity()

        if entity then
            spawnable.update(neighbor)
        end
    end
end

function outlineMarker:updateHeight()
    local entity = self:getEntity()
    if not entity then return end

    local mesh = entity:FindComponentByName("mesh")
    mesh.visualScale = Vector3.new(mesh.visualScale.x, 0.005, self.height / 2)
    mesh:RefreshAppearance()
    visualizer.updateScale(entity, self:getArrowSize(), "arrows")
end

function outlineMarker:draw()
    connectedMarker.draw(self)

    style.mutedText("Height")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    ImGui.SetNextItemWidth(110 * style.viewSize)
    local newValue, changed = ImGui.DragFloat("##height", self.height, 0.01, 0, 250, "%.2f Height")
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

    if changed or finished then
        newValue = math.max(newValue, 0)
        newValue = math.min(newValue, 250)

        self.height = newValue
        self:updateHeight()

        for _, neighbor in pairs(self:getNeighbors().neighbors) do
            neighbor.height = self.height
            neighbor:updateHeight()
        end
    end
end

return outlineMarker