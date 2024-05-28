local mesh = require("modules/classes/spawn/mesh/mesh")

---Class for worldDynamicMeshNode
---@class dynamicMesh : mesh
---@field private startAsleep boolean
---@field private forceAutoHideDistance number
local dynamicMesh = setmetatable({}, { __index = mesh })

function dynamicMesh:new(object)
	local o = mesh.new(self, object)

    o.dataType = "Dynamic Mesh"
    o.modulePath = "physics/dynamicMesh"
    o.spawnDataPath = "data/spawnables/mesh/physics/"
    o.node = "worldDynamicMeshNode"
    o.description = "Places a mesh with simulated physics, from a given .mesh file. Not destructible."
    o.previewNote = "Dynamic meshes do not have simulated physics in the editor"

    o.startAsleep = true
    o.hideGenerate = true
    o.forceAutoHideDistance = 150

    setmetatable(o, { __index = self })
   	return o
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

    self.startAsleep = ImGui.Checkbox("Start Asleep", self.startAsleep)

    ImGui.SameLine()

    ImGui.PushItemWidth(150)
    self.forceAutoHideDistance = ImGui.InputFloat("Auto Hide Distance", self.forceAutoHideDistance, 0, 1000, "%.1f")

    ImGui.PopItemWidth()
end

function dynamicMesh:export()
    local data = mesh.export(self)
    data.type = "worldDynamicMeshNode"
    data.data.startAsleep = self.startAsleep and 1 or 0
    data.data.forceAutoHideDistance = self.forceAutoHideDistance

    return data
end

return dynamicMesh