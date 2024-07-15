local style = require("modules/ui/style")
local spawnable = require("modules/classes/spawn/spawnable")
local builder = require("modules/utils/entityBuilder")
local utils = require("modules/utils/utils")
local cache = require("modules/utils/cache")
local visualizer = require("modules/utils/visualizer")

---Class for base entity handling
---@class entity : spawnable
---@field public apps table
---@field public appIndex integer
---@field private bBoxCallback function
---@field public bBox table {min: Vector4, max: Vector4}
local entity = setmetatable({}, { __index = spawnable })

function entity:new()
	local o = spawnable.new(self)

    o.boxColor = {255, 255, 0}
    o.spawnListType = "list"
    o.dataType = "Entity"
    o.modulePath = "entity/entity"

    o.apps = {}
    o.appIndex = 0
    o.bBoxCallback = nil
    o.bBox = { min = Vector4.new(-0.5, -0.5, -0.5, 0), max = Vector4.new( 0.5, 0.5, 0.5, 0) }

    setmetatable(o, { __index = self })
   	return o
end

function entity:loadSpawnData(data, position, rotation)
    spawnable.loadSpawnData(self, data, position, rotation)

    self.apps = cache.getValue(self.spawnData .. "_apps")
    if not self.apps then
        self.apps = {}
        builder.registerLoadResource(self.spawnData, function (resource)
            for _, appearance in ipairs(resource.appearances) do
                table.insert(self.apps, appearance.name.value)
            end
        end)
        cache.addValue(self.spawnData .. "_apps", self.apps)
    end

    self.appIndex = math.max(utils.indexValue(self.apps, self.app) - 1, 0)
end

function entity:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    cache.tryGet(self.spawnData .. "_bBox", self.spawnData .. "_meshes")
    .notFound(function (task)
        builder.getEntityBBox(entity, function (data)
            local meshes = {}
            for _, mesh in pairs(data.meshes) do
                table.insert(meshes, { app = mesh.app, path = mesh.path, pos = utils.fromVector(mesh.pos), rot = utils.fromEuler(mesh.rot) })
            end

            cache.addValue(self.spawnData .. "_bBox", { min = utils.fromVector(data.bBox.min), max = utils.fromVector(data.bBox.max) })
            cache.addValue(self.spawnData .. "_meshes", meshes)
            utils.log("[Entity] Loaded and cached BBOX for entity " .. self.spawnData .. " with " .. #meshes .. " meshes.")

            task:taskCompleted()
        end)
    end)
    .found(function ()
        utils.log("[Entity] BBOX for entity " .. self.spawnData .. " found.")
        local box = cache.getValue(self.spawnData .. "_bBox")
        self.bBox.min = ToVector4(box.min)
        self.bBox.max = ToVector4(box.max)

        visualizer.updateScale(entity, self:getVisualScale(), "arrows")

        if self.bBoxCallback then
            self.bBoxCallback(entity)
        end
    end)
end

function entity:onBBoxLoaded(callback)
    self.bBoxCallback = callback
end

function entity:getVisualScale()
    local x = self.bBox.max.x - self.bBox.min.x
    local y = self.bBox.max.y - self.bBox.min.y
    local z = self.bBox.max.z - self.bBox.min.z

    local max = math.min(math.max(x, y, z, 1) * 0.5, 3.5)
    return { x = max, y = max, z = max }
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