local mesh = require("modules/classes/spawn/mesh/mesh")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local Cron = require("modules/utils/Cron")

---Class for worldRotatingMeshNode
---@class rotatingMesh : mesh
---@field public duration number
---@field public axis integer
---@field public reverse boolean
---@field private axisTypes table
---@field private cronID number
local rotatingMesh = setmetatable({}, { __index = mesh })

function rotatingMesh:new()
	local o = mesh.new(self)

    o.spawnListType = "list"
    o.dataType = "Rotating Mesh"
    o.modulePath = "mesh/rotatingMesh"
    o.node = "worldRotatingMeshNode"
    o.description = "Places a static mesh, from a given .mesh file, and rotates it around a given axis"
    o.icon = IconGlyphs.FormatRotate90

    o.duration = 5
    o.axis = 0
    o.reverse = false
    o.axisTypes = utils.enumTable("gameTransformAnimation_RotateOnAxisAxis")
    o.hideGenerate = true

    o.cronID = nil

    setmetatable(o, { __index = self })
   	return o
end

function rotatingMesh:onAssemble(entity)
    mesh.onAssemble(self, entity)

    if self.isAssetPreview then return end

    self.cronID = Cron.OnUpdate(function ()
        local entity = self:getEntity()

        if not entity then return end

        local rotation = ((Cron.time % self.duration) / self.duration) * 360
        if self.reverse then rotation = -rotation end

        local transform = entity:GetWorldTransform()
        transform:SetPosition(self.position)

        local angle = EulerAngles.new(0, 0, rotation)
        if self.axis == 0 then
            angle = EulerAngles.new(0, rotation, 0)
        elseif self.axis == 1 then
            angle = EulerAngles.new(rotation, 0, 0)
        end

        entity:FindComponentByName("mesh"):SetLocalOrientation(angle:ToQuat())
    end)
end

function rotatingMesh:despawn()
    if self.cronID then
        Cron.Halt(self.cronID)
        self.cronID = nil
    end

    mesh.despawn(self)
end

function rotatingMesh:save()
    local data = mesh.save(self)
    data.duration = self.duration
    data.axis = self.axis
    data.reverse = self.reverse

    return data
end

function rotatingMesh:draw()
    mesh.draw(self)

    style.mutedText("Duration")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.duration = style.trackedDragFloat(self.object, "##duration", self.duration, 0.01, 0.01, 9999, "%.2f Seconds", 95)

    style.mutedText("Axis")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.axis = style.trackedCombo(self.object, "##axis", self.axis, self.axisTypes, 95)

    style.mutedText("Reverse")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.reverse = style.trackedCheckbox(self.object, "##reverse", self.reverse)
end

function rotatingMesh:export()
    local data = mesh.export(self)
    data.type = "worldRotatingMeshNode"
    data.data.fullRotationTime = self.duration
    data.data.reverseDirection = self.reverse and 1 or 0
    data.data.rotationAxis = self.axisTypes[self.axis + 1]

    return data
end

return rotatingMesh