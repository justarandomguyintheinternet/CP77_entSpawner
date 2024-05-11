local mesh = require("modules/classes/spawn/mesh/mesh")
local builder = require("modules/utils/entityBuilder")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")

---Class for worldRotatingMeshNode
---@class rotatingMesh : mesh
---@field public duration number
---@field public axis integer
local rotatingMesh = setmetatable({}, { __index = mesh })

function rotatingMesh:new()
	local o = mesh.new(self)

    o.spawnListType = "list"
    o.dataType = "Rotating Mesh"
    o.spawnDataPath = "data/spawnables/mesh/"
    o.modulePath = "mesh/rotatingMesh"

    o.duration = 50
    o.axis = 0

    setmetatable(o, { __index = self })
   	return o
end

function rotatingMesh:spawn()
    local mesh = self.spawnData
    self.spawnData = "base\\entity.ent"

    spawnable.spawn(self)
    self.spawnData = mesh

    builder.registerAssembleCallback(self.entityID, function (entity)
        local component = entMeshComponent.new()
        component.name = "mesh"
        component.mesh = ResRef.FromString(self.spawnData)
        component.visualScale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)
        component.meshAppearance = self.app

        local rotate = gameTransformAnimatorComponent.new()
        rotate.name = "rotate"
        local animation = gameTransformAnimationDefinition.new()
        animation.autoStart = true
        animation.looping = true
        local timeline = gameTransformAnimationTimeline.new()
        local item = gameTransformAnimationTrackItem.new()
        item.duration = self.duration
        local impl = gameTransformAnimation_RotateOnAxis.new()
        impl.axis = Enum.new("gameTransformAnimation_RotateOnAxisAxis", self.axis)
        impl.numberOfFullRotations = 1
        item.impl = impl
        timeline.items = {item}
        animation.timeline = timeline
        rotate.animations = {animation}
        print(rotate.animations[1].timeline.items[1])

        entity:AddComponent(rotate)
        entity:AddComponent(component)

        local d = entity:FindComponentByName("rotate").animations[1].timeline.items[1]
        -- print(d)
        -- print(d.impl.axis)
    end)
end

function rotatingMesh:save()
    local data = spawnable.save(self)
    data.scale = self.scale
    data.duration = self.duration
    data.axis = self.axis

    return data
end

function rotatingMesh:export()
    local app = self.app
    if app == "" then
        app = "default"
    end

    local data = mesh.export(self)
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

return rotatingMesh