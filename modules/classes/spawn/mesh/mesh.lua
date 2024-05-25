local spawnable = require("modules/classes/spawn/spawnable")
local builder = require("modules/utils/entityBuilder")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local cache = require("modules/utils/cache")
local visualizer = require("modules/utils/visualizer")

local colliderShapes = { "Box", "Capsule", "Sphere" }

---Class for worldMeshNode
---@class mesh : spawnable
---@field public apps table
---@field public appIndex integer
---@field public scale table {x: number, y: number, z: number}
---@field public bBox table {min: Vector4, max: Vector4}
local mesh = setmetatable({}, { __index = spawnable })

function mesh:new(object)
	local o = spawnable.new(self, object)

    o.spawnListType = "list"
    o.dataType = "Static Mesh"
    o.spawnDataPath = "data/spawnables/mesh/all/"
    o.modulePath = "mesh/mesh"

    o.apps = {}
    o.appIndex = 0
    o.scale = { x = 1, y = 1, z = 1 }
    o.bBox = { min = Vector4.new(-0.5, -0.5, -0.5, 0), max = Vector4.new( 0.5, 0.5, 0.5, 0) }

    o.colliderShape = 0

    setmetatable(o, { __index = self })
   	return o
end

function mesh:loadSpawnData(data, position, rotation)
    spawnable.loadSpawnData(self, data, position, rotation)

    self.apps = cache.getValue(self.spawnData)
    self.bBox.max = cache.getValue(self.spawnData .. "_bBox_max")
    self.bBox.min = cache.getValue(self.spawnData .. "_bBox_min")

    if (not self.apps) or (not self.bBox.max) or (not self.bBox.min) then
        self.apps = {}
        builder.registerLoadResource(self.spawnData, function (resource)
            for _, appearance in ipairs(resource.appearances) do
                table.insert(self.apps, appearance.name.value)
            end

            self.bBox.min = resource.boundingBox.Min
            self.bBox.max = resource.boundingBox.Max

            visualizer.updateScale(entity, self:getVisualScale(), "arrows")

            cache.addValue(self.spawnData, self.apps)
            cache.addValue(self.spawnData .. "_bBox_max", utils.fromVector(self.bBox.max))
            cache.addValue(self.spawnData .. "_bBox_min", utils.fromVector(self.bBox.min))
        end)
    else
        self.bBox.max = ToVector4(self.bBox.max)
        self.bBox.min = ToVector4(self.bBox.min)
    end

    self.appIndex = math.max(utils.indexValue(self.apps, self.app) - 1, 0)
end

function mesh:onAssemble(entity)
    spawnable.onAssemble(self, entity)
    local component = entMeshComponent.new()
    component.name = "mesh"
    component.mesh = ResRef.FromString(self.spawnData)
    component.visualScale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)
    component.meshAppearance = self.app
    entity:AddComponent(component)

    visualizer.updateScale(entity, self:getVisualScale(), "arrows")
end

function mesh:spawn()
    local mesh = self.spawnData
    self.spawnData = "base\\spawner\\empty_entity.ent"

    spawnable.spawn(self)
    self.spawnData = mesh
end

function mesh:save()
    local data = spawnable.save(self)
    data.scale = self.scale

    return data
end

---@protected
function mesh:updateScale()
    local entity = self:getEntity()
    if not entity then return end

    local component = entity:FindComponentByName("mesh")
    component.visualScale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)

    component:Toggle(false)
    component:Toggle(true)

    visualizer.updateScale(entity, self:getVisualScale(), "arrows")
end

function mesh:getVisualScale()
    local max = math.max(self.scale.x, self.scale.y, self.scale.z)
    return { x = max, y = max, z = max }
end

function mesh:getExtraHeight()
    return 6 * ImGui.GetStyle().ItemSpacing.y + ImGui.GetFrameHeight() * 3
end

function mesh:draw()
    spawnable.draw(self)

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    ImGui.PushItemWidth(150)
    self.scale.x, changed = ImGui.DragFloat("##xsize", self.scale.x, 0.01, -9999, 9999, "%.3f X Scale")
    if changed then
        self:updateScale()
    end
    ImGui.SameLine()
    self.scale.y, changed = ImGui.DragFloat("##ysize", self.scale.y, 0.01, -9999, 9999, "%.3f Y Scale")
    if changed then
        self:updateScale()
    end
    ImGui.SameLine()
    self.scale.z, changed = ImGui.DragFloat("##zsize", self.scale.z, 0.01, -9999, 9999, "%.3f Z Scale")
    if changed then
        self:updateScale()
    end
    ImGui.PopItemWidth()

    style.pushGreyedOut(#self.apps == 0)

    local list = self.apps

    if #self.apps == 0 then
        list = {"No apps"}
    end

    ImGui.SetNextItemWidth(150)
    local index, changed = ImGui.Combo("##app", self.appIndex, list, #list)
    style.tooltip("Select the mesh appearance")
    if changed and #self.apps > 0 then
        self.appIndex = index
        self.app = self.apps[self.appIndex + 1]

        local entity = self:getEntity()

        if entity then
            entity:FindComponentByName("mesh").meshAppearance = CName.new(self.app)
            entity:FindComponentByName("mesh"):LoadAppearance()
        end
    end
    style.popGreyedOut(#self.apps == 0)

    ImGui.SameLine()

    if ImGui.Button("Copy Path to Clipboard") then
        ImGui.SetClipboardText(self.spawnData)
    end
    style.tooltip("Copies the mesh path to the clipboard")

    if ImGui.Button("Generate Collider") then
        local path = self.object:addGroupToParent(self.object.name .. "_grouped")
        self.object:setSelectedGroupByPath(path)
        self.object:moveToSelectedGroup()

        local collider = require("modules/classes/spawn/collision/collider"):new()

        local x = (self.bBox.max.x - self.bBox.min.x) * self.scale.x
        local y = (self.bBox.max.y - self.bBox.min.y) * self.scale.y
        local z = (self.bBox.max.z - self.bBox.min.z) * self.scale.z

        local pos = Vector4.new(self.position.x, self.position.y, self.position.z, 0)

        local offset = Vector4.new((self.bBox.min.x * self.scale.x) + x / 2, (self.bBox.min.y * self.scale.y) + y / 2, (self.bBox.min.z * self.scale.z) + z / 2, 0)
        offset = self.rotation:ToQuat():Transform(offset)
        pos = Game['OperatorAdd;Vector4Vector4;Vector4'](pos, offset)

        local radius = math.max(x, y, z) / 2
        if self.colliderShape == 1 then
            radius = math.max(x, y) / 2
        end

        local data = {
            extents = { x = x / 2, y = y / 2, z = z / 2 },
            radius = radius,
            height = z - 1,
            shape = self.colliderShape
        }

        collider:loadSpawnData(data, pos, self.rotation)

        self.object:addObjectToParent(collider, collider:generateName(self.object.name .. "_collider"), false)
    end

    ImGui.SameLine()

    ImGui.SetNextItemWidth(150)
    self.colliderShape, changed = ImGui.Combo("##colliderShape", self.colliderShape, colliderShapes, #colliderShapes)
end

function mesh:export()
    local app = self.app
    if app == "" then
        app = "default"
    end

    local data = spawnable.export(self)
    data.type = "worldMeshNode"
    data.scale = self.scale
    data.data = {
        mesh = {
            DepotPath = {
                ["$storage"] = "string",
                ["$value"] = self.spawnData
            },
        },
        meshAppearance = {
            ["$storage"] = "string",
            ["$value"] = app
        }
    }

    return data
end

return mesh