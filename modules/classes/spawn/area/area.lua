local visualized = require("modules/classes/spawn/visualized")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")

---Class for worldAreaShapeNode
---@class area : visualized
---@field outlinePath string
---@field height number
---@field markers table
local area = setmetatable({}, { __index = visualized })

function area:new()
	local o = visualized.new(self)

    o.spawnListType = "files"
    o.dataType = "Area"
    o.spawnDataPath = "data/spawnables/area/area/"
    o.modulePath = "area/area"
    o.node = "worldAreaShapeNode"
    o.description = "Base type for all area type nodes. Position is irrelevant, as the actual position is determined by the outline markers."
    o.icon = IconGlyphs.Select

    o.previewed = true
    o.previewColor = "cyan"
    o.outlinePath = ""

    -- Only used for saved data, to have easier access to it during export
    o.height = 0
    o.markers = {}

    setmetatable(o, { __index = self })
   	return o
end

function area:spawn()
    self.rotation = EulerAngles.new(0, 0, 0)
    visualized.spawn(self)
end

function area:update()
    self.rotation = EulerAngles.new(0, 0, 0)
    visualized.update(self)
end

function area:save()
    local data = visualized.save(self)

    local markers = {}
    local height = 0
    local paths = self:loadOutlinePaths()

    if utils.indexValue(paths, self.outlinePath) ~= -1 then
        for _, child in pairs(self.object.sUI.getElementByPath(self.outlinePath).childs) do
            if utils.isA(child, "spawnableElement") and child.spawnable.modulePath == "area/outlineMarker" then
                table.insert(markers, utils.fromVector(child.spawnable.position))
                height = child.spawnable.height
            end
        end
    end

    data.outlinePath = self.outlinePath
    data.markers = markers
    data.height = height

    return data
end

function area:loadOutlinePaths()
    local paths = {}
    local ownRoot = self.object:getRootParent()

    for _, container in pairs(self.object.sUI.containerPaths) do
        if container.ref:getRootParent() == ownRoot then
            local nMarkers = 0
            for _, child in pairs(container.ref.childs) do
                if utils.isA(child, "spawnableElement") and child.spawnable.modulePath == "area/outlineMarker" then
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
    local idx, changed = style.trackedCombo(self.object, "Outline Path", index - 1, paths, 225)
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
    data.data = {}

    if #self.markers == 0 then
        return data
    end

    if #self.markers > 255 then
        print(string.format("[entSpawner] Issue during export: Area outline %s has more than 255 markers. Only the first 255 will be utilized.", self.outlinePath))
    end

    -- Grab center
    local center = Vector4.new(0, 0, 0, 0)
	for _, position in pairs(self.markers) do
		center = utils.addVector(center, ToVector4(position))
	end
	local nMarkers = math.max(1, #self.markers)
	center = Vector4.new(center.x / nMarkers, center.y / nMarkers, center.z / nMarkers, 0)
    data.position = utils.fromVector(center)

    local buffer = utils.intToHex(math.min(255, #self.markers))
    buffer = buffer .. "000000"

    for idx, marker in pairs(self.markers) do
        if idx <= 255 then
            local diff = utils.subVector(ToVector4(marker), center)

            buffer = buffer .. utils.floatToHex(diff.x)
            buffer = buffer .. utils.floatToHex(diff.y)
            buffer = buffer .. utils.floatToHex(diff.z)
            buffer = buffer .. utils.floatToHex(1)
        end
    end

    buffer = buffer .. utils.floatToHex(self.height)

    data.data["outline"] = {
        ["Data"] = {
            ["$type"] = "AreaShapeOutline",
            ["buffer"] = utils.hexToBase64(buffer),
        }
    }

    return data
end

return area