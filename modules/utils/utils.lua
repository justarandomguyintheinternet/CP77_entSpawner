miscUtils = {}

---@param origin table
---@return table
function miscUtils.deepcopy(origin)
	local orig_type = type(origin)
    local copy
    if orig_type == 'table' then
        copy = {}
        for origin_key, origin_value in next, origin, nil do
            copy[miscUtils.deepcopy(origin_key)] = miscUtils.deepcopy(origin_value)
        end
        setmetatable(copy, miscUtils.deepcopy(getmetatable(origin)))
    else
        copy = origin
    end
    return copy
end

---Returns the index of a value in a table, if not found -1
---@param table table
---@param value any
---@return integer
function miscUtils.indexValue(table, value)
    local index={}
    for k,v in pairs(table) do
        index[v]=k
    end
    return index[value] or -1
end

---@param tab table
---@param val any
---@return boolean
function miscUtils.has_value(tab, val)
    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end

---@param tab table
---@param index any
---@return boolean
function miscUtils.hasIndex(tab, index)
    for k, _ in pairs(tab) do
        if k == index then
            return true
        end
    end
    return false
end

function miscUtils.tableLength(table)
    local count = 0
    for _ in pairs(table) do count = count + 1 end
    return count
end

---@param tab table
---@param val any
function miscUtils.removeItem(tab, val)
    table.remove(tab, miscUtils.indexValue(tab, val))
end

function miscUtils.addVector(v1, v2)
    return Vector4.new(v1.x + v2.x, v1.y + v2.y, v1.z + v2.z, v1.w + v2.w)
end

function miscUtils.subVector(v1, v2)
    return Vector4.new(v1.x - v2.x, v1.y - v2.y, v1.z - v2.z, v1.w - v2.w)
end

function miscUtils.multVector(v1, factor)
    return Vector4.new(v1.x * factor, v1.y * factor, v1.z * factor, v1.w * factor)
end

function miscUtils.multVecXVec(v1, v2)
    return Vector4.new(v1.x * v2.x, v1.y * v2.y, v1.z * v2.z, v1.w * v2.w)
end

function miscUtils.addEuler(e1, e2)
    return EulerAngles.new(e1.roll + e2.roll, e1.pitch + e2.pitch, e1.yaw + e2.yaw)
end

function miscUtils.subEuler(e1, e2)
    return EulerAngles.new(e1.roll - e2.roll, e1.pitch - e2.pitch, e1.yaw - e2.yaw)
end

function miscUtils.multEuler(e1, factor)
    return EulerAngles.new(e1.roll * factor, e1.pitch * factor, e1.yaw * factor)
end

---Returns table with x y z w from given Vector4
---@param vector Vector4
---@return table {x, y, z, w}
function miscUtils.fromVector(vector)
    return {x = vector.x, y = vector.y, z = vector.z, w = vector.w}
end

---Returns table with i j k r from given Quaternion
---@param quat Quaternion
---@return table {i, j, k, r}
function miscUtils.fromQuaternion(quat)
    return {i = quat.i, j = quat.j, k = quat.k, r = quat.r}
end

---Returns Vector4 object from given table containing x y z w
---@param tab table {x, y, z, w}
---@return Vector4
function miscUtils.getVector(tab)
    return(Vector4.new(tab.x, tab.y, tab.z, tab.w))
end

---Returns Quaternion object from given table containing i j k r
---@param tab table {i, j, k, r}
---@return Quaternion
function miscUtils.getQuaternion(tab)
    return(Quaternion.new(tab.i, tab.j, tab.k, tab.r))
end

---Returns table with roll pitch yaw from given EulerAngles
---@param eul EulerAngles
---@return table {roll, pitch, yaw}
function miscUtils.fromEuler(eul)
    return {roll = eul.roll, pitch = eul.pitch, yaw = eul.yaw}
end

---Returns EulerAngles object from given table containing roll pitch yaw
---@param tab table {roll, pitch, yaw}
---@return EulerAngles
function miscUtils.getEuler(tab)
    return(EulerAngles.new(tab.roll, tab.pitch, tab.yaw))
end

function miscUtils.distanceVector(from, to)
    return math.sqrt((to.x - from.x)^2 + (to.y - from.y)^2 + (to.z - from.z)^2)
end

---Sanitizes a string to be used as a file name
---@param name string
---@return string
function miscUtils.createFileName(name)
    name = name:gsub("<", "_")
    name = name:gsub(">", "_")
    name = name:gsub(":", "_")
    name = name:gsub("\"", "_")
    name = name:gsub("/", "_")
    name = name:gsub("\\", "_")
    name = name:gsub("|", "_")
    name = name:gsub("?", "_")
    name = name:gsub("*", "_")

    return name
end

function miscUtils.rotateRoll(vec, deg)
    local deg = math.rad(deg)

    local row1 = Vector3.new(1, 0, 0)
    local row2 = Vector3.new(0, math.cos(deg), -math.sin(deg))
    local row3 = Vector3.new(0, math.sin(deg), math.cos(deg))

    local rotated = Vector4.new(0, 0, 0, 0)

    rotated.x = row1.x * vec.x + row1.y * vec.y + row1.z * vec.z
    rotated.y = row2.x * vec.x + row2.y * vec.y + row2.z * vec.z
    rotated.z = row3.x * vec.x + row3.y * vec.y + row3.z * vec.z

    return rotated
end

function miscUtils.rotatePitch(vec, deg)
    local deg = math.rad(deg)

    local row1 = Vector3.new(math.cos(deg), 0, math.sin(deg))
    local row2 = Vector3.new(0, 1, 0)
    local row3 = Vector3.new(-math.sin(deg), 0, math.cos(deg))

    local rotated = Vector4.new(0, 0, 0, 0)

    rotated.x = row1.x * vec.x + row1.y * vec.y + row1.z * vec.z
    rotated.y = row2.x * vec.x + row2.y * vec.y + row2.z * vec.z
    rotated.z = row3.x * vec.x + row3.y * vec.y + row3.z * vec.z

    return rotated
end

function miscUtils.rotatePoint(vec, rot)
    local yaw = math.rad(rot.yaw) -- α
    local pitch = math.rad(rot.pitch) -- β
    local roll = math.rad(rot.roll) -- γ

    local r1_1 = math.cos(yaw) * math.cos(pitch)
    local r1_2 = (math.cos(yaw) * math.sin(pitch) * math.sin(roll)) - (math.sin(yaw) * math.cos(roll))
    local r1_3 = (math.cos(yaw) * math.sin(pitch) * math.cos(roll)) + (math.sin(yaw) * math.sin(roll))

    local r2_1 = math.sin(yaw) * math.cos(pitch)
    local r2_2 = (math.sin(yaw) * math.sin(pitch) * math.sin(roll)) + (math.cos(yaw) * math.cos(roll))
    local r2_3 = (math.sin(yaw) * math.sin(pitch) * math.cos(roll)) - (math.cos(yaw) * math.sin(roll))

    local r3_1 = -math.sin(pitch)
    local r3_2 = math.cos(pitch) * math.sin(roll)
    local r3_3 = math.cos(pitch) * math.cos(roll)

    local row1 = Vector3.new(r1_1, r1_2, r1_3)
    local row2 = Vector3.new(r2_1, r2_2, r2_3)
    local row3 = Vector3.new(r3_1, r3_2, r3_3)

    local rotated = Vector4.new(0, 0, 0, 0)

    rotated.x = row1.x * vec.x + row1.y * vec.y + row1.z * vec.z
    rotated.y = row2.x * vec.x + row2.y * vec.y + row2.z * vec.z
    rotated.z = row3.x * vec.x + row3.y * vec.y + row3.z * vec.z

    return rotated
end

---Returns the min and max of a BBox for a list of Vector4's
---@param vectors table
---@return Vector4, Vector4
function miscUtils.getVector4BBox(vectors)
    local minX = 9999999999
    local minY = 9999999999
    local minZ = 9999999999
    local maxX = -9999999999
    local maxY = -9999999999
    local maxZ = -9999999999

    for _, vector in ipairs(vectors) do
        if vector.x < minX then
            minX = vector.x
        end
        if vector.y < minY then
            minY = vector.y
        end
        if vector.z < minZ then
            minZ = vector.z
        end
        if vector.x > maxX then
            maxX = vector.x
        end
        if vector.y > maxY then
            maxY = vector.y
        end
        if vector.z > maxZ then
            maxZ = vector.z
        end
    end

    return Vector4.new(minX, minY, minZ, 0), Vector4.new(maxX, maxY, maxZ, 0)
end

function miscUtils.addEulerRelative(current, delta)
    local result = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](current:ToQuat(), Quaternion.SetAxisAngle(Vector4.new(0, 1, 0, 0), Deg2Rad(delta.roll)))
    result = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](result, Quaternion.SetAxisAngle(Vector4.new(1, 0, 0, 0), Deg2Rad(delta.pitch)))
    result = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](result, Quaternion.SetAxisAngle(Vector4.new(0, 0, 1, 0), Deg2Rad(delta.yaw)))

    return result:ToEulerAngles()
end

---@param enumName string
---@return table
function miscUtils.enumTable(enumName)
    local enums = {}

    for i = 0, tonumber(EnumGetMax(enumName)) do
        table.insert(enums, EnumValueToString(enumName, i))
    end

    return enums
end

function miscUtils.generateCopyName(name)
    local num = name:match("%d*$")

    if #num ~= 0 then
        return name:sub(1, -#num - 1) .. tostring(tonumber(num) + 1)
    else
        return name .. "_1"
    end
end

function miscUtils.log(...)
    if false then return end

    local args = {...}
    local str = ""

    for i, arg in ipairs(args) do
        str = str .. tostring(arg)
        if i < #args then
            str = str .. "\t"
        end
    end

    print(str)
end

function miscUtils.getFileName(path)
    return path:match("[^/\\]+$")
end

function miscUtils.combine(target, data)
    for _, v in pairs(data) do
        table.insert(target, v)
    end

    return target
end

function miscUtils.isA(object, class)
    return miscUtils.has_value(object.class, class)
end

function miscUtils.setNestedValue(tbl, keys, data)
    local value = tbl
    for i, key in ipairs(keys) do
        if i == #keys then
            value[key] = data
            return
        else
            value = value[key]
        end
    end
end

function miscUtils.getNestedValue(tbl, keys)
    local value = tbl
    for _, key in ipairs(keys) do
        if value[key] == nil then
            return nil
        end
        value = value[key]
    end
    return value
end

return miscUtils