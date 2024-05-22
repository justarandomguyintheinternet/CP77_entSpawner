local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local builder = require("modules/utils/entityBuilder")
local visualizer = require("modules/utils/visualizer")

---Base class for any object / node that can be spawned
---@class spawnable
---@field public dataType string
---@field public spawnListType string
---@field public spawnListPath string
---@field public modulePath string
---@field public boxColor table
---@field public spawner table
---@field public spawnData string
---@field public app string
---@field public position Vector4
---@field public rotation EulerAngles
---@field protected entityID entEntityID
---@field protected spawned boolean
---@field protected isHovered boolean
local spawnable = {}

function spawnable:new()
	local o = {}

    o.dataType = "Spawnable"
    o.spawnListType = "list"
    o.spawnListPath = "data/spawnables/entity/templates/"
    o.modulePath = "spawnable"
    o.boxColor = {255, 0, 0}
    o.spawner = nil

    o.spawnData = "base\\spawner\\empty_entity.ent"
    o.app = ""

    o.position = Vector4.new(0, 0, 0, 0)
    o.rotation = EulerAngles.new(0, 0, 0)
    o.entityID = entEntityID.new({hash = 0})
    o.spawned = false

    o.isHovered = false

    self.__index = self
   	return setmetatable(o, self)
end

-- Visualizer:
    -- Do generalized visualization for editing purposes
        -- Arrows
        -- Maybe Boxes for selecting one day
    -- Do visualization for things that cant be previewed
        -- Collider shapes
        -- Maybe shapes for lights
    -- How 2 manage vis state:
        -- Manage it in base spawnable, each one that adds custom vis has to manage it
            -- Attach all possible ones during assemble
            -- Get hovered state from object file
            -- Get more fine grained state from own UI
            -- Must keep track of hovered arrow index, but fine since its all in here
        -- For custom stuff:
            -- Wrap assemble to add own stuff
            -- Already knows when hovered from this class
            -- Function for hover / unhover
            -- Should be fine, most custom stuff will just show with generic things like arrows
    -- Vis scale:
        -- Do it during assembly or file load
        -- Cache!
        -- Custom function for calculating it?
            -- Could do one generic ig -> Entity based on mesh scale
                -- Must consider scale
                -- Can always wrap it, for e.g. lights

function spawnable:onAssemble(entity)
    visualizer.attachArrows(entity, { x = 1, y = 1, z = 1 })
end

---Spawns the spawnable if not spawned already
function spawnable:spawn()
    if self:isSpawned() then return end

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
        Game.FindEntityByID(self.entityID):GetEntity():Destroy()
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

---@return entEntity?
function spawnable:getEntity()
    return Game.FindEntityByID(self.entityID)
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
        app = self.app
    }
end

---@protected
function spawnable:drawPosition()
    ImGui.PushItemWidth(150)
    self.position.x, changed = ImGui.DragFloat("##x", self.position.x, self.spawner.settings.posSteps, -9999, 9999, "%.3f X")
    if ImGui.IsItemHovered() then
        visualizer.highlightArrow(self:getEntity(), "red")
    end
    if changed then
        self:update()
    end
    ImGui.SameLine()
    self.position.y, changed = ImGui.DragFloat("##y", self.position.y, self.spawner.settings.posSteps, -9999, 9999, "%.3f Y")
    if ImGui.IsItemHovered() then
        visualizer.highlightArrow(self:getEntity(), "green")
    end
    if changed then
        self:update()
    end
    ImGui.SameLine()
    self.position.z, changed = ImGui.DragFloat("##z", self.position.z, self.spawner.settings.posSteps, -9999, 9999, "%.3f Z")
    if ImGui.IsItemHovered() then
        visualizer.highlightArrow(self:getEntity(), "blue")
    end
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

---@protected
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

---@protected
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

function spawnable:setIsHovered(state)
    if state == self.isHovered then return end

    self.isHovered = state
    visualizer.showArrows(self:getEntity(), self.isHovered)
    visualizer.highlightArrow(self:getEntity(), "all")
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
---@param spawner table
function spawnable:loadSpawnData(data, position, rotation, spawner)
    for key, value in pairs(data) do
        self[key] = value
    end

    self.position = position
    self.rotation = rotation
    self.spawner = spawner
end

---Export the spawnable for WScript import, using same structure for `data` as JSON formated node
---@return table {position, rotation, scale, type, data}
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