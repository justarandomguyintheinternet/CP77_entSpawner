local mesh = require("modules/classes/spawn/mesh/mesh")
local style = require("modules/ui/style")
local utils = require("modules/utils/core/utils")
local cache = require("modules/utils/game/cache")
local history = require("modules/utils/project/history")
local settings = require("modules/utils/core/settings")
local projectedWireframe = require("modules/utils/editor/projectedWireframe")
local roadIntersectionPorts = require("modules/utils/data/roadIntersectionPorts")

local DEFAULT_ROAD_LENGTH = 12
local PORT_ARROW_LENGTH = 4
local PORT_HOVER_COLOR = 0xFF2E8BFF

---Class for worldMeshNode road intersections, whose road ports bended meshes join onto
---@class roadIntersection : mesh
---@field private hoveredPort integer? Port row hovered in the properties this frame.
local roadIntersection = setmetatable({}, { __index = mesh })

function roadIntersection:new()
	local o = mesh.new(self)

    o.dataType = "Static Road Intersection"
    o.modulePath = "mesh/roadIntersection"
    o.spawnDataPath = "data/spawnables/mesh/roadIntersection/"
    o.description = "Places a vanilla road intersection mesh. Bended meshes join its road ports with Snap Start/End, Alt+drag and magnetic ends."
    o.icon = IconGlyphs.RoadVariant

    setmetatable(o, { __index = self })
    o:setDefaultStreamingPreset("District")
   	return o
end

---Intersection meshes are all named `s0_re.mesh`, so the folder names them.
---@param path string
---@return string
function roadIntersection.getAssetName(path)
    return tostring(path):match("([^\\/]+)[\\/][^\\/]+$") or utils.getFileName(path)
end

local function normalize(v)
    local length = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if length < 0.000001 then return { x = 0, y = 0, z = 0 } end
    return { x = v.x / length, y = v.y / length, z = v.z / length }
end

local function cross(a, b)
    return {
        x = a.y * b.z - a.z * b.y,
        y = a.z * b.x - a.x * b.z,
        z = a.x * b.y - a.y * b.x
    }
end

---Road ports in world space, shaped like bended mesh ends. A port reads as the end of a road leaving
---the intersection, so `isStart` is false and `forward` points away from it.
---@return table[] ends `{ mesh, name, isStart, frame, port, road }`
function roadIntersection:getPortEnds()
    local ends = {}
    local ports = roadIntersectionPorts.getPorts(self.spawnData)
    if not ports or not self.rotation then return ends end

    local quat = self.rotation:ToQuat()
    local scale = self.scale or { x = 1, y = 1, z = 1 }
    local name = self.object and self.object.name or roadIntersection.getAssetName(self.spawnData)

    local function toWorld(v, isDirection)
        local rotated = quat:Transform(Vector4.new(v[1] * scale.x, v[2] * scale.y, v[3] * scale.z, 0))
        if isDirection then
            return normalize({ x = rotated.x, y = rotated.y, z = rotated.z })
        end
        return { x = self.position.x + rotated.x, y = self.position.y + rotated.y, z = self.position.z + rotated.z }
    end

    for index, port in ipairs(ports) do
        local forward = toWorld(port.forward, true)
        local right = normalize(cross(forward, toWorld(port.up, true)))

        table.insert(ends, {
            mesh = self,
            name = string.format("%s port %d (%s)", name, index, roadIntersectionPorts.getRoadProfile(port.road) or "road"),
            isStart = false,
            port = true,
            road = port.road,
            frame = {
                position = toWorld(port.position, false),
                forward = forward,
                right = right,
                up = normalize(cross(right, forward))
            }
        })
    end

    return ends
end

---Rest length of a bended mesh, from the static rig table.
---@param path string
---@return number
local function getRestLength(path)
    local points = cache.getDefaultBendedPathPoints(path)
    local length = 0
    for index = 2, #(points or {}) do
        local a, b = points[index - 1], points[index]
        length = length + math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2)
    end
    return length > 0.01 and length or DEFAULT_ROAD_LENGTH
end

---Rotates a vector around world Z.
local function rotateYaw(v, degrees)
    local angle = math.rad(degrees)
    local c, s = math.cos(angle), math.sin(angle)
    return { x = v.x * c - v.y * s, y = v.x * s + v.y * c, z = v.z }
end

---Spawns the port's vanilla road next to this intersection, straight at rest length, its start joined to the port.
---@param index integer
---@return spawnableElement?
function roadIntersection:spawnPortRoad(index)
    local port = self:getPortEnds()[index]
    if not port or not port.road or not self.object or not self.object.sUI then return nil end

    -- Yaw-only node: local +Y follows the port, slope and bank go into the curve.
    local frame = port.frame
    local yaw = math.deg(math.atan2(-frame.forward.x, frame.forward.y))
    local forward = rotateYaw(frame.forward, -yaw)
    local right = rotateYaw(frame.right, -yaw)
    local up = rotateYaw(frame.up, -yaw)
    local roll = require("modules/classes/spawn/mesh/bendedMesh").pathPointsFromMatrices({
        { X = right, Y = forward, Z = up, W = { x = 0, y = 0, z = 0 } }
    }, 0)[1].roll
    local length = getRestLength(port.road)

    local sUI = self.object.sUI
    local element = require("modules/classes/editor/spawnableElement"):new(sUI)
    element:load({
        name = utils.getFileName(port.road),
        modulePath = element.modulePath,
        spawnable = {
            modulePath = "mesh/bendedMesh",
            spawnData = port.road,
            position = { x = frame.position.x, y = frame.position.y, z = frame.position.z, w = 0 },
            rotation = { roll = 0, pitch = 0, yaw = yaw },
            curvePoints = {
                { x = 0, y = 0, z = 0, roll = roll, dir = forward },
                { x = forward.x * length, y = forward.y * length, z = forward.z * length, roll = roll }
            }
        }
    })

    local parent = self.object.parent or sUI.root
    local position = self.object.parent and utils.indexValue(parent.childs, self.object) + 1 or nil
    element:setParent(parent, position)
    sUI.unselectAll()
    element:setSelected(true)
    sUI.scrollToSelected = true

    history.addAction(history.getInsert({ element }))
    return element
end

function roadIntersection:draw()
    mesh.draw(self)

    local ports = roadIntersectionPorts.getPorts(self.spawnData) or {}

    style.mutedText("Road Ports")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    ImGui.Text(tostring(#ports))
    style.tooltip("Points where a bended road joins this intersection, measured on the vanilla roads.")

    if #ports > 0 then
        style.mutedText("Suggested roads:")
    end

    local indent = ImGui.GetCursorPosX() + 8 * style.viewSize
    for index, port in ipairs(ports) do
        ImGui.SetCursorPosX(indent)
        ImGui.Text(index .. ".")
        local hovered = ImGui.IsItemHovered()

        ImGui.SameLine()
        ImGui.BeginDisabled(not port.road)
        if ImGui.Button(IconGlyphs.PlusBoxOutline .. "##spawnPortRoad" .. index) then
            self:spawnPortRoad(index)
        end
        hovered = hovered or ImGui.IsItemHovered()
        style.tooltip("Spawn this road joined to the port")
        ImGui.SameLine()
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.ContentCopy .. "##copyPortRoad" .. index) then
            ImGui.SetClipboardText(port.road)
            ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, "Copied road path to clipboard"))
        end
        hovered = hovered or ImGui.IsItemHovered()
        style.pushButtonNoBG(false)
        style.tooltip("Copy road path to clipboard")
        ImGui.EndDisabled()

        ImGui.SameLine()
        style.mutedText(string.format("(%.1f m wide)", port.width))
        hovered = hovered or ImGui.IsItemHovered()
        style.tooltip(port.road or "No vanilla road recorded")
        ImGui.SameLine()
        ImGui.Text(roadIntersectionPorts.getRoadProfile(port.road) or "unknown road")
        hovered = hovered or ImGui.IsItemHovered()
        style.tooltip(port.road or "No vanilla road recorded")

        if hovered then
            self.hoveredPort = index
        end
    end
end

function roadIntersection:wantsViewportOverlay()
    return not self.isAssetPreview and self.object ~= nil and self.object.selected == true
end

---Numbered port markers, each with a short arrow along its road. The port hovered in the properties is highlighted.
---@param screen table
---@param drawList table
function roadIntersection:drawViewportOverlay(screen, drawList)
    -- Set by `draw` every frame the row is hovered, consumed here.
    local hovered = self.hoveredPort
    self.hoveredPort = nil
    if not self:wantsViewportOverlay() then return end

    local markerColor, labelColor = 0xFFA35200, 0xFFDCD8D1
    if settings.wireframeColorStyle == 2 then
        markerColor, labelColor = 0xFFFF9900, 0xFF000000
    end

    for index, port in ipairs(self:getPortEnds()) do
        local color = index == hovered and PORT_HOVER_COLOR or markerColor
        local p, forward = port.frame.position, port.frame.forward
        local position = Vector4.new(p.x, p.y, p.z, 1)
        local tip = Vector4.new(
            p.x + forward.x * PORT_ARROW_LENGTH,
            p.y + forward.y * PORT_ARROW_LENGTH,
            p.z + forward.z * PORT_ARROW_LENGTH,
            1
        )

        projectedWireframe.drawWorldLine(drawList, screen, position, tip, { color = color, thickness = 2 })
        projectedWireframe.drawWorldMarker(drawList, screen, position, {
            color = color,
            labelColor = index == hovered and 0xFF000000 or labelColor,
            text = tostring(index),
            radius = 6 * style.viewSize,
            innerRadius = 2.5 * style.viewSize,
            badgeOffsetY = -15 * style.viewSize,
            fontRatio = 0.8,
            clampToScreen = false
        })
    end
end

return roadIntersection
