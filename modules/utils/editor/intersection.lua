local utils = require("modules/utils/utils")
local epsilon = 0.00001

local intersection = {}

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

    print(ray)

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