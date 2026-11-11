local utils = require("modules/utils/core/utils")

---Sector streaming box geometry, shared by the Export tab and the group export pipeline.
---The box is derived from the exported elements' positions, never from a group's origin.
local streamingBox = {}

---Largest per-element streaming range Auto accounts for.
streamingBox.rangeCap = 250
---Safety factor Auto applies to the computed extents.
streamingBox.margin = 1.2
---Smallest extent Auto produces on any axis.
streamingBox.minExtent = 10

---@param element element?
---@return boolean
function streamingBox.isExportDisabled(element)
    local node = element
    while node do
        if node.exportDisabled == true then
            return true
        end
        node = node.parent
    end

    return false
end

---Export-flag check for a node, without the spawnable type check.
---@param element element
---@return boolean
function streamingBox.shouldExportNode(element)
    if streamingBox.isExportDisabled(element) then
        return false
    end

    return not utils.isA(element.parent, "randomizedGroup") or element.visible
end

---@param element element
---@return boolean
function streamingBox.isExported(element)
    return utils.isA(element, "spawnableElement")
        and element.spawnable ~= nil
        and not element.spawnable.noExport
        and streamingBox.shouldExportNode(element)
end

---@param element element
---@param result element[]
local function collect(element, result)
    for _, child in ipairs(element.childs or {}) do
        if streamingBox.isExported(child) then
            table.insert(result, child)
        end
        collect(child, result)
    end
end

---Exported spawnable elements below `root`.
---@param root element
---@return element[]
function streamingBox.collectExported(root)
    local result = {}
    if root then
        collect(root, result)
    end

    return result
end

---Midpoint of the elements' positions.
---@param elements element[]
---@return {x: number, y: number, z: number}?
function streamingBox.getContentCenter(elements)
    local min, max

    for _, element in ipairs(elements or {}) do
        local p = element:getPosition()
        if p then
            if not min then
                min = { x = p.x, y = p.y, z = p.z }
                max = { x = p.x, y = p.y, z = p.z }
            else
                min.x, min.y, min.z = math.min(min.x, p.x), math.min(min.y, p.y), math.min(min.z, p.z)
                max.x, max.y, max.z = math.max(max.x, p.x), math.max(max.y, p.y), math.max(max.z, p.z)
            end
        end
    end

    if not min then
        return nil
    end

    return {
        x = (min.x + max.x) * 0.5,
        y = (min.y + max.y) * 0.5,
        z = (min.z + max.z) * 0.5
    }
end

---Half extents around `center` covering each element's streaming range (capped at `rangeCap`), times `margin`.
---@param center {x: number, y: number, z: number}
---@param elements element[]
---@return {x: number, y: number, z: number}
function streamingBox.getAutoExtents(center, elements)
    local extent = { x = 0, y = 0, z = 0 }

    for _, element in ipairs(elements or {}) do
        local p = element:getPosition()
        if p then
            local range = math.max(0, math.min(tonumber(element.spawnable.primaryRange) or 0, streamingBox.rangeCap))
            extent.x = math.max(extent.x, math.abs(p.x - center.x) + range)
            extent.y = math.max(extent.y, math.abs(p.y - center.y) + range)
            extent.z = math.max(extent.z, math.abs(p.z - center.z) + range)
        end
    end

    return {
        x = math.max(streamingBox.minExtent, extent.x * streamingBox.margin),
        y = math.max(streamingBox.minExtent, extent.y * streamingBox.margin),
        z = math.max(streamingBox.minExtent, extent.z * streamingBox.margin)
    }
end

---Center and extents of the box to export for an export-list entry.
---@param group table Export-list entry (`streamingAuto`, `streamingX/Y/Z`).
---@param elements element[] Exported elements.
---@param fallbackCenter {x: number, y: number, z: number} Used when no element has a position.
---@return {x: number, y: number, z: number} center
---@return {x: number, y: number, z: number} extents
function streamingBox.resolve(group, elements, fallbackCenter)
    local center = streamingBox.getContentCenter(elements)
        or { x = fallbackCenter.x or 0, y = fallbackCenter.y or 0, z = fallbackCenter.z or 0 }

    if group.streamingAuto == true and #elements > 0 then
        return center, streamingBox.getAutoExtents(center, elements)
    end

    return center, {
        x = tonumber(group.streamingX) or 0,
        y = tonumber(group.streamingY) or 0,
        z = tonumber(group.streamingZ) or 0
    }
end

return streamingBox
