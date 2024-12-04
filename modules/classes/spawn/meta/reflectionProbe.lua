local spawnable = require("modules/classes/spawn/spawnable")
local style = require("modules/ui/style")
local visualizer = require("modules/utils/visualizer")
local utils = require("modules/utils/utils")

---Class for worldReflectionProbeNode
---@class reflection : spawnable
---@field public scale {x: number, y: number, z: number}
---@field public edgeScale {x: number, y: number, z: number}
---@field private previewed boolean
---@field private ambientModes table
---@field private neighborModes table
---@field public ambientMode integer
---@field public neighborMode integer
---@field public emissiveScale number
---@field public streamingDistance number
local reflection = setmetatable({}, { __index = spawnable })

function reflection:new()
	local o = spawnable.new(self)

    o.spawnListType = "list"
    o.dataType = "Reflection Probe"
    o.spawnDataPath = "data/spawnables/meta/reflectionProbe/"
    o.modulePath = "meta/reflectionProbe"
    o.node = "worldReflectionProbeNode"
    o.description = "Places a reflection probe of variable size. Can be used to make indoors have appropriate base lighting."
    o.icon = IconGlyphs.HomeLightbulbOutline

    o.scaleLocked = false
    o.scale = { x = 5, y = 5, z = 5 }
    o.edgeScale = { x = 1, y = 1, z = 1 }
    o.previewed = true

    o.ambientModes = utils.enumTable("envUtilsReflectionProbeAmbientContributionMode")
    o.neighborModes = utils.enumTable("envUtilsNeighborMode")

    o.ambientMode = 2
    o.neighborMode = 3
    o.emissiveScale = 1
    o.streamingDistance = 50

    o.uk10 = 1056
    o.uk11 = 512

    setmetatable(o, { __index = self })
   	return o
end

function reflection:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    visualizer.addBox(entity, self.scale, "seashell")

    local component = entEnvProbeComponent.new()
    component.name = "probe"
    component.probeDataRef = ResRef.FromString(self.spawnData)
    component.size = Vector3.new(self.scale.x, self.scale.y, self.scale.z)
    component.edgeScale = Vector3.new(self.edgeScale.x, self.edgeScale.y, self.edgeScale.z)
    component.ambientMode = Enum.new("envUtilsReflectionProbeAmbientContributionMode", self.ambientMode)
    component.neighborMode = Enum.new("envUtilsNeighborMode", self.neighborMode)
    component.emissiveScale = self.emissiveScale
    component.streamingDistance = self.streamingDistance
    entity:AddComponent(component)

    visualizer.updateScale(entity, self:getVisualizerSize(), "arrows")
    visualizer.toggleAll(entity, self.previewed)
end

function reflection:spawn()
    local probe = self.spawnData
    self.spawnData = "base\\spawner\\empty_entity.ent"

    spawnable.spawn(self)
    self.spawnData = probe
end

function reflection:save()
    local data = spawnable.save(self)

    data.scale = { x = self.scale.x, y = self.scale.y, z = self.scale.z }
    data.edgeScale = { x = self.edgeScale.x, y = self.edgeScale.y, z = self.edgeScale.z }
    data.ambientMode = self.ambientMode
    data.neighborMode = self.neighborMode
    data.emissiveScale = self.emissiveScale
    data.streamingDistance = self.streamingDistance
    data.previewed = self.previewed

    return data
end

---@protected
function reflection:updateScale(finished)
    if finished then
        self:respawn()
        return
    end

    local entity = self:getEntity()
    if not entity then return end

    visualizer.updateScale(entity, self:getVisualizerSize(), "arrows")
    visualizer.updateScale(entity, self.scale, "box")
end

function reflection:getSize()
    return self.scale
end

function reflection:getVisualizerSize()
    local size = self:getSize()

    local max = math.min(math.max(size.x, size.y, size.z, 1.5) * 0.5, 3)
    return { x = max, y = max, z = max }
end

function reflection:draw()
    spawnable.draw(self)

    self.previewed, changed = style.trackedCheckbox(self.object, "Visualize outline", self.previewed)
    if changed then
        visualizer.toggleAll(self:getEntity(), self.previewed)
    end

    ImGui.Text("Ambient Mode")
    ImGui.SameLine()
    local value, changed = style.trackedCombo(self.object, "##ambientMode", self.ambientMode - 1, self.ambientModes)
    if changed then
        self.ambientMode = value + 1
        self:respawn()
    end

    ImGui.Text("Neighbor Mode")
    ImGui.SameLine()
    local value, changed = style.trackedCombo(self.object, "##neighborMode", self.neighborMode - 1, self.neighborModes)
    if changed then
        self.neighborMode = value + 1
        self:respawn()
    end

    self.emissiveScale, _, finished = style.trackedDragFloat(self.object, "##emissiveScale", self.emissiveScale, 0.01, 0, 50, "%.2f Emissive Scale", 110)
    if finished then
        self:respawn()
    end

    ImGui.SameLine()

    self.streamingDistance, _, finished = style.trackedDragFloat(self.object, "##streamingDistance", self.streamingDistance, 0.1, 0, 9999, "%.1f Streaming Dist.", 110)
    if finished then
        self:respawn()
    end

    ImGui.Text("Edge Scale")
    ImGui.SameLine()
    self.edgeScale.x, _, finished = style.trackedDragFloat(self.object, "##edgeX", self.edgeScale.x, 0.05, 0, 9999, "%.2f X", 60)
    if finished then
        self:respawn()
    end
    ImGui.SameLine()
    self.edgeScale.y, _, finished = style.trackedDragFloat(self.object, "##edgeY", self.edgeScale.y, 0.05, 0, 9999, "%.2f Y", 60)
    if finished then
        self:respawn()
    end
    ImGui.SameLine()
    self.edgeScale.z, _, finished = style.trackedDragFloat(self.object, "##edgeZ", self.edgeScale.z, 0.05, 0, 9999, "%.2f Z", 60)
    if finished then
        self:respawn()
    end
end

function reflection:getProperties()
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

function reflection:getGroupedProperties()
    local properties = spawnable.getGroupedProperties(self)

    properties["visualization"] = {
		name = "Visualization",
        id = "reflection",
		data = {},
		draw = function(_, entries)
            ImGui.Text("Reflection Probe")

            ImGui.SameLine()

            ImGui.PushID("reflection")

			if ImGui.Button("Off") then
				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == "worldReflectionProbeNode" then
                        entry.spawnable.previewed = false
                        visualizer.toggleAll(entry.spawnable:getEntity(), entry.spawnable.previewed)
                    end
				end
			end

            ImGui.SameLine()

            if ImGui.Button("On") then
				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == "worldReflectionProbeNode" then
                        entry.spawnable.previewed = true
                        visualizer.toggleAll(entry.spawnable:getEntity(), entry.spawnable.previewed)
                    end
				end
			end

            ImGui.PopID()
		end,
		entries = { self.object }
	}

    return properties
end

function reflection:export()
    local data = spawnable.export(self)
    data.type = "worldReflectionProbeNode"
    data.scale = self.scale
    data.data = {
        probeDataRef = {
            DepotPath = {
                ["$storage"] = "string",
                ["$value"] = self.spawnData
            },
        },
        edgeScale = {
			["$type"] = "Vector3",
			["X"] = self.edgeScale.x,
			["Y"] = self.edgeScale.y,
			["Z"] = self.edgeScale.z
		},
        ambientMode = self.ambientModes[self.ambientMode],
        neighborMode = self.neighborModes[self.neighborMode],
        emissiveScale = self.emissiveScale,
        streamingDistance = self.streamingDistance
    }

    return data
end

return reflection