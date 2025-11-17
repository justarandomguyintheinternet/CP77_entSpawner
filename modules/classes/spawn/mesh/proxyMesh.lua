local mesh = require("modules/classes/spawn/mesh/mesh")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")

---Class for worldGenericProxyMeshNode
---@class proxyMesh : mesh
---@field public nearAutoHideDistance number
local proxyMesh = setmetatable({}, { __index = mesh })

function proxyMesh:new()
	local o = mesh.new(self)

    o.spawnListType = "list"
    o.dataType = "Proxy Mesh"
    o.modulePath = "mesh/proxyMesh"
    o.node = "worldGenericProxyMeshNode"
    o.description = "Places a proxy mesh, from a given .mesh file. Preview does not hide the mesh when close."
    o.icon = IconGlyphs.BoxShadow

    o.nearAutoHideDistance = 15

    o.hideGenerate = true

    setmetatable(o, { __index = self })
   	return o
end

function proxyMesh:draw()
    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth({ "Appearance", "Collider", "Occluder", "Enable Wind Impulse", "Near Auto Hide Distance" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end
    mesh.draw(self)

    style.mutedText("Near Auto Hide Distance")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.nearAutoHideDistance = style.trackedDragFloat(self.object, "##nearAutoHideDistance", self.nearAutoHideDistance, 0.5, 0.01, 9999, "%.2f", 95)
end

function proxyMesh:save()
    local data = mesh.save(self)
    data.nearAutoHideDistance = self.nearAutoHideDistance

    return data
end

function proxyMesh:export()
    local data = mesh.export(self)
    data.type = "worldGenericProxyMeshNode"
    data.data.nearAutoHideDistance = self.nearAutoHideDistance
    data.data.nbNodesUnderProxy = 0

    return data
end

return proxyMesh