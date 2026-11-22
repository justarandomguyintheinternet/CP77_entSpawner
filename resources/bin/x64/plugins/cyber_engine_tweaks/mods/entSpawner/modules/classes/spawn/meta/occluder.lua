local spawnable = require("modules/classes/spawn/spawnable")
local visualized = require("modules/classes/spawn/visualized")
local style = require("modules/ui/style")
local utils = require("modules/utils/core/utils")
local visualizer = require("modules/utils/preview/visualizer")
local builder = require("modules/utils/game/entityBuilder")
local cache = require("modules/utils/game/cache")

local function bounds(minX, minY, minZ, maxX, maxY, maxZ)
    return { min = { x = minX, y = minY, z = minZ }, max = { x = maxX, y = maxY, z = maxZ } }
end

local UNIT_BOUNDS = bounds(-0.5, -0.5, -0.5, 0.5, 0.5, 0.5)

-- Bounds are the occluder geometry of each editor mesh (meshMeshParamOccluderData), game 2.5.
local occluderMeshes = {
    { name = "Box", path = "engine\\meshes\\editor\\box_occluder.w2mesh", bounds = UNIT_BOUNDS },
    { name = "Plane Two-Sided XY", path = "engine\\meshes\\editor\\plane_occluder_twosided.mesh", bounds = bounds(-0.5, -0.5, -0.001, 0.5, 0.5, 0.001) },
    { name = "Plane Two-Sided XZ", path = "engine\\meshes\\editor\\plane_occluder_twosided_xz.mesh", bounds = bounds(-0.5, -0.001, -0.5, 0.5, 0.001, 0.5) },
    { name = "Plane Two-Sided YZ", path = "engine\\meshes\\editor\\plane_occluder_twosided_yz.mesh", bounds = bounds(-0.001, -0.5, -0.5, 0.001, 0.5, 0.5) },
    { name = "Plane One-Sided XY", path = "engine\\meshes\\editor\\plane_occluder_onesided.mesh", bounds = bounds(-0.5, -0.5, -0.001, 0.5, 0.5, 0.001) },
    { name = "Plane One-Sided XZ", path = "engine\\meshes\\editor\\plane_occluder_onesided_xz.mesh", bounds = bounds(-0.5, -0.001, -0.5, 0.5, 0.001, 0.5) },
    { name = "Plane One-Sided YZ", path = "engine\\meshes\\editor\\plane_occluder_onesided_yz.mesh", bounds = bounds(-0.001, -0.5, -0.5, 0.001, 0.5, 0.5) },
    { name = "Plane Small XY", path = "engine\\meshes\\editor\\plane_occluder.mesh", bounds = bounds(-0.15, -0.15, 0, 0.15, 0.15, 0) },
    { name = "Corner Box", path = "engine\\meshes\\editor\\occluder_corner_pivot_box.mesh", bounds = bounds(0, -1, 0, 1, 0, 1) },
    { name = "Corner Plane Two-Sided", path = "engine\\meshes\\editor\\occluder_corner_pivot_plane_2side.mesh", bounds = bounds(0, -1, 0, 0, 0, 1) },
    { name = "Corner Plane One-Sided", path = "engine\\meshes\\editor\\occluder_corner_pivot_plane_1side.mesh", bounds = bounds(0, -1, 0, 0, 0, 1) }
}

local meshNames = {}
local meshIndexByPath = {}
for index, entry in ipairs(occluderMeshes) do
    meshNames[index] = entry.name
    meshIndexByPath[entry.path] = index
end
table.insert(meshNames, "Custom")
local CUSTOM_INDEX = #meshNames

-- Mesh indices of saved data before meshPath existed.
local LEGACY_MESH_PATHS = {
    "engine\\meshes\\editor\\box_occluder.w2mesh",
    "engine\\meshes\\editor\\plane_occluder_onesided_xz.mesh",
    "engine\\meshes\\editor\\plane_occluder_twosided_xz.mesh"
}

-- Thinnest outline drawn, in meters, so planes stay visible and clickable.
local MIN_OUTLINE_THICKNESS = 0.01

---Bounds of custom meshes, by path: `{ min, max, occluder, missing? }`, or `false` while loading.
---@type table<string, table|boolean>
local customBounds = {}
---Occluders to refresh once a path's bounds load, by path.
---@type table<string, table<occluder, boolean>>
local boundsWaiters = {}

---@param box userdata Box
---@return table?
local function readBox(box)
    if not box then return nil end
    local result = bounds(box.Min.x, box.Min.y, box.Min.z, box.Max.x, box.Max.y, box.Max.z)
    if result.min.x > result.max.x or result.min.y > result.max.y or result.min.z > result.max.z then
        return nil
    end
    return result
end

---@param path string
---@return boolean
local function hasMeshExtension(path)
    local extension = path:match("%.([%w_]+)$")
    extension = extension and extension:lower()
    return extension == "mesh" or extension == "w2mesh"
end

---Loads the occluder bounds of a mesh, then refreshes `requester`. Cached across sessions.
---@param path string
---@param requester occluder
local function requestCustomBounds(path, requester)
    if customBounds[path] == false then
        boundsWaiters[path][requester] = true
    end
    if customBounds[path] ~= nil then return end

    local cached = cache.getValue(path .. "_occluderBounds")
    if cached then
        customBounds[path] = cached
        return
    end

    local okExists, exists = pcall(function ()
        return Game.GetResourceDepot():ResourceExists(ResRef.FromString(path))
    end)
    if not hasMeshExtension(path) or (okExists and not exists) then
        -- Not persisted: the path may exist once another archive is loaded.
        local result = utils.deepcopy(UNIT_BOUNDS)
        result.missing = true
        customBounds[path] = result
        return
    end

    customBounds[path] = false
    boundsWaiters[path] = setmetatable({ [requester] = true }, { __mode = "k" })
    builder.registerLoadResource(path, function (resource)
        local box, occluder
        pcall(function ()
            for _, param in pairs(resource.parameters) do
                if param:IsA("meshMeshParamOccluderData") then
                    occluder = true
                    -- The occluder geometry can reach past the render mesh bounds.
                    box = readBox(param.occluderResource.boundingBox)
                    break
                end
            end
            box = box or readBox(resource.boundingBox)
        end)

        local result = box or utils.deepcopy(UNIT_BOUNDS)
        result.occluder = occluder == true
        customBounds[path] = result
        cache.addValue(path .. "_occluderBounds", result)

        local waiters = boundsWaiters[path] or {}
        boundsWaiters[path] = nil
        for waiter in pairs(waiters) do
            if waiter.meshPath == path then
                waiter:updateScale(false)
            end
        end
    end)
end

---Class for worldStaticOccluderMeshNode
---@class occluder : visualized
---@field public scale {x: number, y: number, z: number}
---@field public occluderType integer
---@field public meshPath string
---@field public autohideDistanceScale integer
---@field private customMeshSelected boolean? Custom picked while the path is still a preset one.
---@field private previewed boolean
---@field private occluderTypes table
---@field public maxPropertyWidth number
local occluder = setmetatable({}, { __index = visualized })

function occluder:new()
	local o = visualized.new(self)

    o.spawnListType = "files"
    o.dataType = "Static Occluder"
    o.spawnDataPath = "data/spawnables/meta/occluder/"
    o.modulePath = "meta/occluder"
    o.node = "worldStaticOccluderMeshNode"
    o.description = "Places an occluder of variable size and shape, which will cause anything completely behind it to not be rendered."
    o.icon = IconGlyphs.CubeOffOutline

    o.occluderTypes = utils.enumTable("visWorldOccluderType")

    o.scale = { x = 1, y = 1, z = 1 }
    o.occluderType = 0
    o.meshPath = occluderMeshes[1].path
    o.autohideDistanceScale = 255
    o.previewed = true
    o.previewShape = "box"
    o.maxPropertyWidth = nil

    setmetatable(o, { __index = self })
   	return o
end

function occluder:loadSpawnData(data, position, rotation)
    visualized.loadSpawnData(self, data, position, rotation)

    if data.meshPath == nil then
        self.meshPath = LEGACY_MESH_PATHS[data.occluderMesh or 1] or LEGACY_MESH_PATHS[1]
    end

    -- loadSpawnData shares tables with its long-lived payload.
    self.scale = utils.deepcopy(self.scale)
end

---@return boolean
function occluder:isCustomMesh()
    return meshIndexByPath[self.meshPath] == nil
end

---Unscaled occluder bounds of the current mesh. Custom meshes use the unit box until loaded.
---@return table
function occluder:getMeshBounds()
    local index = meshIndexByPath[self.meshPath]
    if index then
        return occluderMeshes[index].bounds
    end

    requestCustomBounds(self.meshPath, self)

    return customBounds[self.meshPath] or UNIT_BOUNDS
end

function occluder:getBBox()
    local meshBounds = self:getMeshBounds()
    local box = { min = {}, max = {} }

    for _, axis in ipairs({ "x", "y", "z" }) do
        -- A negative scale mirrors the mesh, which moves an off-center one to the other side.
        local a, b = meshBounds.min[axis] * self.scale[axis], meshBounds.max[axis] * self.scale[axis]
        box.min[axis], box.max[axis] = math.min(a, b), math.max(a, b)

        local missing = MIN_OUTLINE_THICKNESS - (box.max[axis] - box.min[axis])
        if missing > 0 then
            box.min[axis] = box.min[axis] - missing / 2
            box.max[axis] = box.max[axis] + missing / 2
        end
    end

    return box
end

function occluder:getSize()
    local box = self:getBBox()
    return { x = box.max.x - box.min.x, y = box.max.y - box.min.y, z = box.max.z - box.min.z }
end

function occluder:getCenter()
    return utils.getBoxCenter(self:getBBox(), nil, self.rotation, self.position)
end

---Sizes and places the outline on the occluder bounds.
---@param entity entEntity
---@private
function occluder:updateOutline(entity)
    local box = self:getBBox()

    local component = entity:FindComponentByName("box")
    if component then
        component:SetLocalPosition(Vector4.new((box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2, (box.min.z + box.max.z) / 2, 0))
    end

    -- Also toggles the component, which applies the new position.
    visualizer.updateScale(entity, {
        x = (box.max.x - box.min.x) / 2,
        y = (box.max.y - box.min.y) / 2,
        z = (box.max.z - box.min.z) / 2
    }, "box")
end

function occluder:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    visualizer.addBox(entity, { x = 0.5, y = 0.5, z = 0.5 }, "green")
    self:updateOutline(entity)

    local component = entStaticOccluderMeshComponent.new()
    component.name = "occluder"
    ResourceHelper.LoadReferenceResource(component, "mesh", self.meshPath, true)
    component.scale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)
    component.occluderType = Enum.new("visWorldOccluderType", self.occluderType)
    component.occluderAutohideDistanceScale = self.autohideDistanceScale
    entity:AddComponent(component)

    visualizer.updateScale(entity, self:getArrowSize(), "arrows")
    visualizer.toggleAll(entity, self.previewed)
end

function occluder:spawn()
    self.spawnData = "base\\spawner\\empty_entity.ent"
    spawnable.spawn(self)
end

function occluder:save()
    local data = visualized.save(self)

    data.scale = { x = self.scale.x, y = self.scale.y, z = self.scale.z }
    data.occluderType = self.occluderType
    data.meshPath = self.meshPath
    data.autohideDistanceScale = self.autohideDistanceScale
    return data
end

---@protected
function occluder:updateScale(finished)
    if finished then
        self:respawn()
        return
    end

    local entity = self:getEntity()
    if not entity then return end

    visualizer.updateScale(entity, self:getArrowSize(), "arrows")
    self:updateOutline(entity)
end

function occluder:calculateIntersection(origin, ray)
    if not self.previewed then
        return { hit = false }
    end

    return spawnable.calculateIntersection(self, origin, ray)
end

---Draws a muted label and moves the cursor to the property column.
---@param label string
function occluder:propertyLabel(label)
    style.mutedText(label)
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
end

function occluder:draw()
    spawnable.draw(self)

    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth({ "Visualize outline", "Occluder Mesh", "Mesh Path", "Occluder Type", "Auto-Hide Distance" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    self:drawPreviewCheckbox("Visualize outline", self.maxPropertyWidth)

    local changed, finished

    self:propertyLabel("Occluder Mesh")
    local selected = (self.customMeshSelected or self:isCustomMesh()) and CUSTOM_INDEX or meshIndexByPath[self.meshPath]
    local value
    value, changed = style.trackedCombo(self.object, "##occluderMesh", selected - 1, meshNames, 170)
    if changed and value + 1 ~= selected then
        if value + 1 ~= CUSTOM_INDEX then
            self.customMeshSelected = nil
            self.meshPath = occluderMeshes[value + 1].path
            self:respawn()
        else
            -- Custom starts from the current path, to be edited from there.
            self.customMeshSelected = true
        end
    end

    if selected == CUSTOM_INDEX or self.customMeshSelected then
        self:propertyLabel("Mesh Path")
        self.meshPath, _, finished = style.trackedTextField(self.object, "##meshPath", self.meshPath, "path\\to\\occluder.mesh", -1)
        if finished then
            self.meshPath = utils.trimString(self.meshPath)
            self.customMeshSelected = nil
            self:respawn()
        end

        local loaded = self:isCustomMesh() and customBounds[self.meshPath]
        if type(loaded) == "table" then
            if loaded.missing then
                style.styledText(IconGlyphs.AlertOutline .. " Not a .mesh in the loaded archives.", style.warnColor)
            elseif not loaded.occluder then
                style.styledText(IconGlyphs.AlertOutline .. " No occluder data: this mesh occludes nothing.", style.warnColor)
            end
        end
    end

    self:propertyLabel("Occluder Type")
    self.occluderType, changed = style.trackedCombo(self.object, "##occluderType", self.occluderType, self.occluderTypes, 170)
    if changed then
        local entity = self:getEntity()

        if entity then
            local component = entity:FindComponentByName("occluder")
            component.occluderType = Enum.new("visWorldOccluderType", self.occluderType)
        end
    end

    self:propertyLabel("Auto-Hide Distance")
    self.autohideDistanceScale, changed, finished = style.trackedIntInput(self.object, "##autohideDistanceScale", self.autohideDistanceScale, 0, 255, 80, 1, 10)
    style.tooltip("Auto-hide distance scale, 0 to 255.\nVanilla keeps 255 on 80% of occluders, then 80, 50 or 100.")
    -- A step button click changes the value without a deactivation.
    if finished or (changed and not ImGui.IsItemActive()) then
        self:respawn()
    end
end

function occluder:getProperties()
    return self:addNodeProperty(spawnable.getProperties(self))
end

function occluder:getGroupedProperties()
    local properties = spawnable.getGroupedProperties(self)

    properties["visualization"] = {
		name = "Visualization",
        id = "occluder",
		data = {},
		draw = function(_, entries)
            ImGui.Text("Occluder")

            ImGui.SameLine()

            ImGui.PushID("occluder")

			if ImGui.Button("Off") then
				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == "worldStaticOccluderMeshNode" then
                        entry.spawnable:setPreview(false)
                    end
				end
			end

            ImGui.SameLine()

            if ImGui.Button("On") then
				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == "worldStaticOccluderMeshNode" then
                        entry.spawnable:setPreview(true)
                    end
				end
			end

            ImGui.PopID()
		end,
		entries = { self.object }
	}

    return properties
end

function occluder:export()
    local data = spawnable.export(self)
    data.type = "worldStaticOccluderMeshNode"
    data.scale = self.scale
    data.data = {
        ["occluderType"] = self.occluderTypes[self.occluderType + 1],
        ["autohideDistanceScale"] = math.floor(self.autohideDistanceScale),
        ["mesh"] = {
            ["DepotPath"] = {
                ["$type"] = "ResourcePath",
                ["$storage"] = "string",
                ["$value"] = self.meshPath
            },
            Flags = "Default"
        }
    }

    return data
end

return occluder
