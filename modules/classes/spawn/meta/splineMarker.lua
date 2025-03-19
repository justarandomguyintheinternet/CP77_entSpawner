local connectedMarker = require("modules/classes/spawn/connectedMarker")
local spawnable = require("modules/classes/spawn/spawnable")
local utils = require("modules/utils/utils")

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

    o.connectorApp = "violet"
    o.markerApp = "yellow"
    o.previewText = "Preview Spline"

    setmetatable(o, { __index = self })
   	return o
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

    local nxt = selfIndex > #neighbors and nil or neighbors[selfIndex]

    return { neighbors = neighbors, selfIndex = selfIndex, previous = nil, nxt = nxt }
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

---Updates the x scale and yaw rotation of the outline marker based on the neighbors
function splineMarker:updateTransform(parent)
    spawnable.update(self)

    local entity = self:getEntity()
    if not entity then return end

    local transform = self:getTransform(parent)
    local mesh = entity:FindComponentByName("mesh")
    mesh.visualScale = Vector3.new(transform.scale.x, 0.01, transform.scale.z)
    mesh:SetLocalOrientation(EulerAngles.new(transform.rotation.roll, transform.rotation.pitch, transform.rotation.yaw):ToQuat())

    mesh:RefreshAppearance()
end

return splineMarker