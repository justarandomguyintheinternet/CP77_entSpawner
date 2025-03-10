local spawnable = require("modules/classes/spawn/spawnable")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local visualizer = require("modules/utils/visualizer")

---Class for connected markers (Not a node, meta class used for area outlines and splines)
---@class connectedMarker : spawnable
---@field private intersectionMultiplier number
---@field protected previewed boolean
---@field private height number
---@field private dragBeingEdited boolean
local connectedMarker = setmetatable({}, { __index = spawnable })

function connectedMarker:new()
	local o = spawnable.new(self)

    o.previewed = true
    o.connectorApp = "blue"
    o.markerApp = "blue"

    o.streamingMultiplier = 10
    o.primaryRange = 350
    o.secondaryRange = 300
    o.noExport = true

    setmetatable(o, { __index = self })
   	return o
end

function connectedMarker:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    local transform = self:getTransform()

    local component = entMeshComponent.new()
    component.name = "mesh"
    component.mesh = ResRef.FromString("base\\spawner\\cube_aligned.mesh")
    component.visualScale = Vector3.new(transform.scale.x, 0.005, transform.scale.z / 2)
    component.meshAppearance = "blue"
    component.isEnabled = self.previewed

    local localTransform = WorldTransform.new()
    localTransform:SetOrientationEuler(EulerAngles.new(0, transform.rotation.pitch, transform.rotation.yaw))
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

    self:midAssemble()

    for _, neighbor in pairs(self:getNeighbors().neighbors) do
        neighbor:updateTransform(oldParent)
    end
end

function connectedMarker:midAssemble() end

function connectedMarker:spawn()
    self.rotation = EulerAngles.new(0, 0, 0)
    spawnable.spawn(self)
end

function connectedMarker:save()
    local data = spawnable.save(self)

    data.previewed = self.previewed

    return data
end

function connectedMarker:onParentChanged(oldParent)
    if self.object.parent then
        self:update()
    end

    local oldNeighbors = self:getNeighbors(oldParent)
    for _, neighbor in pairs(oldNeighbors.neighbors) do
        neighbor:updateTransform(neighbor.object.parent)
    end
end

function connectedMarker:update()
    self.rotation = EulerAngles.new(0, 0, 0)

    self:updateTransform(self.object.parent)

    for _, neighbor in pairs(self:getNeighbors().neighbors) do
        neighbor:updateTransform(neighbor.object.parent)
    end
end

function connectedMarker:getNeighbors(parent)
    return { neighbors = {}, selfIndex = 1, previous = {}, nxt = {} }
end

function connectedMarker:getTransform(parent)
    return {
        scale = { x = 0.005, y = 0.005, z = 0.005 },
        rotation = { roll = 0, pitch = 0, yaw = 0 },
    }
end

---Use getTransform, then update the mesh
function connectedMarker:updateTransform(parent) end

function connectedMarker:getSize()
    return { x = 0.1, y = 0.1, z = 0.6 }
end

function connectedMarker:getBBox()
    return {
        min = { x = -0.075, y = -0.075, z = 0 },
        max = { x = 0.075, y = 0.075, z = self:getSize().z }
    }
end

-- Needed for dropToSurface, uses this and size to get bbox
function connectedMarker:getCenter()
    local position = Vector4.new(self.position.x, self.position.y, self.position.z, 1)
    position.z = position.z + self:getSize().z / 2

    return position
end

function connectedMarker:setPreview(state)
    self.previewed = state
    local entity = self:getEntity()

    if entity then
        entity:FindComponentByName("mesh"):Toggle(self.previewed)
        entity:FindComponentByName("marker"):Toggle(self.previewed)
    end
end

function connectedMarker:draw()
    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth({"Preview Outline"}) + 4 * ImGui.GetStyle().ItemSpacing.x
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

function connectedMarker:getGroupedProperties()
    local properties = {}

    properties["visualization"] = {
		name = "Visualization",
        id = self.dataType,
		data = {},
		draw = function(_, entries)
            ImGui.Text(self.dataType)

            ImGui.SameLine()

            ImGui.PushID(self.dataType)

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

function connectedMarker:getProperties()
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

return connectedMarker