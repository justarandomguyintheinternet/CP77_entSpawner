local utils = require("modules/utils/utils")
local epsilon = 0.00001

local intersection = {}

--Very rough frustum check
local function isObjectInFrustum(cameraForward, cameraPosition, objectPosition, objectSize, maxFov)
    local angle = cameraForward:Dot(utils.subVector(objectPosition, cameraPosition))
    --angle must be less than maxFov scaled by object size
end

---Return a factor to be scaled with the objects BBox, hardcoded for special cases like AMM miniatures (Wrong mesh bbox) and foliage (Usually too big)
---@param path any
function intersection.getResourcePathScalingFactor(path, initalScale)
    if string.match(path, "base\\environment\\vegetation\\palms\\") or string.match(path, "yucca") then
        return Vector4.new(0.175, 0.175, 0.7, 0)
    end

    if string.match(path, "base\\environment\\vegetation\\") or string.match(path, "[^s]tree") then
        return Vector4.new(0.35, 0.35, 0.7, 0)
    end

    if path == "base\\amm_props\\mesh\\props\\shuttle.mesh" or path == "base\\amm_props\\mesh\\props\\shuttle_platform.mesh" then
        return Vector4.new(21 / 20000, 26 / 20000, 165 / 80000, 0)
    end

    if string.match(path, "\\fx\\") then
        return Vector4.new(0, 0, 0, 0)
    end

    local newScale = Vector4.new(1, 1, 1, 0)
    if initalScale.x > 0.1 then
        newScale.x = 0.9
    end
    if initalScale.y > 0.1 then
        newScale.y = 0.9
    end
    if initalScale.z > 0.1 then
        newScale.z = 0.9
    end

    return newScale
end

function intersection.BBoxInsideBBox(outerOrigin, outerRotation, outerBox, innerOrigin, innerRotation, innerBox)
    local min = utils.addVector(innerOrigin, innerRotation:ToQuat():Transform(ToVector4(innerBox.min)))
    local max = utils.addVector(innerOrigin, innerRotation:ToQuat():Transform(ToVector4(innerBox.max)))

    return intersection.pointInsideBox(min, outerOrigin, outerRotation, outerBox) and intersection.pointInsideBox(max, outerOrigin, outerRotation, outerBox)
end

function intersection.pointInsideBox(point, boxOrigin, boxRotation, box)
    local matrix = Matrix.BuiltRTS(boxRotation, boxOrigin, Vector4.new(1, 1, 1, 0))

    local delta = utils.subVector(point, boxOrigin)

    local axis = {
        ["x"] = matrix:GetAxisX(),
        ["y"] = matrix:GetAxisY(),
        ["z"] = matrix:GetAxisZ()
    }

    for axisName, axisDirection in pairs(axis) do
        local e = axisDirection:Dot(delta) -- Distance of ray origin to box origin along the box's x/y/z axis

        if e < box.min[axisName] or e > box.max[axisName] then
            return false
        end
    end

    return true
end

--https://github.com/opengl-tutorials/ogl/blob/master/misc05_picking/misc05_picking_custom.cpp
function intersection.getBoxIntersection(rayOrigin, ray, boxOrigin, boxRotation, box)
    local matrix = Matrix.BuiltRTS(boxRotation, boxOrigin, Vector4.new(1, 1, 1, 0))

    local tMin = 0
    local tMax = math.huge

    local delta = utils.subVector(boxOrigin, rayOrigin)

    local axis = {
        ["x"] = matrix:GetAxisX(),
        ["y"] = matrix:GetAxisY(),
        ["z"] = matrix:GetAxisZ()
    }

    for axisName, axisDirection in pairs(axis) do
        local e = axisDirection:Dot(delta) -- Distance of ray origin to box origin along the box's x/y/z axis
        local f = ray:Dot(axisDirection) -- Scale t value based on rotation of the box axis relative to ray, since shallower angle would mean bigger t

        if math.abs(f) > epsilon then
            local t1 = (e + box.min[axisName]) / f
            local t2 = (e + box.max[axisName]) / f

            if t1 > t2 then
                t1, t2 = t2, t1
            end

            if t2 < tMax then
                tMax = t2
            end

            if t1 > tMin then
                tMin = t1
            end

            if tMin > tMax then
                return { hit = false, position = Vector4.new(0, 0, 0, 0), distance = 0 }
            end
        elseif -e + box.min[axisName] > 0 or -e + box.max[axisName] < 0 then
            return { hit = false, position = Vector4.new(0, 0, 0, 0), distance = 0 }
        end
    end

    return { hit = true, position = utils.addVector(rayOrigin, utils.multVector(ray:Normalize(), tMin)), distance = tMin }
end

return intersection