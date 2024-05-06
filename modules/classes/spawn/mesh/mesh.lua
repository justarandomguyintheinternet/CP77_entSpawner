local spawnable = require("modules/classes/spawn/spawnable")
local mesh = setmetatable({}, { __index = spawnable })
local builder = require("modules/utils/entityBuilder")

function mesh:new()
	local o = spawnable.new(self)

    o.spawnListType = "list"
    o.dataType = "Static Mesh"
    o.spawnDataPath = "data/spawnables/mesh/"
    o.modulePath = "mesh/mesh"

    o.scale = { x = 1, y = 1, z = 1 }

    setmetatable(o, { __index = self })
   	return o
end

function mesh:spawn()
    local mesh = self.spawnData
    self.spawnData = "base\\game_object.ent"

    spawnable.spawn(self)
    self.spawnData = mesh

    builder.registerCallback(self.entityID, function (entity)
        local component = entMeshComponent.new()
        component.name = "mesh"
        component.mesh = ResRef.FromString(self.spawnData)
        component.visualScale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)
        entity:AddComponent(component)
    end)
end

function mesh:save()
    local data = spawnable.save(self)
    data.scale = self.scale

    return data
end

function mesh:updateScale()
    local entity = self:getEntity()
    if not entity then return end

    local component = entity:FindComponentByName("mesh")
    component.visualScale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)

    component:Toggle(false)
    component:Toggle(true)
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
    ImGui.SameLine()
    ImGui.PopItemWidth()
end

function mesh:export()
    local data = spawnable.export(self)
    data.type = "worldMeshNode"
    data.scale = self.scale
    data.data = {
        mesh = {
            DepotPath = {
                ["$storage"] = "string",
                ["$value"] = self.spawnData
            }
        },
        intensity = self.strength
    }

    return data
end

return mesh