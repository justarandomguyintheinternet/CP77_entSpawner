local mesh = require("modules/classes/spawn/mesh/mesh")
local spawnable = require("modules/classes/spawn/spawnable")
local visualizer = require("modules/utils/visualizer")
local style = require("modules/ui/style")

---Class for worldDynamicMeshNode
---@class dynamicMesh : mesh
---@field private startAsleep boolean
---@field private forceAutoHideDistance number
local dynamicMesh = setmetatable({}, { __index = mesh })

function dynamicMesh:new()
	local o = mesh.new(self)

    o.dataType = "Dynamic Mesh"
    o.modulePath = "physics/dynamicMesh"
    o.spawnDataPath = "data/spawnables/mesh/physics/"
    o.node = "worldDynamicMeshNode"
    o.description = "Places a mesh with simulated physics, from a given .mesh file. Not destructible."
    o.previewNote = "Dynamic meshes do not have simulated physics in the editor"
    o.icon = IconGlyphs.CubeSend

    o.startAsleep = true
    o.hideGenerate = true
    o.forceAutoHideDistance = 150

    setmetatable(o, { __index = self })
   	return o
end

function dynamicMesh:onAssemble(entity)
    spawnable.onAssemble(self, entity)
    local component = PhysicalMeshComponent.new()
    component.name = "mesh"
    component.mesh = ResRef.FromString(self.spawnData)
    component.visualScale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)
    component.meshAppearance = self.app
    component.simulationType = physicsSimulationType.Dynamic

    local filterData = physicsFilterData.new()
    filterData.preset = "World Dynamic"

    local query = physicsQueryFilter.new()
    query.mask1 = 0
    query.mask2 = 70107400

    local sim = physicsSimulationFilter.new()
    sim.mask1 = 114696
    sim.mask2 = 23627

    filterData.queryFilter = query
    filterData.simulationFilter = sim
    component.filterData = filterData

    entity:AddComponent(component)

    visualizer.updateScale(entity, self:getVisualScale(), "arrows")
end

function dynamicMesh:save()
    local data = mesh.save(self)
    data.startAsleep = self.startAsleep
    data.forceAutoHideDistance = self.forceAutoHideDistance or 150

    return data
end

function dynamicMesh:getExtraHeight()
    return mesh.getExtraHeight(self) + ImGui.GetStyle().ItemSpacing.y + ImGui.GetFrameHeight()
end

function dynamicMesh:draw()
    mesh.draw(self)

    self.startAsleep = style.trackedCheckbox(self.object, "Start Asleep", self.startAsleep)

    self.forceAutoHideDistance = style.trackedDragFloat(self.object, "Auto Hide Distance", self.forceAutoHideDistance, 0.1, 0, 1000, "%.1f")
end

function dynamicMesh:export()
    local data = mesh.export(self)
    data.type = "worldDynamicMeshNode"
    data.data.startAsleep = self.startAsleep and 1 or 0
    data.data.forceAutoHideDistance = self.forceAutoHideDistance

    return data
end

return dynamicMesh