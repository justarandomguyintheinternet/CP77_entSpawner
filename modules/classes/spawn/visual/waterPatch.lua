local mesh = require("modules/classes/spawn/mesh/mesh")
local style = require("modules/ui/style")

---Class for worldWaterPatchNode
---@class waterPatch : mesh
---@field private depth number
---@field private waterType integer
local waterPatch = setmetatable({}, { __index = mesh })


function waterPatch:new()
	local o = mesh.new(self)

    o.dataType = "Water Patch"
    o.modulePath = "visual/waterPatch"
    o.spawnDataPath = "data/spawnables/visual/waterPatch/"
    o.spawnListType = "files"
    o.node = "worldWaterPatchNode"
    o.description = "Places a water patch, with physics / swimmability"
    o.previewNote = "Water patch does not have physics / reactivity in the editor"
    o.icon = IconGlyphs.Waves

    o.depth = 2
    o.hideGenerate = true

    setmetatable(o, { __index = self })
   	return o
end

function waterPatch:save()
    local data = mesh.save(self)

    data.depth = self.depth
    data.waterType = self.waterType

    return data
end

function waterPatch:draw()
    mesh.draw(self)

    self.depth = style.trackedDragFloat(self.object, "Depth", self.depth, 0.01, 0, 9999, "%.2f Depth", 110)

    ImGui.PopItemWidth()
end

function waterPatch:export()
    local data = mesh.export(self)
    data.type = "worldWaterPatchNode"
    data.scale = { x = self.scale.x, y = self.scale.y, z = 1 }
    data.data.depth = self.depth

    return data
end

return waterPatch