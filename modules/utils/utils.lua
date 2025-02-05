miscUtils = {
    data = {}
}

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
    name = name:gsub("'", "_")
    name = name:gsub(" ", "_")

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

    if #vectors == 0 then
        return Vector4.new(0, 0, 0, 0), Vector4.new(0, 0, 0, 0)
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

    for i = -25, tonumber(EnumGetMax(enumName)) do
        local name = EnumValueToString(enumName, i)
        if name ~= "" then
            table.insert(enums, name)
        end
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
    if string.match(path, "\\") then -- Workaround to avoid stripping records
        return path:match("([^/\\]+)%..*$") or path
    end

    return path
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

--https://web.archive.org/web/20131225070434/http://snippets.luacode.org/snippets/Deep_Comparison_of_Two_Values_3
function miscUtils.deepcompare(t1,t2,ignore_mt)
    local ty1 = type(t1)
    local ty2 = type(t2)
    if ty1 ~= ty2 then return false end
    -- non-table types can be directly compared
    if ty1 ~= 'table' and ty2 ~= 'table' then return t1 == t2 end
    -- as well as tables which have the metamethod __eq
    local mt = getmetatable(t1)
    if not ignore_mt and mt and mt.__eq then return t1 == t2 end
    for k1,v1 in pairs(t1) do
        local v2 = t2[k1]
        if v2 == nil or not miscUtils.deepcompare(v1,v2) then return false end
    end
    for k2,v2 in pairs(t2) do
        local v1 = t1[k2]
        if v1 == nil or not miscUtils.deepcompare(v1,v2) then return false end
    end
    return true
end

function miscUtils.sendOutlineEvent(entity, color)
    entity:QueueEvent(entRenderHighlightEvent.new({
        seeThroughWalls = true,
        outlineIndex = color,
        opacity = 1
    }))
end

function miscUtils.getTextMaxWidth(texts)
    local max = 0

    for _, text in ipairs(texts) do
        local x, _ = ImGui.CalcTextSize(text)
        max = math.max(max, x)
    end

    return max
end

function miscUtils.getDerivedClasses(base)
    local classes = { base }

    for _, derived in pairs(Reflection.GetDerivedClasses(base)) do
        if derived:GetName().value ~= base then
            for _, class in pairs(miscUtils.getDerivedClasses(derived:GetName().value)) do
                table.insert(classes, class)
            end
        end
    end

    return classes
end

function miscUtils.nodeRefStringToHashString(data)
    local hash, _ = data:gsub("#", "")
    hash, _ = tostring(FNV1a64(hash)):gsub("ULL", "")

    return hash
end

function miscUtils.insertClipboardValue(key, data)
    miscUtils.data[key] = data
end

function miscUtils.getClipboardValue(key)
    return miscUtils.data[key]
end

--https://stackoverflow.com/questions/18886447/convert-signed-ieee-754-float-to-hexadecimal-representation
--https://stackoverflow.com/questions/72783502/how-does-one-reverse-the-items-in-a-table-in-lua
function miscUtils.floatToHex(n)
    if n == 0.0 then return "00000000" end

    local sign = 0
    if n < 0.0 then
        sign = 0x80
        n = -n
    end

    local mant, expo = math.frexp(n)
    local hext = {}

    if mant ~= mant then
        hext[#hext+1] = string.char(0xFF, 0x88, 0x00, 0x00)

    elseif mant == math.huge or expo > 0x80 then
        if sign == 0 then
            hext[#hext+1] = string.char(0x7F, 0x80, 0x00, 0x00)
        else
            hext[#hext+1] = string.char(0xFF, 0x80, 0x00, 0x00)
        end

    elseif (mant == 0.0 and expo == 0) or expo < -0x7E then
        hext[#hext+1] = string.char(sign, 0x00, 0x00, 0x00)

    else
        expo = expo + 0x7E
        mant = (mant * 2.0 - 1.0) * math.ldexp(0.5, 24)
        hext[#hext+1] = string.char(sign + math.floor(expo / 0x2),
                                    (expo % 0x2) * 0x80 + math.floor(mant / 0x10000),
                                    math.floor(mant / 0x100) % 0x100,
                                    mant % 0x100)
    end

    local str = string.gsub(table.concat(hext),"(.)", function (c) return string.format("%02X%s",string.byte(c),"") end)
    local reversed = ""

    for i = 1, #str, 2 do
        reversed = str:sub(i, i + 1) .. reversed
    end

    if #reversed < 8 then
        reversed = reversed .. string.rep("0", 8 - #reversed)
    end

    return reversed
end

--https://stackoverflow.com/questions/18886447/convert-signed-ieee-754-float-to-hexadecimal-representation
function miscUtils.intToHex(IN)
    local B,K,OUT,I,D=16,"0123456789ABCDEF","",0
    while IN>0 do
        I=I+1
        IN,D=math.floor(IN/B),(IN % B)+1
        OUT=string.sub(K,D,D)..OUT
    end

    if OUT == "" then
        OUT = "00"
    end

    if #OUT == 1 then
        OUT = "0" .. OUT
    end

    return OUT
end

function miscUtils.hexToBase64(hex)
    -- Convert hex string to binary data
    local binary = hex:gsub('..', function(byte)
        return string.char(tonumber(byte, 16))
    end)

    -- Base64 character set
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local b64 = {}
    local padding = #binary % 3 -- Determine the padding needed

    -- Encode binary to base64 without bitwise operations
    local function toBase64Index(bytes)
        local a = bytes[1] or 0
        local b = bytes[2] or 0
        local c = bytes[3] or 0

        -- Calculate the base64 indices manually
        local i1 = math.floor(a / 4)
        local i2 = (a % 4) * 16 + math.floor(b / 16)
        local i3 = (b % 16) * 4 + math.floor(c / 64)
        local i4 = c % 64

        return {i1, i2, i3, i4}
    end

    for i = 1, #binary, 3 do
        local bytes = {binary:byte(i, i + 2)}
        local indices = toBase64Index(bytes)

        for j = 1, 4 do
            table.insert(b64, b64chars:sub(indices[j] + 1, indices[j] + 1))
        end
    end

    -- Add padding if needed
    for _ = 1, (3 - padding) % 3 do
        b64[#b64] = '='
    end

    return table.concat(b64)
end

function miscUtils.getKeys(tab)
    local keys = {}

    for k, _ in pairs(tab) do
        table.insert(keys, k)
    end

    return keys
end

function miscUtils.shortenPath(path, width, backwardsSlash)
    if ImGui.CalcTextSize(path) <= width then return path end

    local pattern = backwardsSlash and "^\\?[^\\]*" or "^%/?[^%/]*"
    local dotsWidth = ImGui.CalcTextSize("...")
    while ImGui.CalcTextSize(path) + dotsWidth > width do
        local stripped = path:gsub(pattern, "")
        if #stripped == 0 then
            break
        end
        path = stripped
    end

    while ImGui.CalcTextSize(path) + dotsWidth > width and #path > 0 do
        path = path:sub(2, #path)
    end

    return "..." .. path
end

return miscUtils