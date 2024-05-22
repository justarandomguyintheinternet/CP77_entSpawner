local spawnable = require("modules/classes/spawn/spawnable")
local builder = require("modules/utils/entityBuilder")
local style = require("modules/ui/style")
local visualizer = require("modules/utils/visualizer")

local materials = { "meatbag.physmat","linoleum.physmat","trash.physmat","plastic.physmat","character_armor.physmat","furniture_upholstery.physmat","metal_transparent.physmat","tire_car.physmat","meat.physmat","metal_car_pipe_steam.physmat","character_flesh.physmat","brick.physmat","character_flesh_head.physmat","leaves.physmat","flesh.physmat","water.physmat","plastic_road.physmat","metal_hollow.physmat","cyberware_flesh.physmat","plaster.physmat","plexiglass.physmat","character_vr.physmat","vehicle_chassis.physmat","sand.physmat","glass_electronics.physmat","leaves_stealth.physmat","tarmac.physmat","metal_car.physmat","tiles.physmat","glass_car.physmat","grass.physmat","concrete.physmat","carpet_techpiercable.physmat","wood_hedge.physmat","stone.physmat","leaves_semitransparent.physmat","metal_catwalk.physmat","upholstery_car.physmat","cyberware_metal.physmat","paper.physmat","leather.physmat","metal_pipe_steam.physmat","metal_pipe_water.physmat","metal_semitransparent.physmat","neon.physmat","glass_dst.physmat","plastic_car.physmat","mud.physmat","dirt.physmat","metal_car_pipe_water.physmat","furniture_leather.physmat","asphalt.physmat","wood_bamboo_poles.physmat","glass_opaque.physmat","carpet.physmat","food.physmat","cyberware_metal_head.physmat","metal_road.physmat","wood_tree.physmat","wood_player_npc_semitransparent.physmat","wood.physmat","metal_car_ricochet.physmat","cardboard.physmat","wood_crown.physmat","metal_ricochet.physmat","plastic_electronics.physmat","glass_semitransparent.physmat","metal_painted.physmat","rubber.physmat","ceramic.physmat","glass_bulletproof.physmat","metal_car_electronics.physmat","trash_bag.physmat","character_cyberflesh.physmat","metal_heavypiercable.physmat","metal.physmat","plastic_car_electronics.physmat","oil_spill.physmat","fabrics.physmat","glass.physmat","metal_techpiercable.physmat","concrete_water_puddles.physmat","character_metal.physmat" }
local presets = { "World Dynamic","Player Collision","Player Hitbox","NPC Collision","NPC Trace Obstacle","NPC Hitbox","Big NPC Collision","Player Blocker","Block Player and Vehicles","Vehicle Blocker","Block PhotoMode Camera","Ragdoll","Ragdoll Inner","RagdollVehicle","Terrain","Sight Blocker","Moving Kinematic","Interaction Object","Particle","Destructible","Debris","Debris Cluster","Foliage Debris","ItemDrop","Shooting","Moving Platform","Water","Window","Device transparent","Device solid visible","Vehicle Device","Environment transparent","Bullet logic","World Static","Simple Environment Collision","Complex Environment Collision","Foliage Trunk","Foliage Trunk Destructible","Foliage Low Trunk","Foliage Crown","Vehicle Part","Vehicle Proxy","Vehicle Part Query Only Exception","Vehicle Chassis","Chassis Bottom","Chassis Bottom Traffic","Vehicle Chassis Traffic","AV Chassis","Tank Chassis","Vehicle Chassis LOD3","Vehicle Chassis Traffic LOD3","Tank Chassis LOD3","Drone","Prop Interaction","Nameplate","Road Barrier Simple Collision","Road Barrier Complex Collision","Lootable Corpse","Spider Tank"}
local hints = { "Dynamic + Visibility + PhotoModeCamera + VehicleBlocker + TankBlocker + Shooting","Visibility","Player + Shooting","AI + PhotoModeCamera + NPCCollision","NPCTraceObstacle","AI","AI + PhotoModeCamera + VehicleBlocker + TankBlocker + NPCCollision","PlayerBlocker","PlayerBlocker + VehicleBlocker + TankBlocker","VehicleBlocker + TankBlocker","PhotoModeCamera","Ragdoll + Shooting","Ragdoll Inner","Ragdoll + Shooting","Terrain + Visibility + Shooting + PhotoModeCamera + VehicleBlocker + TankBlocker + PlayerBlocker","Visibility","Dynamic + PhotoModeCamera + Visibility + VehicleBlocker + TankBlocker + PlayerBlocker","Interaction","Particle","Destructible + PhotoModeCamera + Visibility + PlayerBlocker","Debris + Visibility","Destructible + PhotoModeCamera + Visibility + PlayerBlocker","Debris + Visibility","Interaction","Shooting","Visibility + Dynamic + Shooting + PhotoModeCamera + NPCBlocker + VehicleBlocker + TankBlocker + PlayerBlocker","Water","Collider + Visibility","Dynamic + Collider + Interaction + PhotoModeCamera + PlayerBlocker + VehicleBlocker + TankBlocker + Visibility","Dynamic + Collider + VehicleBlocker + TankBlocker + Visibility + Interaction + PhotoModeCamera + PlayerBlocker + NPCBlocker","Dynamic + Collider + Visibility + Interaction + PhotoModeCamera + PlayerBlocker","Collider + PlayerBlocker + VehicleBlocker + TankBlocker","Player + AI + Dynamic + Destructible + Terrain + Collider + Particle + Ragdoll + Debris + Shooting","Static + Visibility + Shooting + VehicleBlocker + PhotoModeCamera + VehicleBlocker + TankBlocker + PlayerBlocker","Static + VehicleBlocker + TankBlocker + PlayerBlocker + NPCBlocker + PhotoModeCamera","Shooting + Visibility","Shooting + PlayerBlocker + VehicleBlocker + Visibility + PhotoModeCamera","Shooting + PlayerBlocker + VehicleBlocker + Visibility + PhotoModeCamera + FoliageDestructible","Shooting + PlayerBlocker + Visibility + PhotoModeCamera","Visibility","Vehicle + Visibility + Shooting + PhotoModeCamera + Interaction","Visibility + Shooting + PhotoModeCamera","PlayerBlocker + Shooting + Visibility + Interaction","Vehicle + Interaction","Vehicle","Vehicle","Vehicle + Interaction","Vehicle + Interaction","Vehicle + Tank + Interaction","Vehicle + Interaction + Shooting","Vehicle + Interaction + Shooting","Vehicle + Tank + Interaction + Shooting","PlayerBlocker + Visibility + Shooting","Interaction + Visibility","NPCNameplate + Cloth","PlayerBlocker + VehicleBlocker + TankBlocker","Dynamic + Visibility + Shooting + PhotoModeCamera","Visibility + Interaction + PhotoModeCamera + Shooting","Tank + PlayerBlocker + VehicleBlocker + TankBlocker + Visibility + Shooting" }

---Class for worldCollisionNode
---@class collider : spawnable
---@field shape integer
---@field material integer
---@field preset integer
---@field shapeTypes table
---@field extents table {x, y, z}
---@field height number
---@field radius number
local collider = setmetatable({}, { __index = spawnable })

function collider:new()
	local o = spawnable.new(self)

    o.boxColor = {255, 255, 0}
    o.spawnListType = "files"
    o.dataType = "Collision Shape"
    o.spawnDataPath = "data/spawnables/colliders/"
    o.modulePath = "collision/collider"

    o.shape = 0
    o.material = 0
    o.preset = 0

    o.shapeTypes = { "Box", "Capsule", "Sphere" }

    o.extents = { x = 1, y = 1, z = 1 }
    o.height = 3
    o.radius = 1

    setmetatable(o, { __index = self })
   	return o
end

--- TODO: Add toggle for visual previews

function collider:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    local component = entColliderComponent.new()
    component.name = "collider"
    local actor

    if self.shape == 0 then
        actor = physicsColliderBox.new()
        actor.halfExtents = ToVector3(self.extents)
        visualizer.addBox(entity, self.extents, "red")
    elseif self.shape == 1 then
        actor = physicsColliderCapsule.new()
        actor.height = self.height
        actor.radius = self.radius
        visualizer.addCapsule(entity, self.radius, self.height, "red")
    elseif self.shape == 2 then
        actor = physicsColliderSphere.new()
        actor.radius = self.radius
        visualizer.addSphere(entity, self.radius, "red")
    end

    actor.material = materials[self.material + 1]

    component.colliders = { actor }

    local filterData = physicsFilterData.new()
    filterData.preset = self.preset

    local query = physicsQueryFilter.new()
    query.mask1 = 0
    query.mask2 = 70107400

    local sim = physicsSimulationFilter.new()
    sim.mask1 = 114696
    sim.mask2 = 23627

    filterData.queryFilter = query
    filterData.simulationFilter = sim
    component.filterData = filterData

    entity:AddComponent(component)
end

function collider:save()
    local data = spawnable.save(self)
    data.shape = self.shape
    data.material = self.material
    data.preset = self.preset
    data.extents = self.extents
    data.height = self.height
    data.radius = self.radius

    return data
end

function collider:getExtraHeight()
    return 6 * ImGui.GetStyle().ItemSpacing.y + ImGui.GetFrameHeight() * 3
end

---Respawn the collider to update parameters, if changed
---@param changed boolean
---@protected
function collider:updateFull(changed)
    if not self:isSpawned() then return end

    if changed then
        self:despawn()
        self:spawn()
    end
end

function collider:draw()
    spawnable.draw(self)

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    ImGui.PushItemWidth(150)

    ImGui.Text("Collision Shape")
    ImGui.SameLine()
    self.shape, changed = ImGui.Combo("##type", self.shape, self.shapeTypes, #self.shapeTypes)
    self:updateFull(changed)

    ImGui.Text("Collision Preset")
    ImGui.SameLine()
    self.preset, changed = ImGui.Combo("##preset", self.preset, presets, #presets)
    self:updateFull(changed)
    style.tooltip(hints[self.preset + 1])

    ImGui.SameLine()

    ImGui.Text("Collision Material")
    ImGui.SameLine()
    self.material, changed = ImGui.Combo("##material", self.material, materials, #materials)
    self:updateFull(changed)

    if self.shape == 0 then
        self.extents.x, changed = ImGui.DragFloat("##extentsX", self.extents.x, 0.01, 0, 9999, "%.2f X Extents")
        if changed then
            visualizer.updateScale(self:getEntity(), self.extents, "box")
        end
        self:updateFull(ImGui.IsItemDeactivatedAfterEdit())
        ImGui.SameLine()
        self.extents.y, changed = ImGui.DragFloat("##extentsY", self.extents.y, 0.01, 0, 9999, "%.2f Y Extents")
        if changed then
            visualizer.updateScale(self:getEntity(), self.extents, "box")
        end
        self:updateFull(ImGui.IsItemDeactivatedAfterEdit())
        ImGui.SameLine()
        self.extents.z, changed = ImGui.DragFloat("##extentsZ", self.extents.z, 0.01, 0, 9999, "%.2f Z Extents")
        if changed then
            visualizer.updateScale(self:getEntity(), self.extents, "box")
        end
        self:updateFull(ImGui.IsItemDeactivatedAfterEdit())
    elseif self.shape == 1 then
        self.height, changed = ImGui.DragFloat("##height", self.height, 0.01, 0, 9999, "%.2f Height")
        if changed then
            visualizer.updateCapsuleScale(self:getEntity(), self.radius, self.height)
        end
        self:updateFull(ImGui.IsItemDeactivatedAfterEdit())
        ImGui.SameLine()
    end
    if self.shape == 1 or self.shape == 2 then
        self.radius, changed = ImGui.DragFloat("##radius", self.radius, 0.01, 0, 9999, "%.2f Radius")
        if changed then
            if self.shape == 1 then
                visualizer.updateCapsuleScale(self:getEntity(), self.radius, self.height)
            else
                visualizer.updateScale(self:getEntity(), { x = self.radius, y = self.radius, z = self.radius }, "sphere")
            end
        end
        self:updateFull(ImGui.IsItemDeactivatedAfterEdit())
    end

    ImGui.PopItemWidth()
end

function collider:export()
    local data = spawnable.export(self)
    data.type = "worldCollisionNode"
    data.data = {

    }

    return data
end

return collider