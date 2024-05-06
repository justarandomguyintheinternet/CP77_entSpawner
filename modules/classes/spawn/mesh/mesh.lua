local spawnable = require("modules/classes/spawn/spawnable")
local mesh = setmetatable({}, { __index = spawnable })
local builder = require("modules/utils/entityBuilder")

function mesh:new()
	local o = spawnable.new(self)

    o.spawnListType = "list"
    o.dataType = "Static Mesh"
    o.spawnDataPath = "data/spawnables/mesh/"
    o.modulePath = "mesh/mesh"

    o.scale = { 1, 1, 1 }

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
        entity:AddComponent(component)
    end)
end

function mesh:draw()
    spawnable.draw(self)

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()
end

function mesh:export()
    local data = spawnable.export(self)
    data.type = "worldMeshNode"
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