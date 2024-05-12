local mesh = require("modules/classes/spawn/mesh/mesh")
local spawnable = require("modules/classes/spawn/spawnable")
local builder = require("modules/utils/entityBuilder")
local utils = require("modules/utils/utils")

---Class for worldRotatingMeshNode
---@class rotatingMesh : mesh
---@field public duration number
---@field public axis integer
---@field public reverse boolean
local rotatingMesh = setmetatable({}, { __index = mesh })

local axisTypes = utils.enumTable("gameTransformAnimation_RotateOnAxisAxis")

function rotatingMesh:new()
	local o = mesh.new(self)

    o.spawnListType = "list"
    o.dataType = "Rotating Mesh"
    o.spawnDataPath = "data/spawnables/mesh/"
    o.modulePath = "mesh/rotatingMesh"

    o.duration = 50
    o.axis = 0
    o.reverse = false

    setmetatable(o, { __index = self })
   	return o
end

function rotatingMesh:spawn()
    local mesh = self.spawnData
    self.spawnData = "base\\spawner\\rotating_entity.ent"

    spawnable.spawn(self)
    self.spawnData = mesh

    builder.registerAssembleCallback(self.entityID, function (entity)
        local meshComponent = entMeshComponent.new()
        meshComponent.name = "mesh"
        meshComponent.mesh = ResRef.FromString(self.spawnData)
        meshComponent.visualScale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)
        meshComponent.meshAppearance = self.app

        entity:AddComponent(meshComponent)

        local rotate = entity:FindComponent("rotate")
        rotate.animations[1].timeline.items[1].impl.axis = Enum.new("gameTransformAnimation_RotateOnAxisAxis", self.axis)
        rotate.animations[1].timeline.items[1].duration = self.duration
        rotate.animations[1].timeline.items[1].impl.reverseDirection = self.reverse
        print(rotate.animations[1].timeline.items[1].impl.axis, rotate.animations[1].timeline.items[1].duration, rotate.animations[1].timeline.items[1].impl.reverseDirection)
    end)
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

---@param changed boolean
---@protected
function rotatingMesh:updateParameters(changed)
    if not changed then return end

    local entity = self:getEntity()

    if not entity then return end

    local rotate = entity:FindComponent("rotate")
    rotate.animations[1].timeline.items[1].impl.axis = Enum.new("gameTransformAnimation_RotateOnAxisAxis", self.axis)
    rotate.animations[1].timeline.items[1].duration = self.duration
    rotate.animations[1].timeline.items[1].impl.reverseDirection = self.reverse
end

function rotatingMesh:draw()
    mesh.draw(self)

    ImGui.PushItemWidth(150)

    self.duration, changed = ImGui.DragFloat("##duration", self.duration, 0.01, -9999, 9999, "%.2f Duration")
    self:updateParameters(changed)
    ImGui.SameLine()

    self.reverse, changed = ImGui.Checkbox("Reverse", self.reverse)
    self:updateParameters(changed)
    ImGui.SameLine()

    self.axis, changed = ImGui.Combo("Axis", self.axis, axisTypes, #axisTypes)
    self:updateParameters(changed)

    ImGui.PopItemWidth()
end

function rotatingMesh:export()
    local data = mesh.export(self)
    data.type = "worldRotatingMeshNode"
    data.data.fullRotationTime = self.duration
    data.reverseDirection = self.reverse
    data.rotationAxis = axisTypes[self.axis]

    return data
end

return rotatingMesh