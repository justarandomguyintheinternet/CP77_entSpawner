local visualized = require("modules/classes/spawn/visualized")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")

---Class for worldSplineNode
---@class spline : visualized
---@field splinePath string
---@field points table
---@field reverse boolean
---@field looped boolean
---@field protected maxPropertyWidth number
local spline = setmetatable({}, { __index = visualized })

function spline:new()
	local o = visualized.new(self)

    o.spawnListType = "files"
    o.dataType = "Spline"
    o.spawnDataPath = "data/spawnables/meta/Spline/"
    o.modulePath = "meta/spline"
    o.node = "worldSplineNode"
    o.description = "Basic spline with auto-tangents, which can be referenced using its NodeRef."
    o.icon = IconGlyphs.VectorPolyline

    o.previewed = true
    o.previewColor = "violet"
    o.splinePath = ""

    o.reverse = false
    o.looped = false
    -- Only used for saved data, to have easier access to it during export
    o.points = {}

    o.maxPropertyWidth = nil

    setmetatable(o, { __index = self })
   	return o
end

function spline:getVisualizerSize()
    return { x = 0.25, y = 0.25, z = 0.25 }
end

function spline:spawn()
    self.rotation = EulerAngles.new(0, 0, 0)
    visualized.spawn(self)
end

function spline:update()
    self.rotation = EulerAngles.new(0, 0, 0)
    visualized.update(self)
end

function spline:save()
    local data = visualized.save(self)

    local points = {}
    local paths = self:loadSplinePaths()

    if utils.indexValue(paths, self.splinePath) ~= -1 then
        for _, child in pairs(self.object.sUI.getElementByPath(self.splinePath).childs) do
            if utils.isA(child, "spawnableElement") and child.spawnable.modulePath == "meta/splineMarker" then
                table.insert(points, utils.fromVector(child.spawnable.position))
            end
        end
    end

    data.splinePath = self.splinePath
    data.points = points
    data.reverse = self.reverse
    data.looped = self.looped

    return data
end

function spline:loadSplinePaths()
    local paths = {}
    local ownRoot = self.object:getRootParent()

    for _, container in pairs(self.object.sUI.containerPaths) do
        if container.ref:getRootParent() == ownRoot then
            local nMarkers = 0
            for _, child in pairs(container.ref.childs) do
                if utils.isA(child, "spawnableElement") and child.spawnable.modulePath == "meta/splineMarker" then
                    nMarkers = nMarkers + 1
                end

                if nMarkers == 2 then
                    table.insert(paths, container.path)
                    break
                end
            end
        end
    end

    return paths
end

function spline:draw()
    visualized.draw(self)

    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth({ "Visualize", "Spline Path", "Reverse", "Looped" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    self:drawPreviewCheckbox("Visualize", self.maxPropertyWidth)

    local paths = self:loadSplinePaths()
    table.insert(paths, 1, "None")

    local index = math.max(1, utils.indexValue(paths, self.splinePath))

    style.mutedText("Spline Path")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    local idx, changed = style.trackedCombo(self.object, "##splinePath", index - 1, paths, 225)
    if changed then
        self.splinePath = paths[idx + 1]
    end
    style.tooltip("Path to the group containing the spline points.\nMust be contained within the same root group as this spline.")

    style.mutedText("Reverse")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.reverse, _ = style.trackedCheckbox(self.object, "##reverse", self.reverse)

    style.mutedText("Looped")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.looped, _ = style.trackedCheckbox(self.object, "##looped", self.looped)
end

function spline:getProperties()
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

function spline:export()
    local data = visualized.export(self)
    data.type = "worldSplineNode"
    data.data = {}

    if #self.points == 0 then
        table.insert(self.object.sUI.spawner.baseUI.exportUI.exportIssues.noSplineMarker, self.object.name)

        return data
    end

    local points = {}

    for _, point in pairs(self.points) do
        local position = utils.subVector(point, self.position)

        table.insert(points, {
            ["$type"] = "SplinePoint",
            ["position"] = {
                ["$type"] = "Vector3",
                ["X"] = position.x,
                ["Y"] = position.y,
                ["Z"] = position.z
          }
        })
    end

    data.data = {
        ["splineData"] = {
            ["Data"] = {
                ["$type"] = "Spline",
                ["points"] = points,
                ["reversed"] = self.reverse and 1 or 0,
                ["looped"] = self.looped and 1 or 0
            }
        }
    }

    return data
end

return spline