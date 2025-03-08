local mesh = require("modules/classes/spawn/mesh/mesh")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")

---Class for worldRotatingMeshNode
---@class clothMesh : mesh
---@field private affectedByWind boolean
---@field private collisionType integer
local clothMesh = setmetatable({}, { __index = mesh })

local collisionTypes = { "SPHERE", "BOX", "CONVEX", "TRIMESH", "CAPSULE" }

function clothMesh:new()
	local o = mesh.new(self)

    o.dataType = "Cloth Mesh"
    o.modulePath = "mesh/clothMesh"
    o.spawnDataPath = "data/spawnables/mesh/cloth/"
    o.node = "worldClothMeshNode"
    o.description = "Places a cloth mesh with physics, from a given .mesh file"
    o.previewNote = "Cloth meshes do not have simulated physics in the editor"
    o.icon = IconGlyphs.ReceiptOutline

    o.affectedByWind = false
    o.collisionType = 4
    o.hideGenerate = true

    setmetatable(o, { __index = self })
   	return o
end

function clothMesh:save()
    local data = mesh.save(self)
    data.affectedByWind = self.affectedByWind
    data.collisionType = self.collisionType

    return data
end

function clothMesh:draw()
    local calculateMaxWidth = not self.maxPropertyWidth

    mesh.draw(self)

    if calculateMaxWidth then
        self.maxPropertyWidth = math.max(self.maxPropertyWidth, utils.getTextMaxWidth({ "Affected By Wind", "Collision Mask" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX())
    end

    style.mutedText("Affected By Wind")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.affectedByWind = style.trackedCheckbox(self.object, "##affectedByWind", self.affectedByWind)

    style.mutedText("Collision Mask")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.collisionType = style.trackedCombo(self.object, "##collisionMask", self.collisionType, collisionTypes)

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