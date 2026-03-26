local connectedMarker = require("modules/classes/spawn/connectedMarker")
local spawnable = require("modules/classes/spawn/spawnable")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local Cron = require("modules/utils/Cron")

---Class for spline markers
---@class splineMarker : connectedMarker
local splineMarker = setmetatable({}, { __index = connectedMarker })

function splineMarker:new()
	local o = connectedMarker.new(self)

    o.spawnListType = "files"
    o.dataType = "Spline Point"
    o.spawnDataPath = "data/spawnables/meta/splineMarker/"
    o.modulePath = "meta/splineMarker"
    o.node = "---"
    o.description = "Places a point of a spline. Automatically connects with other spline points in the same group, to form a path. The parent group can be used to reference the contained spline, and use it in worldSplineNode's"
    o.icon = IconGlyphs.MapMarkerPath

    o.connectorApp = "lavender"
    o.markerApp = "yellow"
    o.previewText = "Preview Spline Points"
    o.tangentIn = { x = 0, y = 0, z = 0 }
    o.tangentOut = { x = 0, y = 0, z = 0 }
    o.automaticTangents = true
    o.symmetricTangents = false
    o.maxPropertyWidth = nil

    setmetatable(o, { __index = self })
   	return o
end

function splineMarker:loadSpawnData(data, position, rotation)
    connectedMarker.loadSpawnData(self, data, position, rotation)

    self.tangentIn = self.tangentIn or { x = 0, y = 0, z = 0 }
    self.tangentOut = self.tangentOut or { x = 0, y = 0, z = 0 }
    if self.automaticTangents == nil then
        self.automaticTangents = true
    end
    self.symmetricTangents = self.symmetricTangents or false

    -- History undo/redo reloads marker data via load(); refresh linked spline curve preview after load.
    Cron.After(0.1, function()
        self:refreshLinkedSplinesPreview()
    end)
end

function splineMarker:save()
    local data = connectedMarker.save(self)

    data.tangentIn = { x = self.tangentIn.x, y = self.tangentIn.y, z = self.tangentIn.z }
    data.tangentOut = { x = self.tangentOut.x, y = self.tangentOut.y, z = self.tangentOut.z }
    data.automaticTangents = self.automaticTangents
    data.symmetricTangents = self.symmetricTangents

    return data
end

function splineMarker:isLinkedSplineLooped()
    if not self.object or not self.object.parent or not self.object.sUI then
        return false
    end

    local parentPath = self.object.parent:getPath()
    local ownRoot = self.object:getRootParent()

    for _, entry in pairs(self.object.sUI.paths) do
        if utils.isA(entry.ref, "spawnableElement") then
            local spawnableRef = entry.ref.spawnable
            if spawnableRef
                and spawnableRef.modulePath == "meta/spline"
                and entry.ref:getRootParent() == ownRoot
                and spawnableRef.splinePath == parentPath
                and spawnableRef.looped then
                return true
            end
        end
    end

    return false
end

function splineMarker:refreshLinkedSplinesPreview(parent, forceRespawn)
    if not self.object or not self.object.sUI then
        return
    end

    if self.object.sUI.ensureCache then
        self.object.sUI.ensureCache()
    end

    parent = parent or (self.object and self.object.parent or nil)
    if not parent then
        return
    end

    local parentPath = parent.getPath and parent:getPath() or nil
    local ownRoot = parent.getRootParent and parent:getRootParent() or nil
    if not parentPath or not ownRoot then
        return
    end

    for _, entry in pairs(self.object.sUI.paths) do
        if utils.isA(entry.ref, "spawnableElement") then
            local spawnableRef = entry.ref.spawnable
            if spawnableRef
                and spawnableRef.modulePath == "meta/spline"
                and entry.ref:getRootParent() == ownRoot
                and spawnableRef.splinePath == parentPath then
                spawnableRef:loadSplinePoints()
                if forceRespawn and spawnableRef.isSpawned and spawnableRef.respawn and spawnableRef:isSpawned() then
                    -- Topology changes (add/remove/reparent marker) can leave stale curve components.
                    -- Respawn guarantees the spline preview mesh set is fully rebuilt.
                    spawnableRef:respawn()
                elseif spawnableRef.updateCurvePreview then
                    spawnableRef:updateCurvePreview()
                end
            end
        end
    end
end

function splineMarker:notifyLinkedSplinePreviewChanged()
    self:refreshLinkedSplinesPreview()
end

function splineMarker:onParentChanged(oldParent)
    connectedMarker.onParentChanged(self, oldParent)

    -- Keep linked spline previews in sync when markers are added/removed/moved between groups.
    self:refreshLinkedSplinesPreview(oldParent, true)
    local newParent = self.object and self.object.parent or nil
    if newParent ~= oldParent then
        self:refreshLinkedSplinesPreview(newParent, true)
    end
end

function splineMarker:getAutoTangentAxis(parent)
    local neighbors = self:getNeighbors(parent)
    local axis = Vector4.new(0, 1, 0, 0)
    local previous = neighbors.previous
    local nxt = neighbors.nxt

    if self:isLinkedSplineLooped() and #neighbors.neighbors > 0 then
        previous = previous or neighbors.neighbors[#neighbors.neighbors]
        nxt = nxt or neighbors.neighbors[1]
    end

    if previous and nxt then
        axis = utils.subVector(nxt.position, previous.position)
    elseif nxt then
        axis = utils.subVector(nxt.position, self.position)
    elseif previous then
        axis = utils.subVector(self.position, previous.position)
    end

    local len = axis:Length()
    if len <= 0.0001 then
        return Vector4.new(0, 1, 0, 0)
    end

    return Vector4.new(axis.x / len, axis.y / len, axis.z / len, 0)
end

function splineMarker:applyAutoTangents(parent, distanceIn, distanceOut)
    local axis = self:getAutoTangentAxis(parent)
    local currentIn = Vector4.new(self.tangentIn.x, self.tangentIn.y, self.tangentIn.z, 0):Length()
    local currentOut = Vector4.new(self.tangentOut.x, self.tangentOut.y, self.tangentOut.z, 0):Length()

    local distIn
    local distOut
    if self.symmetricTangents then
        local lockedDistance = distanceIn or distanceOut
        if not lockedDistance then
            lockedDistance = (currentIn + currentOut) / 2
        end

        distIn = lockedDistance
        distOut = lockedDistance
    else
        distIn = distanceIn or currentIn
        distOut = distanceOut or currentOut
    end

    self.tangentIn = { x = -axis.x * distIn, y = -axis.y * distIn, z = -axis.z * distIn }
    self.tangentOut = { x = axis.x * distOut, y = axis.y * distOut, z = axis.z * distOut }
end

function splineMarker:getSymmetricTangentDistance()
    local currentIn = Vector4.new(self.tangentIn.x, self.tangentIn.y, self.tangentIn.z, 0):Length()
    local currentOut = Vector4.new(self.tangentOut.x, self.tangentOut.y, self.tangentOut.z, 0):Length()
    return (currentIn + currentOut) / 2
end

function splineMarker:updateTangentGizmoVisibility()
    local entity = self:getEntity()
    if not entity then return end

    local showManualTangents = self.previewed and not self.automaticTangents
    local tangentInLine = entity:FindComponentByName("tangentInLine")
    local tangentOutLine = entity:FindComponentByName("tangentOutLine")
    local tangentIn = entity:FindComponentByName("tangentIn")
    local tangentOut = entity:FindComponentByName("tangentOut")

    if tangentInLine then tangentInLine:Toggle(showManualTangents) end
    if tangentOutLine then tangentOutLine:Toggle(showManualTangents) end
    if tangentIn then tangentIn:Toggle(showManualTangents) end
    if tangentOut then tangentOut:Toggle(showManualTangents) end
end

function splineMarker:midAssemble()
    local entity = self:getEntity()
    if not entity then return end

    local showManualTangents = self.previewed and not self.automaticTangents

    local tangentInLine = entMeshComponent.new()
    tangentInLine.name = "tangentInLine"
    tangentInLine.mesh = ResRef.FromString("base\\spawner\\cube_aligned.mesh")
    tangentInLine.meshAppearance = "lime"
    tangentInLine.visualScale = Vector3.new(0.005, 0.005, 0.005)
    tangentInLine.isEnabled = showManualTangents
    entity:AddComponent(tangentInLine)

    local tangentOutLine = entMeshComponent.new()
    tangentOutLine.name = "tangentOutLine"
    tangentOutLine.mesh = ResRef.FromString("base\\spawner\\cube_aligned.mesh")
    tangentOutLine.meshAppearance = "lime"
    tangentOutLine.visualScale = Vector3.new(0.005, 0.005, 0.005)
    tangentOutLine.isEnabled = showManualTangents
    entity:AddComponent(tangentOutLine)

    local tangentIn = entMeshComponent.new()
    tangentIn.name = "tangentIn"
    tangentIn.mesh = ResRef.FromString("base\\environment\\ld_kit\\marker.mesh")
    tangentIn.meshAppearance = "default"
    tangentIn.visualScale = Vector3.new(0.0025, 0.0025, 0.0025)
    tangentIn.isEnabled = showManualTangents
    entity:AddComponent(tangentIn)

    local tangentOut = entMeshComponent.new()
    tangentOut.name = "tangentOut"
    tangentOut.mesh = ResRef.FromString("base\\environment\\ld_kit\\marker.mesh")
    tangentOut.meshAppearance = "default"
    tangentOut.visualScale = Vector3.new(0.0025, 0.0025, 0.0025)
    tangentOut.isEnabled = showManualTangents
    entity:AddComponent(tangentOut)

    self:updateTangentMarkers()
end

function splineMarker:updateTangentMarkers()
    local entity = self:getEntity()
    if not entity then return end

    local tangentInLine = entity:FindComponentByName("tangentInLine")
    local tangentOutLine = entity:FindComponentByName("tangentOutLine")
    local tangentIn = entity:FindComponentByName("tangentIn")
    local tangentOut = entity:FindComponentByName("tangentOut")
    if not tangentInLine or not tangentOutLine or not tangentIn or not tangentOut then return end

    local function updateTangent(line, marker, tangent)
        local diff = Vector4.new(tangent.x, tangent.y, tangent.z, 0)
        local length = diff:Length()
        local yaw = 0
        local roll = 0

        if length > 0.0001 then
            yaw = diff:ToRotation().yaw + 90
            roll = diff:ToRotation().pitch
        end

        line.visualScale = Vector3.new(math.max(0.0001, length / 2), 0.01, 0.01)
        line:SetLocalOrientation(EulerAngles.new(roll, 0, yaw):ToQuat())
        line:RefreshAppearance()

        marker:SetLocalPosition(Vector4.new(tangent.x, tangent.y, tangent.z, 0))
        marker:RefreshAppearance()
    end

    updateTangent(tangentInLine, tangentIn, self.tangentIn)
    updateTangent(tangentOutLine, tangentOut, self.tangentOut)
    self:updateTangentGizmoVisibility()
end

function splineMarker:setPreview(state)
    connectedMarker.setPreview(self, state)
    self:updateTangentGizmoVisibility()
end

function splineMarker:getNeighbors(parent)
    parent = parent or self.object.parent
    local neighbors = {}
    local selfIndex = 0

    for _, entry in pairs(parent.childs) do
        if utils.isA(entry, "spawnableElement") and entry.spawnable.modulePath == self.modulePath and entry ~= self.object then
            table.insert(neighbors, entry.spawnable)
        elseif entry == self.object then
            selfIndex = #neighbors + 1
        end
    end

    local previous = selfIndex == 1 and nil or neighbors[selfIndex - 1]
    local nxt = selfIndex > #neighbors and nil or neighbors[selfIndex]

    if self:isLinkedSplineLooped() and #neighbors > 0 then
        previous = previous or neighbors[#neighbors]
        nxt = nxt or neighbors[1]
    end

    return { neighbors = neighbors, selfIndex = selfIndex, previous = previous, nxt = nxt }
end

function splineMarker:getTransform(parent)
    local neighbors = self:getNeighbors(parent)
    local width = 0.01
    local yaw = self.rotation.yaw
    local roll = self.rotation.pitch

    if #neighbors.neighbors > 0 and neighbors.nxt then
        local diff = utils.subVector(neighbors.nxt.position, self.position)
        yaw = diff:ToRotation().yaw + 90
        roll = diff:ToRotation().pitch
        width = diff:Length() / 2
    end

    return {
        scale = { x = width, y = 0.01, z = 0.01 },
        rotation = { roll = roll, pitch = 0, yaw = yaw },
    }
end

function splineMarker:updateStraightSegmentMesh(parent)
    local entity = self:getEntity()
    if not entity then return end

    local transform = self:getTransform(parent)
    local mesh = entity:FindComponentByName("mesh")
    if not mesh then return end

    mesh.visualScale = Vector3.new(transform.scale.x, 0.01, transform.scale.z)
    mesh:SetLocalOrientation(EulerAngles.new(transform.rotation.roll, transform.rotation.pitch, transform.rotation.yaw):ToQuat())
end

function splineMarker:updateTransform(parent)
    spawnable.update(self)

    if self.symmetricTangents then
        self:applyAutoTangents(parent)
    end

    self:updateStraightSegmentMesh(parent)
    self:updateTangentMarkers()
end

function splineMarker:update()
    connectedMarker.update(self)
    self:notifyLinkedSplinePreviewChanged()
end

function splineMarker:draw()
    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth({ self.previewText, "Automatic Tangents", "Parallel symmetrical tangents", "Distance", "Tangent In", "Tangent Out" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    style.mutedText(self.previewText)
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    local changed
    self.previewed, changed = style.trackedCheckbox(self.object, "##visualize", self.previewed)
    if changed then
        self:setPreview(self.previewed)

        for _, neighbor in pairs(self:getNeighbors().neighbors) do
            neighbor:setPreview(self.previewed)
        end
    end

    style.mutedText("Automatic Tangents")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.automaticTangents, changed = style.trackedCheckbox(self.object, "##automaticTangents", self.automaticTangents)
    style.tooltip("When enabled, the tangent is automatically smoothed from neighbor points.")
    if changed then
        self:updateTangentGizmoVisibility()
        self:notifyLinkedSplinePreviewChanged()
    end

    if self.automaticTangents then
        return
    end

    style.mutedText("Parallel symmetrical tangents")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.symmetricTangents, changed = style.trackedCheckbox(self.object, "##symmetricTangents", self.symmetricTangents)
    if changed then
        if self.symmetricTangents then
            local distance = self:getSymmetricTangentDistance()
            self:applyAutoTangents(self.object.parent, distance, distance)
            self:updateTangentMarkers()
        end
        self:notifyLinkedSplinePreviewChanged()
    end

    if self.symmetricTangents then
        style.mutedText("Distance")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxPropertyWidth)
        local distance = self:getSymmetricTangentDistance()
        local changedDistance
        distance, changedDistance = style.trackedDragFloat(self.object, "##symmetricTangentDistance", distance, 0.05, 0, 99999, "%.2f", 110)
        ImGui.PushID("resetSymmetricTangentDistance")
        local resetDistance = style.drawNoBGConditionalButton(true, IconGlyphs.Close)
        ImGui.PopID()
        if resetDistance then
            distance = 0
            changedDistance = true
        end

        if changedDistance then
            self:applyAutoTangents(self.object.parent, distance, distance)
            self:updateTangentMarkers()
            self:notifyLinkedSplinePreviewChanged()
        end

        return
    end

    style.mutedText("Tangent In")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    local changedX
    local changedY
    local changedZ
    self.tangentIn.x, changedX = style.trackedDragFloat(self.object, "##tangentInX", self.tangentIn.x, 0.05, -99999, 99999, "%.2f X", 75)
    ImGui.SameLine()
    self.tangentIn.y, changedY = style.trackedDragFloat(self.object, "##tangentInY", self.tangentIn.y, 0.05, -99999, 99999, "%.2f Y", 75)
    ImGui.SameLine()
    self.tangentIn.z, changedZ = style.trackedDragFloat(self.object, "##tangentInZ", self.tangentIn.z, 0.05, -99999, 99999, "%.2f Z", 75)
    ImGui.PushID("resetTangentIn")
    local resetIn = style.drawNoBGConditionalButton(true, IconGlyphs.Close)
    ImGui.PopID()
    if resetIn then
        self.tangentIn.x = 0
        self.tangentIn.y = 0
        self.tangentIn.z = 0
        changedX = true
    end
    if changedX or changedY or changedZ then
        self:updateTangentMarkers()
        self:notifyLinkedSplinePreviewChanged()
    end

    style.mutedText("Tangent Out")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    changedX = nil
    changedY = nil
    changedZ = nil
    self.tangentOut.x, changedX = style.trackedDragFloat(self.object, "##tangentOutX", self.tangentOut.x, 0.05, -99999, 99999, "%.2f X", 75)
    ImGui.SameLine()
    self.tangentOut.y, changedY = style.trackedDragFloat(self.object, "##tangentOutY", self.tangentOut.y, 0.05, -99999, 99999, "%.2f Y", 75)
    ImGui.SameLine()
    self.tangentOut.z, changedZ = style.trackedDragFloat(self.object, "##tangentOutZ", self.tangentOut.z, 0.05, -99999, 99999, "%.2f Z", 75)
    ImGui.PushID("resetTangentOut")
    local resetOut = style.drawNoBGConditionalButton(true, IconGlyphs.Close)
    ImGui.PopID()
    if resetOut then
        self.tangentOut.x = 0
        self.tangentOut.y = 0
        self.tangentOut.z = 0
        changedX = true
    end
    if changedX or changedY or changedZ then
        self:updateTangentMarkers()
        self:notifyLinkedSplinePreviewChanged()
    end
end

return splineMarker
