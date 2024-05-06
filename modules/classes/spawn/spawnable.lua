local utils = require("modules/utils/utils")
local style = require("modules/ui/style")

spawnable = {}

function spawnable:new()
	local o = {}

    o.dataType = "Spawnable"
    o.spawnListType = "list"
    o.spawnListPath = "data/spawnables/entity/templates/"
    o.modulePath = "spawnable"
    o.boxColor = {255, 0, 0}
    o.spawner = nil

    o.spawnData = "base\\game_object.ent"
    o.app = ""

    o.position = Vector4.new(0, 0, 0, 0)
    o.rotation = EulerAngles.new(0, 0, 0)
    o.entityID = entEntityID.new({hash = 0})
    o.spawned = false

	self.__index = self
   	return setmetatable(o, self)
end

function spawnable:spawn()
    local transform = WorldTransform.new()
    transform:SetOrientation(self.rotation:ToQuat())
    transform:SetPosition(self.position)

    local spec = StaticEntitySpec.new()
    spec.templatePath = self.spawnData
    spec.position = self.position
    spec.orientation = self.rotation:ToQuat()
    spec.attached = true
    spec.appearanceName = self.app
    self.entityID = Game.GetStaticEntitySystem():SpawnEntity(spec)

    self.spawned = true
end

function spawnable:isSpawned()
    return self.spawned
end

function spawnable:despawn()
    local entity = self:getEntity()
    if entity then
        Game.FindEntityByID(self.entityID):GetEntity():Destroy()
    end
    self.spawned = false
end

function spawnable:update()
    if not self:isSpawned() then return end

    local entity = self:getEntity()

    if not entity then return end

    local transform = entity:GetWorldTransform()
    transform:SetPosition(self.position)
    transform:SetOrientationEuler(self.rotation)
    self:getEntity():SetWorldTransform(transform)
end

function spawnable:getEntity()
    return Game.FindEntityByID(self.entityID)
end

function spawnable:generateName(name) -- Generate valid name from given name / path
    if string.find(name, "\\") then
        name = name:match("\\[^\\]*$") -- Everything after last \
    end
    name = name:gsub(".ent", ""):gsub("\\", "_") -- Remove .ent, replace \ by _
    return utils.createFileName(name)
end

function spawnable:save()
    return {
        modulePath = self.modulePath,
        position = { x = self.position.x, y = self.position.y, z = self.position.z, w = 0 },
        rotation = { roll = self.rotation.roll, pitch = self.rotation.pitch, yaw = self.rotation.yaw },
        spawnData = self.spawnData,
        dataType = self.dataType,
        app = self.app
    }
end

function spawnable:drawPosition()
    ImGui.PushItemWidth(150)
    self.position.x, changed = ImGui.DragFloat("##x", self.position.x, self.spawner.settings.posSteps, -9999, 9999, "%.3f X")
    if changed then
        self:update()
    end
    ImGui.SameLine()
    self.position.y, changed = ImGui.DragFloat("##y", self.position.y, self.spawner.settings.posSteps, -9999, 9999, "%.3f Y")
    if changed then
        self:update()
    end
    ImGui.SameLine()
    self.position.z, changed = ImGui.DragFloat("##z", self.position.z, self.spawner.settings.posSteps, -9999, 9999, "%.3f Z")
    if changed then
        self:update()
    end
    ImGui.PopItemWidth()
    ImGui.SameLine()
    if ImGui.Button("To player", 150, 0) then
        self.position = Game.GetPlayer():GetWorldPosition()
        self:update()
    end
    style.tooltip("Set the object position to the players position")
end

function spawnable:drawRelativePosition()
    style.pushGreyedOut(not self:isSpawned())

    ImGui.PushItemWidth(150)
    local x, changed = ImGui.DragFloat("##r_x", 0, self.spawner.settings.posSteps, -9999, 9999, "%.3f Relative X")
    if changed then
        local entity = self:getEntity()
        if entity then
            local v = entity:GetWorldRight()
            self.position.x = self.position.x + (v.x * x)
            self.position.y = self.position.y + (v.y * x)
            self.position.z = self.position.z + (v.z * x)
            self:update()
        end
        x = 0
    end
    ImGui.SameLine()
    local y, changed = ImGui.DragFloat("##r_y", 0, self.spawner.settings.posSteps, -9999, 9999, "%.3f Relative Y")
    if changed then
        local entity = self:getEntity()
        if entity then
            local v = entity:GetWorldForward()
            self.position.x = self.position.x + (v.x * y)
            self.position.y = self.position.y + (v.y * y)
            self.position.z = self.position.z + (v.z * y)
            self:update()
        end
        y = 0
    end
    ImGui.SameLine()
    local z, changed = ImGui.DragFloat("##r_z", 0, self.spawner.settings.posSteps, -9999, 9999, "%.3f Relative Z")
    if changed then
        local entity = self:getEntity()
        if entity then
            local v = entity:GetWorldUp()
            self.position.x = self.position.x + (v.x * z)
            self.position.y = self.position.y + (v.y * z)
            self.position.z = self.position.z + (v.z * z)
            self:update()
        end
        z = 0
    end
    ImGui.PopItemWidth()

    style.popGreyedOut(not self:isSpawned())
end

function spawnable:drawRotation()
    ImGui.PushItemWidth(150)
    self.rotation.roll, changed = ImGui.DragFloat("##roll", self.rotation.roll, self.spawner.settings.rotSteps, -9999, 9999, "%.3f Roll")
    if changed then
        self:update()
    end
    ImGui.SameLine()
    self.rotation.pitch, changed = ImGui.DragFloat("##pitch", self.rotation.pitch, self.spawner.settings.rotSteps, -9999, 9999, "%.3f Pitch")
    if changed then
        self:update()
    end
    ImGui.SameLine()
    self.rotation.yaw, changed = ImGui.DragFloat("##yaw", self.rotation.yaw, self.spawner.settings.rotSteps, -9999, 9999, "%.3f Yaw")
    if changed then
        self:update()
    end
    ImGui.SameLine()
    ImGui.PopItemWidth()

    if ImGui.Button("To Player Rotation", 150, 0) then
        self.rotation = GetPlayer():GetWorldOrientation():ToEulerAngles()
        self:update()
    end
    style.tooltip("Set the object rotation to the players rotation")
end

function spawnable:draw()
    self:drawPosition()
    self:drawRelativePosition()
    self:drawRotation()
end

---Load data blob, position and rotation for spawning
---@param data table
function spawnable:loadSpawnData(data, position, rotation, spawner)
    for key, value in pairs(data) do
        self[key] = value
    end

    self.position = position
    self.rotation = rotation
    self.spawner = spawner
end

function spawnable:export()
    return {
        position = utils.fromVector(self.position),
        rotation = utils.fromQuaternion(self.rotation:ToQuat()),
        scale = { x = 1, y = 1, z = 1 },
        type = "worldEntityNode",
        data = {
            entityTemplate = {
                DepotPath = {
                    ["$storage"] = "string",
                    ["$value"] = self.spawnData
                }
            },
            appearanceName = {
                ["$storage"] = "string",
                ["$value"] = self.app
            }
        }
    }
end

return spawnable