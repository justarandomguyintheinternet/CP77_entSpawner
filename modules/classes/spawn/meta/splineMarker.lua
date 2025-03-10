local spawnable = require("modules/classes/spawn/spawnable")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local history = require("modules/utils/history")
local visualizer = require("modules/utils/visualizer")

---Class for spline markers
---@class splineMarker : spawnable
---@field private intersectionMultiplier number
---@field protected previewed boolean
---@field private height number
---@field private dragBeingEdited boolean
local splineMarker = setmetatable({}, { __index = spawnable })

function splineMarker:new()
	local o = spawnable.new(self)

    o.spawnListType = "files"
    o.dataType = "Outline Marker"
    o.spawnDataPath = "data/spawnables/area/outlineMarker/"
    o.modulePath = "area/outlineMarker"
    o.node = "---"
    o.description = "Places a marker for an outline. Automatically connects with other outline markers in the same group, to form a outline. The parent group can be used to refernce the contained outline, and use it in worldAreaShapeNode's"
    o.icon = IconGlyphs.SelectMarker

    o.previewed = true

    o.streamingMultiplier = 10
    o.primaryRange = 350
    o.secondaryRange = 300
    o.noExport = true

    setmetatable(o, { __index = self })
   	return o
end

function splineMarker:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    local transform = self:getTransform()

    local component = entMeshComponent.new()
    component.name = "mesh"
    component.mesh = ResRef.FromString("base\\spawner\\cube_aligned.mesh")
    component.visualScale = Vector3.new(transform.scale.x, 0.005, transform.scale.z / 2)
    component.meshAppearance = "blue"
    component.isEnabled = self.previewed

    local localTransform = WorldTransform.new()
    localTransform:SetOrientationEuler(EulerAngles.new(0, 0, transform.rotation.yaw))
    component.localTransform = localTransform
    entity:AddComponent(component)

    local marker = entMeshComponent.new()
    marker.name = "marker"
    marker.mesh = ResRef.FromString("base\\environment\\ld_kit\\marker.mesh")
    marker.meshAppearance = "blue"
    marker.visualScale = Vector3.new(0.005, 0.005, 0.005)
    marker.isEnabled = self.previewed
    entity:AddComponent(marker)

    visualizer.updateScale(entity, self:getArrowSize(), "arrows")

    for _, neighbor in pairs(self:getNeighbors().neighbors) do
        neighbor:updateTransform(oldParent)
    end
end

function splineMarker:spawn()
    self.rotation = EulerAngles.new(0, 0, 0)
    spawnable.spawn(self)
end

function splineMarker:save()
    local data = spawnable.save(self)

    data.previewed = self.previewed

    return data
end

function splineMarker:onParentChanged(oldParent)
    if self.object.parent then
        self:update()
    end

    local oldNeighbors = self:getNeighbors(oldParent)
    for _, neighbor in pairs(oldNeighbors.neighbors) do
        neighbor:updateTransform(neighbor.object.parent)
    end
end

function outlisplineMarkerneMarker:update()
    self.rotation = EulerAngles.new(0, 0, 0)

    self:updateTransform(self.object.parent)

    for _, neighbor in pairs(self:getNeighbors().neighbors) do
        neighbor:updateTransform(neighbor.object.parent)
    end
end

function splineMarker:getNeighbors(parent)
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

function splineMarker:getTransform(parent)
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
function splineMarker:updateTransform(parent)
    spawnable.update(self)

    local entity = self:getEntity()
    if not entity then return end

    local transform = self:getTransform(parent)
    local mesh = entity:FindComponentByName("mesh")
    mesh.visualScale = Vector3.new(transform.scale.x, 0.005, transform.scale.z / 2)
    mesh:SetLocalOrientation(EulerAngles.new(0, 0, transform.rotation.yaw):ToQuat())

    mesh:RefreshAppearance()
end

function outlineMarker:getSize()
    return { x = 0.1, y = 0.1, z = 0.6 }
end

function outlineMarker:getBBox()
    return {
        min = { x = -0.075, y = -0.075, z = 0 },
        max = { x = 0.075, y = 0.075, z = self:getSize().z }
    }
end

function outlineMarker:getArrowSize()
    local max = math.min(math.max(self.height, 0.75) * 0.5, 0.8)
    return { x = max, y = max, z = max }
end

-- Needed for dropToSurface, uses this and size to get bbox
function outlineMarker:getCenter()
    local position = Vector4.new(self.position.x, self.position.y, self.position.z, 1)
    position.z = position.z + self:getSize().z / 2

    return position
end

function splineMarker:setPreview(state)
    self.previewed = state
    local entity = self:getEntity()

    if entity then
        entity:FindComponentByName("mesh"):Toggle(self.previewed)
        entity:FindComponentByName("marker"):Toggle(self.previewed)
    end
end

function splineMarker:draw()
    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth(propertyNames) + 4 * ImGui.GetStyle().ItemSpacing.x
    end

    style.mutedText("Preview Outline")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.previewed, changed = style.trackedCheckbox(self.object, "##visualize", self.previewed)
    if changed then
        self:setPreview(self.previewed)

        for _, neighbor in pairs(self:getNeighbors().neighbors) do
            neighbor:setPreview(self.previewed)
        end
    end
end

function outlineMarker:getGroupedProperties()
    local properties = {}

    properties["visualization"] = {
		name = "Visualization",
        id = "outlineMarker",
		data = {},
		draw = function(_, entries)
            ImGui.Text("Outline Marker")

            ImGui.SameLine()

            ImGui.PushID("outlineMarker")

			if ImGui.Button("Off") then
				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == self.node then
                        entry.spawnable.previewed = false
                        local entity = entry.spawnable:getEntity()
                        if entity then
                            entity:FindComponentByName("mesh"):Toggle(false)
                            entity:FindComponentByName("marker"):Toggle(false)
                        end
                    end
				end
			end

            ImGui.SameLine()

            if ImGui.Button("On") then
				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == self.node then
                        entry.spawnable.previewed = true
                        local entity = entry.spawnable:getEntity()
                        if entity then
                            entity:FindComponentByName("mesh"):Toggle(true)
                            entity:FindComponentByName("marker"):Toggle(true)
                        end
                    end
				end
			end

            ImGui.PopID()
		end,
		entries = { self.object }
	}

    return properties
end

function outlineMarker:getProperties()
    local properties = {}
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