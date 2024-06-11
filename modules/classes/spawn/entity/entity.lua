local style = require("modules/ui/style")
local spawnable = require("modules/classes/spawn/spawnable")
local builder = require("modules/utils/entityBuilder")
local utils = require("modules/utils/utils")
local cache = require("modules/utils/cache")

---Class for base entity handling
---@class entity : spawnable
---@field public apps table
---@field public appIndex integer
local entity = setmetatable({}, { __index = spawnable })

function entity:new()
	local o = spawnable.new(self)

    o.boxColor = {255, 255, 0}
    o.spawnListType = "list"
    o.dataType = "Entity"
    o.modulePath = "entity/entity"

    o.apps = {}
    o.appIndex = 0

    setmetatable(o, { __index = self })
   	return o
end

function entity:loadSpawnData(data, position, rotation)
    spawnable.loadSpawnData(self, data, position, rotation)

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

function entity:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    builder.getEntityBBox(entity, function (data)
        print(data.bBox.min, data.bBox.max, #data.meshes)

        for _, mesh in pairs(data.meshes) do
            print(mesh.path .. " : " .. mesh.app)
            print(mesh.min, mesh.max)
            print(mesh.pos)
            print(mesh.rot)
            print("------------------------")

            -- local collider = require("modules/classes/spawn/collision/collider"):new()

            -- local x = mesh.max.x - mesh.min.x
            -- local y = mesh.max.y - mesh.min.y
            -- local z = mesh.max.z - mesh.min.z

            -- local offset = Vector4.new((mesh.min.x) + x / 2, (mesh.min.y) + y / 2, (mesh.min.z) + z / 2, 0)
            -- offset = mesh.rot:ToQuat():Transform(offset)
            -- offset = self.rotation:ToQuat():Transform(offset)

            -- pos = Game['OperatorAdd;Vector4Vector4;Vector4'](self.rotation:ToQuat():Transform(mesh.pos), offset)
            -- pos = Game['OperatorAdd;Vector4Vector4;Vector4'](self.position, pos)
            -- rot = utils.addEuler(mesh.rot, self.rotation)

            -- local data = {
            --     extents = { x = x / 2, y = y / 2, z = z / 2 },
            --     shape = 0
            -- }
            -- collider:loadSpawnData(data, pos, rot)
            -- self.object:addObjectToParent(collider, collider:generateName(mesh.path), false)
        end
    end)
end

function entity:getExtraHeight()
    return 4 * ImGui.GetStyle().ItemSpacing.y + ImGui.GetFrameHeight() * 1
end

function entity:draw()
    spawnable.draw(self)

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    style.pushGreyedOut(#self.apps == 0)

    local list = self.apps

    if #self.apps == 0 then
        list = {"No apps"}
    end

    if ImGui.Button("Test") then
        builder.getEntityBBox(self:getEntity(), function ()
            
        end)
    end

    ImGui.SetNextItemWidth(150)
    local index, changed = ImGui.Combo("##app", self.appIndex, list, #list)
    if changed and #self.apps > 0 then
        self.appIndex = index
        self.app = self.apps[self.appIndex + 1]

        local entity = self:getEntity()

        if entity then
            entity:ScheduleAppearanceChange(self.app)
        end
    end
    style.popGreyedOut(#self.apps == 0)
end

return entity