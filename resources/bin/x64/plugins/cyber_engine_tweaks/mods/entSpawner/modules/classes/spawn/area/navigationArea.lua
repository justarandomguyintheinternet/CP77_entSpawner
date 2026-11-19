local spawnable = require("modules/classes/spawn/spawnable")
local visualized = require("modules/classes/spawn/visualized")
local editor = require("modules/utils/editor/editor")
local fitToGround = require("modules/utils/editor/fitToGround")
local history = require("modules/utils/project/history")
local saveState = require("modules/utils/project/saveState")
local projectedWireframe = require("modules/utils/editor/projectedWireframe")
local style = require("modules/ui/style")
local utils = require("modules/utils/core/utils")

local navigationArea = setmetatable({}, { __index = visualized })
local footprintLine = { color = 0xFF4BBBE7, thickness = 2 }
local rejectedLine = { color = 0xA04F58ED, thickness = 1.4 }
local surfaceLine = { color = 0xCA7EEA65, thickness = 1.3 }

function navigationArea:new()
    local o = visualized.new(self)
    o.spawnListType = "files"
    o.spawnDataPath = "data/spawnables/area/navigation/"
    o.dataType = "Navigation Area"
    o.modulePath = "area/navigationArea"
    o.node = "---"
    o.icon = IconGlyphs.MapMarkerPath
    o.description = "Fits Human navigation to streamed collision inside a footprint."
    o.noExport = true
    o.previewed = true
    o.defaultScaleLocked = false
    o.scale = { x = 6, y = 3, z = .1 }
    o.layer = 200
    o.shape = 0
    return o
end

function navigationArea:getSize()
    return { x = self.scale.x * 2, y = self.scale.y * 2, z = .2 }
end

function navigationArea:getVisualizerSize()
    return { x = .18, y = .18, z = .18 }
end

function navigationArea:getTransformUIConfig()
    return { axes = { rotation = { roll = false, pitch = false }, scale = { z = false } } }
end

function navigationArea:update()
    self.rotation = EulerAngles.new(0, 0, self.rotation.yaw)
    spawnable.update(self)
end

function navigationArea:updateScale()
    self.scale.x = math.max(1, math.min(48, self.scale.x))
    self.scale.y = math.max(1, math.min(48, self.scale.y))
    self.scale.z = .1
    visualized.updateScale(self)
end

function navigationArea:loadSpawnData(data, position, rotation)
    visualized.loadSpawnData(self, data, position, EulerAngles.new(0, 0, rotation.yaw))
    self.scale = utils.deepcopy(self.scale)
    self.fitted = utils.deepcopy(data.fitted)
    self.fitGrid = utils.deepcopy(data.fitGrid)
    self.previewLines = nil
end

function navigationArea:save()
    local data = visualized.save(self)
    data.scale = utils.deepcopy(self.scale)
    data.layer = self.layer
    data.shape = self.shape
    data.fitted = utils.deepcopy(self.fitted)
    data.fitGrid = utils.deepcopy(self.fitGrid)
    return data
end

local function close(a, b)
    return math.abs(a - b) < .001
end

function navigationArea:hasCurrentFit()
    local f, p, size = self.fitted, self.position, self:getSize()
    return f ~= nil and f.layer == self.layer and (f.shape or 0) == self.shape
        and close(f.anchor[1], p.x) and close(f.anchor[2], p.y) and close(f.anchor[3], p.z)
        and close(f.footprint[1], size.x) and close(f.footprint[2], size.y)
        and math.abs(((f.yaw - self.rotation.yaw + 180) % 360) - 180) < .001
end

local function triangleCount(surface)
    if surface.version == 1 then return #surface.faces end
    local count = 0
    for _, tile in ipairs(surface.tiles) do count = count + #tile.faces end
    return count
end

function navigationArea:fit()
    local p, size = self.position, self:getSize()
    local preview, err = fitToGround.capture(editor.interface, p.x, p.y, p.z, size.x, size.y, self.layer, self.rotation.yaw, self.shape)
    if not preview then return false, err end
    if triangleCount(preview.surface) == 0 then return false, "No walkable cells found." end

    history.addAction(history.getElementChange(self.object))
    self.fitted = preview.surface
    self.fitGrid = preview.cells
    self.previewLines = nil
    saveState.markDirty(self.object)
    return true
end

function navigationArea:getFittedNavigation()
    if not self:hasCurrentFit() then
        error("Fit to Ground on Navigation Area '" .. self.object.name .. "' and save its group before exporting.")
    end
    return self.fitted
end

function navigationArea:getProperties()
    return {{
        id = "navigationArea",
        name = "Navigation Area",
        defaultHeader = true,
        draw = function()
            self:draw()
        end
    }}
end

function navigationArea:draw()
    local size = self:getSize()
    ImGui.Text(string.format("Footprint %.2f x %.2f m", size.x, size.y))
    local shape, shapeChanged = style.trackedCombo(self.object, "Footprint shape", self.shape, {"Rectangle", "Ellipse"}, 125)
    if shapeChanged then self.shape = shape end
    local layer, changed = style.trackedDragInt(self.object, "Tile layer", self.layer, 1, 255)
    if changed then
        self.layer = layer
    end
    if ImGui.Button("Fit to Ground") then
        local ok, err = self:fit()
        self.fitError = ok and nil or err
    end
    if self.fitError then
        ImGui.TextWrapped(self.fitError)
    end
    if self:hasCurrentFit() then
        local tiles = self.fitted.tiles and #self.fitted.tiles or 1
        ImGui.TextWrapped(string.format("%d triangles across %d tile(s)", triangleCount(self.fitted), tiles))
    elseif self.fitted then
        ImGui.TextWrapped("Area changed. Fit to Ground again before exporting.")
    end
end

function navigationArea:wantsViewportOverlay()
    return self.object and self.object.selected and self.previewed
end

function navigationArea:drawViewportOverlay(screen, drawList)
    local p, size = self.position, self:getSize()
    local angle = math.rad(self.rotation.yaw)
    local c, s = math.cos(angle), math.sin(angle)
    local function point(u, v)
        return Vector4.new(p.x + c*u - s*v, p.y + s*u + c*v, p.z + .05, 1)
    end
    local function rectangle(x0, y0, x1, y1, options)
        local a, b, c1, d = point(x0, y0), point(x1, y0), point(x1, y1), point(x0, y1)
        projectedWireframe.drawWorldLine(drawList, screen, a, b, options)
        projectedWireframe.drawWorldLine(drawList, screen, b, c1, options)
        projectedWireframe.drawWorldLine(drawList, screen, c1, d, options)
        projectedWireframe.drawWorldLine(drawList, screen, d, a, options)
    end

    if self.shape == 1 then
        local previous = point(size.x / 2, 0)
        for i = 1, 64 do
            local angle = i * math.pi / 32
            local nextPoint = point(math.cos(angle) * size.x / 2, math.sin(angle) * size.y / 2)
            projectedWireframe.drawWorldLine(drawList, screen, previous, nextPoint, footprintLine)
            previous = nextPoint
        end
    else
        rectangle(-size.x / 2, -size.y / 2, size.x / 2, size.y / 2, footprintLine)
    end
    if not self:hasCurrentFit() then return end

    if not self.previewLines then
        self.previewLines = {}
        for _, tile in ipairs(self.fitted.tiles or {self.fitted}) do
            local points, edges = {}, {}
            for i, v in ipairs(tile.vertices) do
                points[i - 1] = Vector4.new(v[1], v[2], v[3] + .04, 1)
            end
            for _, face in ipairs(tile.faces) do
                for i = 1, 3 do
                    local a, b = face[i], face[i % 3 + 1]
                    local key = math.min(a, b) .. ":" .. math.max(a, b)
                    if edges[key] then
                        edges[key].boundary = false
                    else
                        edges[key] = {points[a], points[b], boundary = true}
                        table.insert(self.previewLines, edges[key])
                    end
                end
            end
        end
    end
    local camera = screen.cameraWorld
    for _, edge in ipairs(self.previewLines) do
        local a = edge[1]
        if not self.fitted.tiles or edge.boundary or not camera
            or (a.x - camera.x)^2 + (a.y - camera.y)^2 < 14^2 then
            projectedWireframe.drawWorldLine(drawList, screen, a, edge[2], surfaceLine)
        end
    end

    local rows = self.fitGrid
    if rows and rows[1] then
        local dx, dy = (size.x - .6) / #rows[1], (size.y - .6) / #rows
        for iy, row in ipairs(rows) do
            for ix, accepted in ipairs(row) do
                if not accepted then
                    local x = -size.x / 2 + .3 + (ix - 1) * dx
                    local y = -size.y / 2 + .3 + (iy - 1) * dy
                    rectangle(x, y, x + dx, y + dy, rejectedLine)
                end
            end
        end
    end
end

return navigationArea
