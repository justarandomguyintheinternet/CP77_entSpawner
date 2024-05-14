local mesh = require("modules/classes/spawn/mesh/mesh")
local spawnable = require("modules/classes/spawn/spawnable")
local builder = require("modules/utils/entityBuilder")
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
    o.spawnDataPath = "data/spawnables/mesh/"
    o.modulePath = "mesh/rotatingMesh"

    o.duration = 5
    o.axis = 0
    o.reverse = false
    o.axisTypes = utils.enumTable("gameTransformAnimation_RotateOnAxisAxis")

    o.cronID = nil

    setmetatable(o, { __index = self })
   	return o
end

function rotatingMesh:spawn()
    local mesh = self.spawnData
    self.spawnData = "base\\spawner\\empty_entity.ent"

    spawnable.spawn(self)
    self.spawnData = mesh

    builder.registerAssembleCallback(self.entityID, function (entity)
        local meshComponent = entMeshComponent.new()
        meshComponent.name = "mesh"
        meshComponent.mesh = ResRef.FromString(self.spawnData)
        meshComponent.visualScale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)
        meshComponent.meshAppearance = self.app

        entity:AddComponent(meshComponent)

        self.cronID = Cron.OnUpdate(function ()
            local entity = self:getEntity()

            if not entity then return end

            local rotation = ((Cron.time % self.duration) / self.duration) * 360
            if self.reverse then rotation = -rotation end

            local transform = entity:GetWorldTransform()
            transform:SetPosition(self.position)

            local angle = EulerAngles.new(self.rotation.roll, self.rotation.pitch, rotation)
            if self.axis == 0 then
                angle = EulerAngles.new(rotation, self.rotation.pitch, self.rotation.yaw)
            elseif self.axis == 1 then
                angle = EulerAngles.new(self.rotation.roll, rotation, self.rotation.yaw)
            end

            transform:SetOrientationEuler(angle)
            entity:SetWorldTransform(transform)
        end)
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

function rotatingMesh:getExtraHeight()
    return mesh.getExtraHeight(self) + ImGui.GetStyle().ItemSpacing.y + ImGui.GetFrameHeight()
end

function rotatingMesh:draw()
    mesh.draw(self)

    ImGui.PushItemWidth(150)

    self.duration, changed = ImGui.DragFloat("##duration", self.duration, 0.01, -9999, 9999, "%.2f Duration")
    self.duration = math.max(self.duration, 0.01)
    ImGui.SameLine()

    self.reverse, changed = ImGui.Checkbox("Reverse", self.reverse)
    ImGui.SameLine()
    self.axis, changed = ImGui.Combo("Axis", self.axis, self.axisTypes, #self.axisTypes)

    ImGui.PopItemWidth()
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