local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local builder = require("modules/utils/entityBuilder")
local visualizer = require("modules/utils/visualizer")
local settings = require("modules/utils/settings")

---Base class for any object / node that can be spawned
---@class spawnable
---@field public dataType string
---@field public spawnListType string
---@field public spawnListPath string
---@field public modulePath string
---@field public boxColor table
---@field public spawnData string
---@field public app string
---@field public position Vector4
---@field public rotation EulerAngles
---@field protected entityID entEntityID
---@field protected spawned boolean
---@field public isHovered boolean
---@field protected arrowDirection string all|red|green|blue
---@field public object object? The object that is using this spawnable
---@field public node string
---@field public description string
---@field public previewNote string
---@field private rotationRelative boolean
local spawnable = {}

function spawnable:new()
	local o = {}

    o.dataType = "Spawnable"
    o.spawnListType = "list"
    o.spawnListPath = "data/spawnables/entity/templates/"
    o.modulePath = "spawnable"
    o.boxColor = {255, 0, 0}
    o.node = "worldEntityNode"
    o.description = ""
    o.previewNote = "---"

    o.spawnData = "base\\spawner\\empty_entity.ent"
    o.app = ""

    o.position = Vector4.new(0, 0, 0, 0)
    o.rotation = EulerAngles.new(0, 0, 0)
    o.entityID = entEntityID.new({hash = 0})
    o.spawned = false

    o.isHovered = false
    o.arrowDirection = "all"
    o.rotationRelative = false

    o.object = object

    self.__index = self
   	return setmetatable(o, self)
end

function spawnable:onAssemble(entity)
    visualizer.attachArrows(entity, self:getVisualScale(), self.isHovered, self.arrowDirection)
end

---Spawns the spawnable if not spawned already, must register a callback for entityAssemble which calls onAssemble
function spawnable:spawn()
    if self:isSpawned() then return end

    local spec = StaticEntitySpec.new()
    spec.templatePath = self.spawnData
    spec.position = self.position
    spec.orientation = self.rotation:ToQuat()
    spec.attached = true
    spec.appearanceName = self.app
    self.entityID = Game.GetStaticEntitySystem():SpawnEntity(spec)

    builder.registerAssembleCallback(self.entityID, function (entity)
        self:onAssemble(entity)
    end)

    self.spawned = true
end

---@return boolean
function spawnable:isSpawned()
    return self.spawned
end

function spawnable:despawn()
    local entity = self:getEntity()
    if entity then
        Game.GetStaticEntitySystem():DespawnEntity(self.entityID)
    end
    self.spawned = false
end

function spawnable:respawn()
    self:despawn()
    self:spawn()
end

---Update the position and rotation of the spawnable
function spawnable:update()
    if not self:isSpawned() then return end

    local entity = self:getEntity()

    if not entity then return end

    local transform = entity:GetWorldTransform()
    transform:SetPosition(self.position)
    transform:SetOrientationEuler(self.rotation)
    self:getEntity():SetWorldTransform(transform)
end

---Called when one of the control UI widgets is released
function spawnable:onEdited(edited) end

---@return entEntity?
function spawnable:getEntity()
    return Game.GetStaticEntitySystem():GetEntity(self.entityID)
end

--- Generate valid name from given name / path
---@param name string
---@return string newName The generated/sanitized name
function spawnable:generateName(name)
    if string.find(name, "\\") then
        name = name:match("\\[^\\]*$") -- Everything after last \
    end
    name = name:gsub(".ent", ""):gsub("\\", "_") -- Remove .ent, replace \ by _
    return utils.createFileName(name)
end

---Return the spawnable data for internal object format saving
---@return table {modulePath, position, rotation, spawnData, dataType, app}
function spawnable:save()
    return {
        modulePath = self.modulePath,
        position = { x = self.position.x, y = self.position.y, z = self.position.z, w = 0 },
        rotation = { roll = self.rotation.roll, pitch = self.rotation.pitch, yaw = self.rotation.yaw },
        spawnData = self.spawnData,
        dataType = self.dataType,
        app = self.app,
        rotationRelative = self.rotationRelative
    }
end

---@protected
function spawnable:drawPosition()
    ImGui.PushItemWidth(150)
    self.position.x, changed = ImGui.DragFloat("##x", self.position.x, settings.posSteps, -9999, 9999, "%.3f X")
    self:setIsHovered(ImGui.IsItemActive() or ImGui.IsItemHovered())
    self:updateArrowDirection(ImGui.IsItemHovered(), "red")
    if changed then
        self:update()
    end
    self:onEdited(ImGui.IsItemDeactivatedAfterEdit())
    ImGui.SameLine()

    self.position.y, changed = ImGui.DragFloat("##y", self.position.y, settings.posSteps, -9999, 9999, "%.3f Y")
    self:setIsHovered(ImGui.IsItemActive() or ImGui.IsItemHovered())
    self:updateArrowDirection(ImGui.IsItemHovered(), "green")
    if changed then
        self:update()
    end
    self:onEdited(ImGui.IsItemDeactivatedAfterEdit())
    ImGui.SameLine()

    self.position.z, changed = ImGui.DragFloat("##z", self.position.z, settings.posSteps, -9999, 9999, "%.3f Z")
    self:setIsHovered(ImGui.IsItemActive() or ImGui.IsItemHovered())
    self:updateArrowDirection(ImGui.IsItemHovered(), "blue")
    if changed then
        self:update()
    end
    self:onEdited(ImGui.IsItemDeactivatedAfterEdit())
    ImGui.PopItemWidth()
    ImGui.SameLine()

    if ImGui.Button("To player", 150, 0) then
        self.position = Game.GetPlayer():GetWorldPosition()
        self:update()
    end
    self:onEdited(ImGui.IsItemDeactivatedAfterEdit())
    style.tooltip("Set the object position to the players position")
end

---@protected
function spawnable:drawRelativePosition()
    style.pushGreyedOut(not self:isSpawned())

    ImGui.PushItemWidth(150)
    local x, changed = ImGui.DragFloat("##r_x", 0, settings.posSteps, -9999, 9999, "%.3f Relative X")
    self:setIsHovered(ImGui.IsItemActive() or ImGui.IsItemHovered())
    self:updateArrowDirection(ImGui.IsItemHovered(), "red")
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
    self:onEdited(ImGui.IsItemDeactivatedAfterEdit())

    ImGui.SameLine()
    local y, changed = ImGui.DragFloat("##r_y", 0, settings.posSteps, -9999, 9999, "%.3f Relative Y")
    self:setIsHovered(ImGui.IsItemActive() or ImGui.IsItemHovered())
    self:updateArrowDirection(ImGui.IsItemHovered(), "green")
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
    self:onEdited(ImGui.IsItemDeactivatedAfterEdit())

    ImGui.SameLine()
    local z, changed = ImGui.DragFloat("##r_z", 0, settings.posSteps, -9999, 9999, "%.3f Relative Z")
    self:setIsHovered(ImGui.IsItemActive() or ImGui.IsItemHovered())
    self:updateArrowDirection(ImGui.IsItemHovered(), "blue")
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
    self:onEdited(ImGui.IsItemDeactivatedAfterEdit())
    ImGui.PopItemWidth()

    style.popGreyedOut(not self:isSpawned())
end

---TODO: Fix roll+pitch
---@protected
function spawnable:drawRotation()
    ImGui.PushItemWidth(150)
    local roll, changed = ImGui.DragFloat("##roll", self.rotation.roll, settings.rotSteps, -9999, 9999, "%.3f Roll")
    self:setIsHovered(ImGui.IsItemActive() or ImGui.IsItemHovered())
    self:updateArrowDirection(ImGui.IsItemHovered(), "green")
    if changed then
        if self.rotationRelative then
            local rot = Quaternion.SetAxisAngle(Vector4.new(0, 1, 0, 0), Deg2Rad(roll - self.rotation.roll))
            self.rotation = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](self.rotation:ToQuat(), rot):ToEulerAngles()
        else
            self.rotation.roll = roll
        end

        self:update()
    end
    self:onEdited(ImGui.IsItemDeactivatedAfterEdit())

    ImGui.SameLine()
    local pitch, changed = ImGui.DragFloat("##pitch", self.rotation.pitch, settings.rotSteps, -9999, 9999, "%.3f Pitch")
    self:setIsHovered(ImGui.IsItemActive() or ImGui.IsItemHovered())
    self:updateArrowDirection(ImGui.IsItemHovered(), "red")
    if changed then
        if self.rotationRelative then
            local rot = Quaternion.SetAxisAngle(Vector4.new(1, 0, 0, 0), Deg2Rad(pitch - self.rotation.pitch))
            self.rotation = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](self.rotation:ToQuat(), rot):ToEulerAngles()
        else
            self.rotation.pitch = pitch
        end

        self:update()
    end
    self:onEdited(ImGui.IsItemDeactivatedAfterEdit())

    ImGui.SameLine()
    local yaw, changed = ImGui.DragFloat("##yaw", self.rotation.yaw, settings.rotSteps, -9999, 9999, "%.3f Yaw")
    self:setIsHovered(ImGui.IsItemActive() or ImGui.IsItemHovered())
    self:updateArrowDirection(ImGui.IsItemHovered(), "blue")
    if changed then
        if self.rotationRelative then
            local rot = Quaternion.SetAxisAngle(Vector4.new(0, 0, 1, 0), Deg2Rad(yaw - self.rotation.yaw))
            self.rotation = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](self.rotation:ToQuat(), rot):ToEulerAngles()
        else
            self.rotation.yaw = yaw
        end

        self:update()
    end
    self:onEdited(ImGui.IsItemDeactivatedAfterEdit())

    ImGui.SameLine()
    ImGui.PopItemWidth()

    self.rotationRelative = ImGui.Checkbox("Relative", self.rotationRelative)
    style.tooltip("Rotate relative to the object's orientation")
end

function spawnable:draw()
    self:drawPosition()
    self:drawRelativePosition()
    self:drawRotation()
end

--- Reset the internal states of the arrow visualizer
function spawnable:resetVisualizerStates()
    self.arrowDirection = "all"
    self.isHovered = false
end

--- Tried to update and highlight the arrow direction, if changed
function spawnable:updateArrowDirection(hovered, direction)
    if self.isHovered and direction ~= self.arrowDirection and hovered then
        self.arrowDirection = direction
        visualizer.highlightArrow(self:getEntity(), self.arrowDirection)
    end
end

--- Collect all hovered states from header and internal widgets
function spawnable:setIsHovered(state)
    self.isHovered = state or self.isHovered
end

--- Called at the end of the draw functions, to update the visualizer visibility if needed
function spawnable:updateIsHovered(oldState)
    if oldState ~= self.isHovered then
        visualizer.showArrows(self:getEntity(), self.isHovered)

        -- TODO: Do this more elegantly
        if self.arrowDirection == "all" then
            visualizer.highlightArrow(self:getEntity(), self.arrowDirection)
        end
    end
end

---TODO: Implement better for each object
--- Used for visualizer scales
function spawnable:getVisualScale()
    return { x = 1, y = 1, z = 1 }
end

---Amount of extra height to be added to 
---@see object.draw
---@return integer
function spawnable:getExtraHeight()
    return 0
end

---Load data blob, position and rotation for spawning
---@param data table
---@param position Vector4
---@param rotation EulerAngles
function spawnable:loadSpawnData(data, position, rotation)
    for key, value in pairs(data) do
        self[key] = value
    end

    self.position = position
    self.rotation = rotation
    self.rotationRelative = data.rotationRelative or false
end

---Export the spawnable for WScript import, using same structure for `data` as JSON formated node
---@param key integer Index of the object in the group
---@param length integer Amount of objects in the group
---@return table {position, rotation, scale, type, data}
function spawnable:export(key, length)
    return {
        position = utils.fromVector(self.position),
        rotation = utils.fromQuaternion(self.rotation:ToQuat()),
        scale = { x = 1, y = 1, z = 1 },
        type = "worldEntityNode",
        name = self.object.name,
        data = {
            entityTemplate = {
                DepotPath = {
                    ["$type"] = "ResourcePath",
                    ["$storage"] = "string",
                    ["$value"] = self.spawnData
                }
            },
            appearanceName = {
                ["$type"] = "CName",
                ["$storage"] = "string",
                ["$value"] = self.app
            }
        }
    }
end

return spawnable