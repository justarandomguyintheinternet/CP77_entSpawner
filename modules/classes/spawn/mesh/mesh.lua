local spawnable = require("modules/classes/spawn/spawnable")
local builder = require("modules/utils/entityBuilder")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local cache = require("modules/utils/cache")

---Class for worldMeshNode
---@class mesh : spawnable
---@field public apps table
---@field public appIndex integer
---@field public scale table {x: number, y: number, z: number}
local mesh = setmetatable({}, { __index = spawnable })

function mesh:new()
	local o = spawnable.new(self)

    o.spawnListType = "list"
    o.dataType = "Static Mesh"
    o.spawnDataPath = "data/spawnables/mesh/"
    o.modulePath = "mesh/mesh"

    o.apps = {}
    o.appIndex = 0
    o.scale = { x = 1, y = 1, z = 1 }

    setmetatable(o, { __index = self })
   	return o
end

function mesh:loadSpawnData(data, position, rotation, spawner)
    spawnable.loadSpawnData(self, data, position, rotation, spawner)

    self.apps = cache.getValue(self.spawnData)
    if not self.apps then
        self.apps = {}
        builder.registerLoadResource(self.spawnData, function (resource)
            for _, appearance in ipairs(resource.appearances) do
                table.insert(self.apps, appearance.name.value)
            end
        end)
        cache.addValue(self.spawnData, self.apps)
    end

    self.appIndex = math.max(utils.indexValue(self.apps, self.app) - 1, 0)
end

function mesh:onAssemble(entity)
    local component = entMeshComponent.new()
    component.name = "mesh"
    component.mesh = ResRef.FromString(self.spawnData)
    component.visualScale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)
    component.meshAppearance = self.app
    entity:AddComponent(component)
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
end

function mesh:getExtraHeight()
    return 5 * ImGui.GetStyle().ItemSpacing.y + ImGui.GetFrameHeight() * 2
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