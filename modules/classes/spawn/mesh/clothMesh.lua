local mesh = require("modules/classes/spawn/mesh/mesh")

---Class for worldRotatingMeshNode
---@class clothMesh : mesh
---@field private affectedByWind boolean
---@field private collisionType integer
local clothMesh = setmetatable({}, { __index = mesh })

local collisionTypes = { "SPHERE", "BOX", "CONVEX", "TRIMESH", "CAPSULE" }

function clothMesh:new(object)
	local o = mesh.new(self, object)

    o.dataType = "Cloth Mesh"
    o.modulePath = "mesh/clothMesh"
    o.spawnDataPath = "data/spawnables/mesh/cloth/"
    o.node = "worldClothMeshNode"
    o.description = "Places a cloth mesh with physics, from a given .mesh file"
    o.previewNote = "Cloth meshes do not have simulated physics in the editor"

    o.affectedByWind = false
    o.collisionType = 4

    setmetatable(o, { __index = self })
   	return o
end

function clothMesh:save()
    local data = mesh.save(self)
    data.affectedByWind = self.affectedByWind
    data.collisionType = self.collisionType

    return data
end

function clothMesh:getExtraHeight()
    return mesh.getExtraHeight(self) + ImGui.GetStyle().ItemSpacing.y + ImGui.GetFrameHeight()
end

function clothMesh:draw()
    mesh.draw(self)

    ImGui.PushItemWidth(150)

    self.affectedByWind, changed = ImGui.Checkbox("Affected By Wind", self.affectedByWind)
    ImGui.SameLine()
    self.collisionType, changed = ImGui.Combo("Collision Type", self.collisionType, collisionTypes, #collisionTypes)

    ImGui.PopItemWidth()
end

function clothMesh:export()
    local data = mesh.export(self)
    data.type = "worldClothMeshNode"
    data.data.affectedByWind = self.affectedByWind and 1 or 0
    data.data.collisionMask = collisionTypes[self.collisionType + 1]

    return data
end

return clothMesh