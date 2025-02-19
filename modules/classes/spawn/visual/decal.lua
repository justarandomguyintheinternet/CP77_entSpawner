local spawnable = require("modules/classes/spawn/spawnable")
local style = require("modules/ui/style")
local intersection = require("modules/utils/editor/intersection")
local preview = require("modules/utils/previewUtils")

---Class for worldStaticDecalNode
---@class decal : spawnable
---@field private alpha number
---@field private horizontalFlip boolean
---@field private verticalFlip boolean
---@field private autoHideDistance number
---@field private scale {x: number, y: number, z: number}
local decal = setmetatable({}, { __index = spawnable })

function decal:new()
	local o = spawnable.new(self)

    o.spawnListType = "list"
    o.dataType = "Decals"
    o.spawnDataPath = "data/spawnables/visual/decals/"
    o.modulePath = "visual/decal"
    o.node = "worldStaticDecalNode"
    o.description = "Places a decal on the nearest surface, from a given .mi file"
    o.icon = IconGlyphs.StickerOutline

    o.alpha = 1
    o.horizontalFlip = false
    o.verticalFlip = false
    o.autoHideDistance = 150
    o.scale = { x = 1, y = 1, z = 1 }

    o.assetPreviewType = "backdrop"
    o.assetPreviewDelay = 0.05

    setmetatable(o, { __index = self })
   	return o
end

function decal:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    local component = entDecalComponent.new()
    ResourceHelper.LoadReferenceResource(component, "material", self.spawnData, true)

    component.alpha = self.alpha
    component.horizontalFlip = self.horizontalFlip
    component.verticalFlip = self.verticalFlip
    component.autoHideDistance = self.autoHideDistance
    component.aspectRatio = 1
    component.name = "decal"
    component.visualScale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)

    entity:AddComponent(component)

    self:assetPreviewAssemble(entity)
end

function decal:getAssetPreviewPosition()
    return spawnable.getAssetPreviewPosition(self, 0.5)
end

function decal:assetPreviewAssemble(entity)
    if not self.isAssetPreview then return end

    local component = entMeshComponent.new()
    component.name = "backdrop"
    component.mesh = ResRef.FromString("base\\spawner\\base_grid.w2mesh")
    component.visualScale = Vector3.new(0.05, 0.05, 0.05)
    component:SetLocalOrientation(EulerAngles.new(0, 90, 180):ToQuat())
    entity:AddComponent(component)

    preview.addLight(entity, 5, 0.75, 1)

    local decal = entity:FindComponentByName("decal")
    decal.visualScale = Vector3.new(0.5, 0.5, 0.5)
    decal:SetLocalOrientation(EulerAngles.new(0, 90, 180):ToQuat())
end

function decal:spawn()
    local decal = self.spawnData
    self.spawnData = "base\\spawner\\empty_entity.ent"

    spawnable.spawn(self)
    self.spawnData = decal
end

function decal:save()
    local data = spawnable.save(self)
    data.alpha = self.alpha
    data.horizontalFlip = self.horizontalFlip
    data.verticalFlip = self.verticalFlip
    data.autoHideDistance = self.autoHideDistance
    data.scale = { x = self.scale.x, y = self.scale.y, z = self.scale.z }

    return data
end

function decal:getSize()
    return { x = self.scale.x, y = self.scale.y, z = 0.025 }
end

function decal:getBBox()
    return {
        min = { x = -math.abs(self.scale.x) / 2, y = -math.abs(self.scale.y) / 2, z = -0.05 },
        max = { x = math.abs(self.scale.x) / 2, y = math.abs(self.scale.y) / 2, z = 0.05 }
    }
end

function decal:calculateIntersection(origin, ray)
    if not self:getEntity() then
        return { hit = false }
    end

    local scaleFactor = 0.8

    local scaledBBox = {
        min = {  x = -math.abs(self.scale.x) * scaleFactor / 2, y = -math.abs(self.scale.y) * scaleFactor / 2, z = -math.abs(self.scale.y) * 0.05 / 2 },
        max = {  x = math.abs(self.scale.x) * scaleFactor / 2, y = math.abs(self.scale.y) * scaleFactor / 2, z = math.abs(self.scale.y) * 0.05 / 2 }
    }

    local result = intersection.getBoxIntersection(origin, ray, self.position, self.rotation, scaledBBox)

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

function decal:updateScale()
    local entity = self:getEntity()
    if not entity then return end

    local component = entity:FindComponentByName("decal")
    component.visualScale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)

    component:Toggle(false)
    component:Toggle(true)

    self:setOutline(self.outline)
end

---Respawn the decal to update parameters, if changed
---@param changed boolean
---@protected
function decal:updateFull(changed)
    if changed and self:isSpawned() then self:respawn() end
end

function decal:draw()
    spawnable.draw(self)

    ImGui.PushItemWidth(150 * style.viewSize)

    self.alpha, changed, deactivatedAfterEdit = style.trackedDragFloat(self.object, "##alpha", self.alpha, 0.01, 0, 100, "%.2f Alpha")
    self:updateFull(deactivatedAfterEdit)

    ImGui.SameLine()
    self.autoHideDistance = style.trackedDragFloat(self.object, "##autoHideDistance", self.autoHideDistance, 0.05, 0, 9999, "%.2f Hide Dist.", 100)

    self.verticalFlip, changed = style.trackedCheckbox(self.object, "Vertical Flip", self.verticalFlip)
    self:updateFull(ImGui.IsItemDeactivatedAfterEdit())

    ImGui.SameLine()
    self.horizontalFlip, changed = style.trackedCheckbox(self.object, "Horizontal Flip", self.horizontalFlip)
    self:updateFull(ImGui.IsItemDeactivatedAfterEdit())

    ImGui.PopItemWidth()
end

function decal:getProperties()
    local properties = spawnable.getProperties(self)
    table.insert(properties, {
        id = self.node,
        name = self.dataType,
        defaultHeader = true,
        draw = function()
            self:draw()
        end
    })
    return properties
end

function decal:export()
    local data = spawnable.export(self)
    data.type = "worldStaticDecalNode"
    data.scale = self.scale
    data.data = {
        alpha = self.alpha,
        autoHideDistance = self.autoHideDistance,
        horizontalFlip = self.horizontalFlip and 1 or 0,
        verticalFlip = self.verticalFlip and 1 or 0,
        isStretchingEnabled = 1,
        material = {
            DepotPath = {
                ["$storage"] = "string",
                ["$value"] = self.spawnData
            }
        }
    }

    return data
end

return decal