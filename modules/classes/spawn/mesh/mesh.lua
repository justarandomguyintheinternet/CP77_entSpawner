local spawnable = require("modules/classes/spawn/spawnable")
local builder = require("modules/utils/entityBuilder")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local cache = require("modules/utils/cache")
local visualizer = require("modules/utils/visualizer")
local history = require("modules/utils/history")
local intersection = require("modules/utils/editor/intersection")

local colliderShapes = { "Box", "Capsule", "Sphere" }

---Class for worldMeshNode
---@class mesh : spawnable
---@field public apps table
---@field public appIndex integer
---@field public scale {x: number, y: number, z: number}
---@field public bBox table {min: Vector4, max: Vector4}
---@field public colliderShape integer
---@field public hideGenerate boolean
local mesh = setmetatable({}, { __index = spawnable })

function mesh:new()
	local o = spawnable.new(self)

    o.spawnListType = "list"
    o.dataType = "Static Mesh"
    o.spawnDataPath = "data/spawnables/mesh/all/"
    o.modulePath = "mesh/mesh"
    o.node = "worldMeshNode"
    o.description = "Places a static mesh, from a given .mesh file. This will not have any collision, but has an option to generate a fitting collider"
    o.icon = IconGlyphs.CubeOutline

    o.apps = {}
    o.appIndex = 0
    o.scale = { x = 1, y = 1, z = 1 }
    o.bBox = { min = Vector4.new(-0.5, -0.5, -0.5, 0), max = Vector4.new( 0.5, 0.5, 0.5, 0) }

    o.colliderShape = 0
    o.hideGenerate = false

    o.uk10 = 1040

    setmetatable(o, { __index = self })
   	return o
end

function mesh:loadSpawnData(data, position, rotation)
    spawnable.loadSpawnData(self, data, position, rotation)

    -- Get from cache
    self.apps = cache.getValue(self.spawnData .. "_apps")
    self.bBox.max = cache.getValue(self.spawnData .. "_bBox_max")
    self.bBox.min = cache.getValue(self.spawnData .. "_bBox_min")

    -- Something is missing
    if (not self.apps) or (not self.bBox.max) or (not self.bBox.min) then
        self.bBox.max = Vector4.new(0.5, 0.5, 0.5, 0) -- Temp values, so that onAssemble//updateScale can work
        self.bBox.min = Vector4.new(-0.5, -0.5, -0.5, 0)

        self.apps = {}
        builder.registerLoadResource(self.spawnData, function (resource)
            for _, appearance in ipairs(resource.appearances) do
                table.insert(self.apps, appearance.name.value)
            end

            self.bBox.min = resource.boundingBox.Min
            self.bBox.max = resource.boundingBox.Max
            visualizer.updateScale(entity, self:getArrowSize(), "arrows")

            -- Save to cache
            cache.addValue(self.spawnData .. "_apps", self.apps)
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

    visualizer.updateScale(entity, self:getArrowSize(), "arrows")
end

function mesh:spawn()
    local mesh = self.spawnData
    self.spawnData = "base\\spawner\\empty_entity.ent"

    spawnable.spawn(self)
    self.spawnData = mesh
end

function mesh:save()
    local data = spawnable.save(self)
    data.scale = { x = self.scale.x, y = self.scale.y, z = self.scale.z }

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

    visualizer.updateScale(entity, self:getArrowSize(), "arrows")
    self:setOutline(self.outline)
end

function mesh:getSize()
    return { x = (self.bBox.max.x - self.bBox.min.x) * math.abs(self.scale.x), y = (self.bBox.max.y - self.bBox.min.y) * math.abs(self.scale.y), z = (self.bBox.max.z - self.bBox.min.z) * math.abs(self.scale.z) }
end

function mesh:getCenter()
    local size = self:getSize()
    local offset = Vector4.new(
        (self.bBox.min.x * self.scale.x) + size.x / 2,
        (self.bBox.min.y * self.scale.y) + size.y / 2,
        (self.bBox.min.z * self.scale.z) + size.z / 2,
        0
    )
    offset = self.rotation:ToQuat():Transform(offset)

    return Vector4.new(
        self.position.x + offset.x,
        self.position.y + offset.y,
        self.position.z + offset.z,
        0
    )
end

function mesh:calculateIntersection(origin, ray)
    if not self:getEntity() then
        return { hit = false }
    end

    local scaleFactor = intersection.getResourcePathScalingFactor(self.spawnData, self:getSize())

    local scaledBBox = {
        min = {  x = self.bBox.min.x * math.abs(self.scale.x) * scaleFactor.x, y = self.bBox.min.y * math.abs(self.scale.y) * scaleFactor.y, z = self.bBox.min.z * math.abs(self.scale.z) * scaleFactor.z },
        max = {  x = self.bBox.max.x * math.abs(self.scale.x) * scaleFactor.x, y = self.bBox.max.y * math.abs(self.scale.y) * scaleFactor.y, z = self.bBox.max.z * math.abs(self.scale.z) * scaleFactor.z }
    }
    local result = intersection.getBoxIntersection(origin, ray, self.position, self.rotation, scaledBBox)

    return {
        hit = result.hit,
        position = result.position,
        collisionType = "bbox",
        distance = result.distance,
        bBox = scaledBBox,
        objectOrigin = self.position,
        objectRotation = self.rotation
    }
end

function mesh:draw()
    spawnable.draw(self)

    style.pushGreyedOut(#self.apps == 0)

    local list = self.apps

    if #self.apps == 0 then
        list = {"No apps"}
    end

    local index, changed = style.trackedCombo(self.object, "##app", self.appIndex, list, 110)
    style.tooltip("Select the mesh appearance")
    if changed and #self.apps > 0 then
        self.appIndex = index
        self.app = self.apps[self.appIndex + 1]

        local entity = self:getEntity()

        if entity then
            entity:FindComponentByName("mesh").meshAppearance = CName.new(self.app)
            entity:FindComponentByName("mesh"):LoadAppearance()

            self:setOutline(self.outline)
        end
    end
    style.popGreyedOut(#self.apps == 0)

    if self.hideGenerate then
        return
    end

    ImGui.SetNextItemWidth(110 * style.viewSize)
    self.colliderShape, changed = ImGui.Combo("##colliderShape", self.colliderShape, colliderShapes, #colliderShapes)

    ImGui.SameLine()

    if ImGui.Button("Generate Collider") then
        self:generateCollider()
    end
end

function mesh:getProperties()
    local properties = spawnable.getProperties(self)
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

---@protected
function mesh:generateCollider()
    local group = require("modules/classes/editor/positionableGroup"):new(self.object.sUI)
    group.name = self.object.name .. "_grouped"
    group:setParent(self.object.parent, utils.indexValue(self.object.parent.childs, self.object) + 1)
    local insertGroup = history.getInsert({ group })

    local collider = require("modules/classes/spawn/collision/collider"):new()

    local x = (self.bBox.max.x - self.bBox.min.x) * self.scale.x
    local y = (self.bBox.max.y - self.bBox.min.y) * self.scale.y
    local z = (self.bBox.max.z - self.bBox.min.z) * self.scale.z

    local pos = Vector4.new(self.position.x, self.position.y, self.position.z, 0)
    local rotation = EulerAngles.new(self.rotation.roll, self.rotation.pitch, self.rotation.yaw)

    local offset = Vector4.new((self.bBox.min.x * self.scale.x) + x / 2, (self.bBox.min.y * self.scale.y) + y / 2, (self.bBox.min.z * self.scale.z) + z / 2, 0)
    offset = self.rotation:ToQuat():Transform(offset)
    pos = Game['OperatorAdd;Vector4Vector4;Vector4'](pos, offset)

    local radius = math.max(x, y) / 2
    local height = z - radius * 2
    if self.colliderShape == 1 then
        if x > z or y > z then
            radius = z / 2
            height = math.max(x, y) - radius * 2
            rotation.roll = rotation.roll + 90

            if y > x then
                rotation.yaw = rotation.yaw + 90
            end
        end
    end

    local data = {
        extents = { x = x / 2, y = y / 2, z = z / 2 },
        radius = radius,
        height = height,
        shape = self.colliderShape
    }

    collider:loadSpawnData(data, pos, rotation)

    local colliderElement = require("modules/classes/editor/spawnableElement"):new(self.object.sUI)
    colliderElement:load({
        name = self.object.name .. "_collider",
        spawnable = collider:save(),
        modulePath = "modules/classes/editor/spawnableElement"
    })
    colliderElement:setParent(group)
    local insertCollider = history.getInsert({ colliderElement })

    local remove = history.getRemove({ self.object })
    self.object:setParent(group)
    local insert = history.getInsert({ self.object })
    local move = history.getMove(remove, insert)

    history.addAction({
        undo = function ()
            move.undo()
            insertCollider.undo()
            insertGroup.undo()
        end,
        redo = function ()
            insertGroup.redo()
            history.spawnedUI.cachePaths()
            insertCollider.redo()
            move.redo()
        end
    })

    self.object.headerOpen = false
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