local style = require("modules/ui/style")
local visualizer = require("modules/utils/visualizer")
local settings = require("modules/utils/settings")
local utils = require("modules/utils/utils")
local intersection = require("modules/utils/editor/intersection")
local builder = require("modules/utils/entityBuilder")
local cache = require("modules/utils/cache")
local collisionMeshesUtils = require("modules/utils/data/collisionMeshes")

local colliderBase = require("modules/classes/spawn/collision/colliderBase")
local materials = colliderBase.getColliderGenerics().materials
local presets = colliderBase.getColliderGenerics().presets
local colors = colliderBase.getColliderGenerics().colors

--- Class for worldCollisionNode with convex or triangle collision mesh
--- @see colliderBase
--- @class meshCollider : colliderBase
--- @field sectorHash string
--- @field shapeHash string
--- @field meshType string
--- @field material integer
--- @field preset integer
--- @field scale Vector3
--- @field bBox table
--- @field bBoxLoaded boolean
--- @field apps table
--- @field previewArchiveInstalled boolean
--- @field previewed boolean
--- @field maxPropertyWidth number
local meshCollider = setmetatable({}, { __index = colliderBase })

function meshCollider:new()
    local o = colliderBase.new(self)

    o.spawnListType = "list"
    o.dataType = "Collision Mesh"
    o.spawnDataPath = "data/spawnables/colliders/"
    o.modulePath = "collision/meshCollider"
    o.node = "worldCollisionNode"
    o.description = "A collision mesh."

    o.sectorHash = nil
    o.shapeHash = nil
    o.meshType = nil

    o.scale = Vector3.new(1, 1, 1)

    o.bBox = { min = Vector4.new(-0.5, -0.5, -0.5, 0), max = Vector4.new( 0.5, 0.5, 0.5, 0) }
    o.bBoxLoaded = false
    o.apps = {}
    o.previewArchiveInstalled = false

    self.__index = self
    return setmetatable(o, self)
end

---@param data table
---@param position Vector4
---@param rotation EulerAngles
function meshCollider:loadSpawnData(data, position, rotation)
    self.previewArchiveInstalled = utils.archiveInstalled("scc_collision.archive")

    if (data.scale) then
        self.scale = Vector3.new(data.scale.x, data.scale.y, data.scale.z)
    end

    colliderBase.loadSpawnData(self, data, position, rotation)

    --[[ 
    a bit cursed but eh, spawnUI sets the the display / index value which is intended to be a 
    resource path to the resource, but for collision meshes it's using the sectorHash, shapeHash and meshType
    instead so this needs to reparse it to avoid modifying spawnUI
    ]]--
    if (not string.find(data.spawnData, "%.")) then
        local sectorHash, shapeHash, shapeType = collisionMeshesUtils.parseCollisionMeshesFileLine(data.spawnData)
        if sectorHash and shapeHash and shapeType then
            self.sectorHash = sectorHash
            self.shapeHash = shapeHash
            self.meshType = shapeType
        end
    end

    if not self.previewArchiveInstalled then
        self.previewed = false
        self.spawnData = "base\\spawner\\empty_entity.ent"
        return
    end

    if self.shapeHash then
        self.spawnData = "scc\\generated\\geometry_cache\\collision\\" .. self.shapeHash .. ".ent"
    end

    local meshPath = "scc\\generated\\geometry_cache\\visual\\" .. self.shapeHash .. ".mesh"

    cache.tryGet(meshPath .. "_apps", meshPath .. "_bBox_max", meshPath .. "_bBox_min", meshPath .. "_occluder")
    .notFound(function (task)
        self.bBox.max = Vector4.new(0.5, 0.5, 0.5, 0) -- Temp values, so that onAssemble//updateScale can work
        self.bBox.min = Vector4.new(-0.5, -0.5, -0.5, 0)

        builder.registerLoadResource(meshPath, function (resource)
            local apps = {}
            for _, appearance in ipairs(resource.appearances) do
                table.insert(apps, appearance.name.value)
            end

            self.bBox.min = resource.boundingBox.Min
            self.bBox.max = resource.boundingBox.Max

            local occluder = false
            for _, param in pairs(resource.parameters) do
                if param:IsA("meshMeshParamOccluderData") then
                    occluder = true
                    break
                end
            end

            -- Save to cache
            cache.addValue(meshPath .. "_apps", apps)
            cache.addValue(meshPath .. "_bBox_max", utils.fromVector(self.bBox.max))
            cache.addValue(meshPath .. "_bBox_min", utils.fromVector(self.bBox.min))
            cache.addValue(meshPath .. "_occluder", occluder)

            task:taskCompleted()

            if self:isSpawned() and self.isAssetPreview then
                self:assetPreviewSetPosition()
            end
        end)
    end)
    .found(function ()
        self.bBox.max = cache.getValue(meshPath .. "_bBox_max")
        self.bBox.min = cache.getValue(meshPath .. "_bBox_min")
        self.bBoxLoaded = true
    end)
end

function meshCollider:onAssemble(entity)
    colliderBase.onAssemble(self, entity)

    if not self.previewArchiveInstalled then return end

    local component = entity:FindComponentByName("collision_mesh_0")
    if not component then
        print("Error: collision_mesh_0 component not found on entity. Cannot set up mesh collider.")
        return
    end
    component.filterData.preset = self.preset
    component.colliders[1].material = materials[self.material + 1]

    if not self.sectorHash or not self.shapeHash or not self.meshType then
        print("Error: Missing sectorHash, shapeHash, or meshType. Cannot add visualizer mesh.")
        return
    end

    visualizer.addMesh(entity,
        {x = 1, y = 1, z = 1},
        "scc\\generated\\geometry_cache\\visual\\" .. self.shapeHash .. ".mesh",
        colors[settings.colliderColor + 1])
end

function meshCollider:save()
    local data = colliderBase.save(self)

    data.sectorHash = self.sectorHash
    data.shapeHash = self.shapeHash
    data.meshType = self.meshType

    data.material = self.material
    data.preset = self.preset

    data.previewed = self.previewed

    data.scale = { x = self.scale.x, y = self.scale.y, z = self.scale.z }

    return data
end

function meshCollider:getSize()
    return { x = 1, y = 1, z = 1 }
end

function meshCollider:getArrowSize()
    return { x = 1, y = 1, z = 1 }
end

function meshCollider:calculateIntersection(origin, ray)
    if not self:getEntity() then
        return { hit = false }
    end

    local scaleFactor = intersection.getResourcePathScalingFactor(self.spawnData, self:getSize())

    local scaledBBox = {
        min = {  x = self.bBox.min.x * scaleFactor.x, y = self.bBox.min.y * scaleFactor.y, z = self.bBox.min.z * scaleFactor.z },
        max = {  x = self.bBox.max.x * scaleFactor.x, y = self.bBox.max.y * scaleFactor.y, z = self.bBox.max.z * scaleFactor.z }
    }
    local result = intersection.getBoxIntersection(origin, ray, self.position, self.rotation, scaledBBox)

    local unscaledHit
    if result.hit then
        unscaledHit = intersection.getBoxIntersection(origin, ray, self.position, self.rotation, intersection.unscaleBBox(self.spawnData, self:getSize(), scaledBBox))
    end

    return {
        hit = result.hit,
        position = result.position,
        unscaledHit = unscaledHit and unscaledHit.position or result.position,
        collisionType = "bbox",
        distance = result.distance,
        bBox = scaledBBox,
        objectOrigin = self.position,
        objectRotation = self.rotation,
        normal = result.normal
    }
end

function meshCollider:draw()
    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth({ "Preview Shape", "Collision Preset", "Collision Material" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    local noPreview = not self.previewArchiveInstalled

    style.mutedText("Preview Shape")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    style.pushGreyedOut(noPreview)
    self.previewed, changed = style.trackedCheckbox(self.object, "##collisionPreview", self.previewed, noPreview)
    style.popGreyedOut(noPreview)
    if changed then
        visualizer.toggleAll(self:getEntity(), self.previewed)
    end

    if noPreview then
        ImGui.SameLine()
        style.styledText(IconGlyphs.AlertOutline, 0xFF0000FF)
        style.tooltip("Preview disabled due to missing scc_collision.archive\nIf you wish to have collision mesh previews, please download the optional \"Collision Mesh Preview\" archive and install it.")
    end

    colliderBase.draw(self)
end

function meshCollider:export()
    local rotation = self.rotation:ToQuat()
    local shapeType = self.meshType
    local sectorHash = self.sectorHash
    local extends = {
        x = math.abs(self.bBox.max.x - self.bBox.min.x) / 2,
        y = math.abs(self.bBox.max.y - self.bBox.min.y) / 2,
        z = math.abs(self.bBox.max.z - self.bBox.min.z) / 2
    }

    if shapeType == "BV4TriangleMesh" then
        shapeType = "TriangleMesh"
    end

    -- This just needs to be any non 0 value that isn't already a sector, the game defaults non existent sectors to the always loaded one
    if sectorHash == "0" then
        sectorHash = "1"
    end

    local data = colliderBase.export(self)
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
                                ["Hash"] = self.shapeHash,
                                ["Position"] = {
									["$type"] = "Vector3",
									["X"] = 0,
									["Y"] = 0,
									["Z"] = 0
								},
                                ["Rotation"] = {
                                    ["$type"] = "Quaternion",
                                    ["i"] = rotation.i,
                                    ["j"] = rotation.j,
                                    ["k"] = rotation.k,
                                    ["r"] = rotation.r
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
								},
                                ["Uk1"] = 0,
                                ["Uk2"] = 0,
                                ["Uk3"] = 0
							}
						},
						["Scale"] = {
							["$type"] = "Vector3",
							["X"] = self.scale.x,
							["Y"] = self.scale.y,
							["Z"] = self.scale.z
						}
					}
				}
			}
		},
		["extents"] = {
			["$type"] = "Vector4",
			["W"] = 0,
			["X"] = extends.x,
			["Y"] = extends.y,
			["Z"] = extends.z
		},
		["lod"] = 1,
		["numActors"] = 1,
		["numMaterialIndices"] = 1,
		["numMaterials"] = 1,
		["numPresets"] = 1,
		["numScales"] = 1,
		["numShapeIndices"] = 1,
		["numShapeInfos"] = 1,
		["numShapePositions"] = 1,
		["numShapeRotations"] = 1,
        ["resourceVersion"] = 2, -- You little shit
        ["sectorHash"] = sectorHash,
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

return meshCollider