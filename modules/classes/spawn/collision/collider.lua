local spawnable = require("modules/classes/spawn/spawnable")
local style = require("modules/ui/style")
local visualizer = require("modules/utils/visualizer")
local settings = require("modules/utils/settings")
local utils = require("modules/utils/utils")
local history = require("modules/utils/history")
local intersection = require("modules/utils/editor/intersection")

local materials = { "meatbag.physmat","linoleum.physmat","trash.physmat","plastic.physmat","character_armor.physmat","furniture_upholstery.physmat","metal_transparent.physmat","tire_car.physmat","meat.physmat","metal_car_pipe_steam.physmat","character_flesh.physmat","brick.physmat","character_flesh_head.physmat","leaves.physmat","flesh.physmat","water.physmat","plastic_road.physmat","metal_hollow.physmat","cyberware_flesh.physmat","plaster.physmat","plexiglass.physmat","character_vr.physmat","vehicle_chassis.physmat","sand.physmat","glass_electronics.physmat","leaves_stealth.physmat","tarmac.physmat","metal_car.physmat","tiles.physmat","glass_car.physmat","grass.physmat","concrete.physmat","carpet_techpiercable.physmat","wood_hedge.physmat","stone.physmat","leaves_semitransparent.physmat","metal_catwalk.physmat","upholstery_car.physmat","cyberware_metal.physmat","paper.physmat","leather.physmat","metal_pipe_steam.physmat","metal_pipe_water.physmat","metal_semitransparent.physmat","neon.physmat","glass_dst.physmat","plastic_car.physmat","mud.physmat","dirt.physmat","metal_car_pipe_water.physmat","furniture_leather.physmat","asphalt.physmat","wood_bamboo_poles.physmat","glass_opaque.physmat","carpet.physmat","food.physmat","cyberware_metal_head.physmat","metal_road.physmat","wood_tree.physmat","wood_player_npc_semitransparent.physmat","wood.physmat","metal_car_ricochet.physmat","cardboard.physmat","wood_crown.physmat","metal_ricochet.physmat","plastic_electronics.physmat","glass_semitransparent.physmat","metal_painted.physmat","rubber.physmat","ceramic.physmat","glass_bulletproof.physmat","metal_car_electronics.physmat","trash_bag.physmat","character_cyberflesh.physmat","metal_heavypiercable.physmat","metal.physmat","plastic_car_electronics.physmat","oil_spill.physmat","fabrics.physmat","glass.physmat","metal_techpiercable.physmat","concrete_water_puddles.physmat","character_metal.physmat" }
local presets = { "World Dynamic","Player Collision","Player Hitbox","NPC Collision","NPC Trace Obstacle","NPC Hitbox","Big NPC Collision","Player Blocker","Block Player and Vehicles","Vehicle Blocker","Block PhotoMode Camera","Ragdoll","Ragdoll Inner","RagdollVehicle","Terrain","Sight Blocker","Moving Kinematic","Interaction Object","Particle","Destructible","Debris","Debris Cluster","Foliage Debris","ItemDrop","Shooting","Moving Platform","Water","Window","Device transparent","Device solid visible","Vehicle Device","Environment transparent","Bullet logic","World Static","Simple Environment Collision","Complex Environment Collision","Foliage Trunk","Foliage Trunk Destructible","Foliage Low Trunk","Foliage Crown","Vehicle Part","Vehicle Proxy","Vehicle Part Query Only Exception","Vehicle Chassis","Chassis Bottom","Chassis Bottom Traffic","Vehicle Chassis Traffic","AV Chassis","Tank Chassis","Vehicle Chassis LOD3","Vehicle Chassis Traffic LOD3","Tank Chassis LOD3","Drone","Prop Interaction","Nameplate","Road Barrier Simple Collision","Road Barrier Complex Collision","Lootable Corpse","Spider Tank"}
local hints = { "Dynamic + Visibility + PhotoModeCamera + VehicleBlocker + TankBlocker + Shooting","Visibility","Player + Shooting","AI + PhotoModeCamera + NPCCollision","NPCTraceObstacle","AI","AI + PhotoModeCamera + VehicleBlocker + TankBlocker + NPCCollision","PlayerBlocker","PlayerBlocker + VehicleBlocker + TankBlocker","VehicleBlocker + TankBlocker","PhotoModeCamera","Ragdoll + Shooting","Ragdoll Inner","Ragdoll + Shooting","Terrain + Visibility + Shooting + PhotoModeCamera + VehicleBlocker + TankBlocker + PlayerBlocker","Visibility","Dynamic + PhotoModeCamera + Visibility + VehicleBlocker + TankBlocker + PlayerBlocker","Interaction","Particle","Destructible + PhotoModeCamera + Visibility + PlayerBlocker","Debris + Visibility","Destructible + PhotoModeCamera + Visibility + PlayerBlocker","Debris + Visibility","Interaction","Shooting","Visibility + Dynamic + Shooting + PhotoModeCamera + NPCBlocker + VehicleBlocker + TankBlocker + PlayerBlocker","Water","Collider + Visibility","Dynamic + Collider + Interaction + PhotoModeCamera + PlayerBlocker + VehicleBlocker + TankBlocker + Visibility","Dynamic + Collider + VehicleBlocker + TankBlocker + Visibility + Interaction + PhotoModeCamera + PlayerBlocker + NPCBlocker","Dynamic + Collider + Visibility + Interaction + PhotoModeCamera + PlayerBlocker","Collider + PlayerBlocker + VehicleBlocker + TankBlocker","Player + AI + Dynamic + Destructible + Terrain + Collider + Particle + Ragdoll + Debris + Shooting","Static + Visibility + Shooting + VehicleBlocker + PhotoModeCamera + VehicleBlocker + TankBlocker + PlayerBlocker","Static + VehicleBlocker + TankBlocker + PlayerBlocker + NPCBlocker + PhotoModeCamera","Shooting + Visibility","Shooting + PlayerBlocker + VehicleBlocker + Visibility + PhotoModeCamera","Shooting + PlayerBlocker + VehicleBlocker + Visibility + PhotoModeCamera + FoliageDestructible","Shooting + PlayerBlocker + Visibility + PhotoModeCamera","Visibility","Vehicle + Visibility + Shooting + PhotoModeCamera + Interaction","Visibility + Shooting + PhotoModeCamera","PlayerBlocker + Shooting + Visibility + Interaction","Vehicle + Interaction","Vehicle","Vehicle","Vehicle + Interaction","Vehicle + Interaction","Vehicle + Tank + Interaction","Vehicle + Interaction + Shooting","Vehicle + Interaction + Shooting","Vehicle + Tank + Interaction + Shooting","PlayerBlocker + Visibility + Shooting","Interaction + Visibility","NPCNameplate + Cloth","PlayerBlocker + VehicleBlocker + TankBlocker","Dynamic + Visibility + Shooting + PhotoModeCamera","Visibility + Interaction + PhotoModeCamera + Shooting","Tank + PlayerBlocker + VehicleBlocker + TankBlocker + Visibility + Shooting" }
local colors = { "red", "green", "blue" }

---Class for worldCollisionNode
---@class collider : spawnable
---@field private shape integer
---@field private material integer
---@field private preset integer
---@field private shapeTypes table
---@field public previewed boolean
---@field public maxPropertyWidth number
local collider = setmetatable({}, { __index = spawnable })

function collider:new()
	local o = spawnable.new(self)

    o.spawnListType = "files"
    o.dataType = "Collision Shape"
    o.spawnDataPath = "data/spawnables/colliders/"
    o.modulePath = "collision/collider"
    o.node = "worldCollisionNode"
    o.description = "A collision shape, can be a box, capsule or sphere"
    o.icon = IconGlyphs.TextureBox

    o.shape = 0
    o.material = 31
    o.preset = 33

    o.shapeTypes = { "Box", "Capsule", "Sphere" }

    o.scale = { x = 1, y = 1, z = 1 }
    o.previewed = true
    o.maxPropertyWidth = nil
    o.currentAxis = 0

    setmetatable(o, { __index = self })
   	return o
end

function collider:loadSpawnData(data, position, rotation)
    spawnable.loadSpawnData(self, data, position, rotation)

    if data.radius then
        if self.shape == 0 then
            self.scale = data.extents
        elseif self.shape == 1 then
            self.scale = { x = data.radius, y = data.radius, z = data.height }
        elseif self.shape == 2 then
            self.scale = { x = data.radius, y = data.radius, z = data.radius }
        end
    end
end

function collider:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    local component = entColliderComponent.new()
    component.name = "collider"
    local actor
    local color = colors[settings.colliderColor + 1]

    if self.shape == 0 then
        actor = physicsColliderBox.new()
        actor.halfExtents = ToVector3(self.scale)
        visualizer.addBox(entity, self.scale, color)
    elseif self.shape == 1 then
        actor = physicsColliderCapsule.new()
        actor.height = self.scale.z
        actor.radius = self.scale.x
        visualizer.addCapsule(entity, self.scale.x, self.scale.z, color)
    elseif self.shape == 2 then
        actor = physicsColliderSphere.new()
        actor.radius = self.scale.x
        visualizer.addSphere(entity, self.scale, color)
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

    visualizer.toggleAll(entity, self.previewed)
end

function collider:save()
    local data = spawnable.save(self)
    data.shape = self.shape
    data.material = self.material
    data.preset = self.preset
    data.previewed = self.previewed
    data.scale = { x = self.scale.x, y = self.scale.y, z = self.scale.z }
    if data.previewed == nil then data.previewed = true end

    return data
end

function collider:getPresetIndexByName(preset)
    return utils.indexValue(presets, preset) - 1
end

function collider:getMaterialIndexByName(material)
    return utils.indexValue(materials, material) - 1
end

function collider:getSize()
    return { x = self.scale.x * 2, y = self.scale.y * 2, z = self.scale.z * 2 }
end

function collider:getArrowSize()
    local max = math.max(self.scale.x, self.scale.y, self.scale.z)

    max = math.max(max, 1) * 0.5

    return { x = max, y = max, z = max }
end

function collider:calculateIntersection(origin, ray)
    if not self:getEntity() or not self.previewed then
        return { hit = false }
    end

    local scaledBBox = {
        min = {  x = - self.scale.x, y = - self.scale.y, z = - self.scale.z },
        max = {  x = self.scale.x, y = self.scale.y, z = self.scale.z }
    }
    local result

    if self.shape == 2 then
        result = intersection.getSphereIntersection(origin, ray, self.position, self.scale.x)
    else
        result = intersection.getBoxIntersection(origin, ray, self.position, self.rotation, scaledBBox)
    end

    return {
        hit = result.hit,
        position = result.position,
        unscaledHit = result.position,
        collisionType = "bbox",
        distance = result.distance,
        bBox = scaledBBox,
        objectOrigin = self.position,
        objectRotation = self.rotation,
        normal = result.normal
    }
end

---Respawn the collider to update parameters, if changed
---@param changed boolean
---@protected
function collider:updateFull(changed)
    if changed and self:isSpawned() then self:respawn() end
end

---@protected
function collider:updateScale(finished, delta)
    self.scale.x = math.max(self.scale.x, 0)
    self.scale.y = math.max(self.scale.y, 0)
    self.scale.z = math.max(self.scale.z, 0)

    if self.shape == 1 then
        if math.abs(delta.y) > 0 then
            self.currentAxis = 0
        elseif math.abs(delta.x) > 0 then
            self.currentAxis = 1
        end

        if finished then
            if self.currentAxis == 0 then
                self.scale.x = self.scale.y
            else
                self.scale.y = self.scale.x
            end
        end
    elseif self.shape == 2 then
        local radius = math.max(self.scale.x, self.scale.y, self.scale.z)
        self.scale = { x = radius, y = radius, z = radius }
    end

    if finished then
        self:respawn()
        return
    end

    local entity = self:getEntity()
    if not entity then return end

    visualizer.updateScale(entity, self:getArrowSize(), "arrows")

    if self.shape == 0 then
        visualizer.updateScale(entity, self.scale, "box")
    elseif self.shape == 1 then
        visualizer.updateCapsuleScale(self:getEntity(), self.currentAxis == 1 and self.scale.x or self.scale.y, self.scale.z)
    elseif self.shape == 2 then
        visualizer.updateScale(entity, self.scale, "sphere")
    end
end

function collider:draw()
    spawnable.draw(self)

    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth({ "Preview Shape", "Collision Shape", "Collision Preset", "Collision Material" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    style.mutedText("Preview Shape")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.previewed, changed = style.trackedCheckbox(self.object, "##collisionPreview", self.previewed)
    if changed then
        visualizer.toggleAll(self:getEntity(), self.previewed)
    end

    style.mutedText("Collision Shape")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.shape, changed = style.trackedCombo(self.object, "##type", self.shape, self.shapeTypes, 100)
    if changed then
        self:updateScale(true, { x = 0, y = 0, z = 0 })
    end

    style.mutedText("Collision Preset")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.preset, changed = style.trackedCombo(self.object, "##preset", self.preset, presets, 100)
    self:updateFull(changed)
    style.tooltip(hints[self.preset + 1])

    style.mutedText("Collision Material")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.material, changed = style.trackedCombo(self.object, "##material", self.material, materials, 200)
    self:updateFull(changed)
end

function collider:getProperties()
    local properties = spawnable.getProperties(self)
    table.insert(properties, {
        id = self.node,
        name = "Collider",
        defaultHeader = true,
        draw = function()
            self:draw()
        end
    })
    return properties
end

function collider:getGroupedProperties()
    local properties = spawnable.getGroupedProperties(self)

    properties["visualization"] = {
		name = "Visualization",
        id = "collider",
		data = {},
		draw = function(_, entries)
            ImGui.Text("Collider")

            ImGui.SameLine()

            ImGui.PushID("collider")

			if ImGui.Button("Off") then
                history.addAction(history.getMultiSelectChange(entries))

				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == "worldCollisionNode" then
                        entry.spawnable.previewed = false
                        visualizer.toggleAll(entry.spawnable:getEntity(), entry.spawnable.previewed)
                    end
				end
			end

            ImGui.SameLine()

            if ImGui.Button("On") then
                history.addAction(history.getMultiSelectChange(entries))

				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == "worldCollisionNode" then
                        entry.spawnable.previewed = true
                        visualizer.toggleAll(entry.spawnable:getEntity(), entry.spawnable.previewed)
                    end
				end
			end

            ImGui.PopID()
		end,
		entries = { self.object }
	}

    return properties
end

function collider:export()
	local extents
    local shapeType
    local size
	if self.shape == 0 then
		local max = math.max(self.scale.x, self.scale.y, self.scale.z)
		extents = Vector4.new(max, max, max)
        shapeType = "Box"
        size = self.scale
	elseif self.shape == 1 then
		local max = math.max(self.scale.y, self.scale.z)
		extents = Vector4.new(max, max, max)
        shapeType = "Capsule"
        size = Vector4.new(self.scale.y, self.scale.z, 0, 0)
	elseif self.shape == 2 then
		extents = Vector4.new(self.scale.x, self.scale.x, self.scale.x)
        shapeType = "Sphere"
        size = Vector4.new(self.scale.x, 0, 0, 0)
	end

    local rotation = self.rotation:ToQuat()

    local data = spawnable.export(self)
    data.type = "worldCollisionNode"
    data.data = {
		["compiledData"] = {
			["BufferId"] = tostring(tonumber(FNV1a64("CollisionBuffer" .. math.random(1, 10000000)))),
			["Flags"] = 4063232,
			["Type"] = "WolvenKit.RED4.Archive.Buffer.CollisionBuffer, WolvenKit.RED4, Version=8.14.1.0, Culture=neutral, PublicKeyToken=null",
			["Data"] = {
				["Actors"] = {
					{
						["Position"] = {
							["$type"] = "WorldPosition",
							["x"] = {
								["$type"] = "FixedPoint",
								["Bits"] = math.floor(self.position.x * 131072)
							},
							["y"] = {
								["$type"] = "FixedPoint",
								["Bits"] = math.floor(self.position.y * 131072)
							},
							["z"] = {
								["$type"] = "FixedPoint",
								["Bits"] = math.floor(self.position.z * 131072)
							}
						},
						["Shapes"] = {
							{
								["ShapeType"] = shapeType,
                                ["Rotation"] = {
                                    ["$type"] = "Quaternion",
                                    ["i"] = rotation.i,
                                    ["j"] = rotation.j,
                                    ["k"] = rotation.k,
                                    ["r"] = rotation.r
                                  },
								["Size"] = {
									["$type"] = "Vector3",
									["X"] = size.x,
									["Y"] = size.y,
									["Z"] = size.z
								},
								["Preset"] = {
									["$type"] = "CName",
									["$storage"] = "string",
									["$value"] = presets[self.preset + 1]
								},
								["ProxyType"] = "CharacterObstacle",
								["Materials"] = {
									{
										["$type"] = "CName",
										["$storage"] = "string",
										["$value"] = materials[self.material + 1]
									}
								}
							}
						},
						["Scale"] = {
							["$type"] = "Vector3",
							["X"] = 1,
							["Y"] = 1,
							["Z"] = 1
						}
					}
				}
			}
		},
		["extents"] = {
			["$type"] = "Vector4",
			["W"] = 0,
			["X"] = extents.x,
			["Y"] = extents.y,
			["Z"] = extents.z
		},
		["lod"] = 1,
		["numActors"] = 1,
		["numMaterialIndices"] = 1,
		["numMaterials"] = 1,
		["numPresets"] = 1,
		["numScales"] = 1,
		["numShapeIndices"] = 1,
		["numShapeInfos"] = 1,
		["numShapePositions"] = 0,
		["numShapeRotations"] = 1,
        ["resourceVersion"] = 2, -- You little shit
		["staticCollisionShapeCategories"] = {
			["$type"] = "worldStaticCollisionShapeCategories_CollisionNode",
			["arr"] = {
				["Elements"] = {
					{ ["Elements"] = {0, 0, 0, 0, 0, 0} },
					{ ["Elements"] = {0, 1, 0, 0, 0, 0} },
					{ ["Elements"] = {0, 0, 0, 0, 0, 0} },
					{ ["Elements"] = {0, 0, 0, 0, 0, 0} },
					{ ["Elements"] = {0, 1, 0, 0, 0, 0} }
				}
			}
		}
	}


    return data
end

return collider