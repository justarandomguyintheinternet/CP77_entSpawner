local visualized = require("modules/classes/spawn/visualized")
local history = require("modules/utils/project/history")
local saveState = require("modules/utils/project/saveState")
local style = require("modules/ui/style")
local projectedWireframe = require("modules/utils/editor/projectedWireframe")

local navigationLink = setmetatable({}, { __index = visualized })
local lineStyle = { color = 0xFFF5BE74, thickness = 3 }

function navigationLink:new()
    local object = visualized.new(self)
    object.spawnListType = "files"
    object.spawnDataPath = "data/spawnables/area/navigationLink/"
    object.modulePath = "area/navigationLink"
    object.dataType = "Navigation Link"
    object.node = "worldOffMeshConnectionNode"
    object.icon = IconGlyphs.LinkVariant
    object.description = "Connects two walkable surfaces with a bidirectional Floor link."
    object.previewed = true
    object.noExport = true
    object.endOffset = { x = 0, y = 0, z = 0 }
    object.radius = .75
    return object
end

local function distance(offset)
    return math.sqrt(offset.x ^ 2 + offset.y ^ 2 + offset.z ^ 2)
end

function navigationLink:save()
    local data = visualized.save(self)
    local p = self.endOffset
    data.endOffset = { x = p.x, y = p.y, z = p.z }
    data.radius = self.radius
    return data
end

function navigationLink:setEndPosition(position)
    local offset = Vector4.new(position.x - self.position.x, position.y - self.position.y, position.z - self.position.z, 0)
    local localPosition = self.rotation:ToQuat():TransformInverse(offset)
    self.endOffset = { x = localPosition.x, y = localPosition.y, z = localPosition.z }
end

function navigationLink:getProperties()
    return {{
        id = "navigationLink",
        name = "Navigation Link",
        defaultHeader = true,
        draw = function()
            local radius, changed = style.trackedDragFloat(self.object, "Endpoint radius", self.radius, .05, .1, 2)
            if changed then self.radius = radius end
            local player = GetPlayer()
            if ImGui.Button("Set end from V") and player then
                history.addAction(history.getElementChange(self.object))
                self:setEndPosition(player:GetWorldPosition())
                saveState.markDirty(self.object)
            end
            local length = distance(self.endOffset)
            if length < .05 then
                ImGui.TextWrapped("Set the end on the other walkable surface.")
            else
                ImGui.Text(string.format("Endpoint separation %.2f m", length))
            end
        end
    }}
end

function navigationLink:wantsViewportOverlay()
    return self.object.selected and self.previewed and distance(self.endOffset) >= .05
end

function navigationLink:getEndPosition()
    local p = self.endOffset
    local offset = self.rotation:ToQuat():Transform(Vector4.new(p.x, p.y, p.z, 0))
    return Vector4.new(self.position.x + offset.x, self.position.y + offset.y, self.position.z + offset.z, 1)
end

function navigationLink:drawViewportOverlay(screen, drawList)
    projectedWireframe.drawWorldLine(drawList, screen, self.position, self:getEndPosition(), lineStyle)
end

function navigationLink:getFittedNavigationLink()
    local p = self.endOffset
    if distance(p) < .05 then
        error("Set the end of Navigation Link '" .. self.object.name .. "' before exporting.")
    end
    local destination = self:getEndPosition()
    return {
        name = self.object.name,
        position = { x = self.position.x, y = self.position.y, z = self.position.z },
        radius = self.radius,
        destination = { x = destination.x, y = destination.y, z = destination.z }
    }
end

return navigationLink
