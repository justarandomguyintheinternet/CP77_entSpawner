local visualized = require("modules/classes/spawn/visualized")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")

---Class for worldAreaShapeNode
---@class area : visualized
local area = setmetatable({}, { __index = visualized })

function area:new()
	local o = visualized.new(self)

    o.spawnListType = "files"
    o.dataType = "Area"
    o.spawnDataPath = "data/spawnables/meta/area/"
    o.modulePath = "meta/area"
    o.node = "worldAreaShapeNode"
    o.description = "Base type for all area type nodes. Position is irrelevant, as the actual position is determined by the outline markers."
    o.icon = IconGlyphs.Select

    o.previewed = true
    o.previewColor = "lime"
    o.outlinePath = ""

    setmetatable(o, { __index = self })
   	return o
end

function area:save()
    local data = visualized.save(self)

    return data
end

function area:loadOutlinePaths()
    local paths = {}
    local ownRoot = self.object:getRootParent()

    for _, container in pairs(self.object.sUI.containerPaths) do
        if container.ref:getRootParent() == ownRoot then
            local nMarkers = 0
            for _, child in pairs(container.ref.childs) do
                if utils.isA(child, "spawnableElement") and child.spawnable.modulePath == "meta/outlineMarker" then
                    nMarkers = nMarkers + 1
                end

                if nMarkers == 3 then
                    table.insert(paths, container.path)
                    break
                end
            end
        end
    end

    return paths
end

function area:draw()
    visualized.draw(self)
    self:drawPreviewCheckbox()

    local paths = self:loadOutlinePaths()
    table.insert(paths, 1, "None")

    local index = math.max(1, utils.indexValue(paths, self.outlinePath))
    local idx, changed = style.trackedCombo(self.object, "Outline Path", index - 1, paths)
    if changed then
        self.outlinePath = paths[idx + 1]
    end
    style.tooltip("Path to the group containing the outline markers.\nMust be contained within the same root group as this area.")
end

function area:getProperties()
    local properties = visualized.getProperties(self)
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

function area:export()
    local data = visualized.export(self)
    data.type = "worldAreaShapeNode"

    return data
end

return area