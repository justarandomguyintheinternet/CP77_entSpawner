local utils = require("modules/utils/utils")
local red = {}

--GetMod("entSpawner").e(Game.GetTargetingSystem():GetLookAtObject(Game.GetPlayer(), false, false):FindComponentByName("spotlight_lightsource"))
--GetMod("entSpawner").e(Game.GetTargetingSystem():GetLookAtObject(Game.GetPlayer(), false, false):FindComponentByName("Collider8411"))
-- print(FromVariant(Reflection.GetClassOf(ToVariant(FixedPoint.new())):GetProperty("Bits"):GetValue(ToVariant(Game.GetTargetingSystem():GetLookAtObject(Game.GetPlayer(), false, false):FindComponentByName("spotlight_lightsource").localTransform.Position.z))))
--GetMod("entSpawner").e(entColliderComponent.new( { colliders = { physicsColliderBox.new() } } ))
-- print(propType, prop:GetType():GetName().value, " | Name: ", prop:GetName().value, " | Value: ", propValue, " | Class: ", class:GetName().value, " | Value directly ", data[prop:GetName().value])
--GetMod("entSpawner").e(Game.FindEntityByID(entEntityID.new({hash=12264210ULL})):FindComponentByName("Light2103"))

--- EXPORT

--TODO: TweakDBID strings

local exportExludes = {
    "appearancePath",
    "meshResource",
    "worldTransform",
    "appearanceName",
    "blackboard"
}

-- If this handle is nil, generate a new instance for it
local handleIncludes = {
    "journalPath"
}

local function convertCName(propValue)
    if propValue then
        return {
            ["$type"] = "CName",
            ["$storage"] = "string",
            ["$value"] = propValue.value
        }
    end
    return nil
end

local function convertFundamental(propValue, propClass)
    local propData = propValue
    if type(propValue) == "boolean" then
        propData = propValue and 1 or 0
    elseif propClass == "uint64" or propClass == "Uint64" then
        propData = tostring(propValue):gsub("ULL", "")
    end

    return propData
end

local function convertSimple(propValue, propClass, prop)
    local propData = tostring(propValue)

    if propClass == "LocalizationString" then
        propData = {
            ["unk1"] = "0",
            ["value"] = GameDump(propValue)
        }
    elseif propClass == "CRUID" then
        propData = tostring(CRUIDToHash(propValue)):gsub("ULL", "")
    elseif propClass == "TweakDBID" then
        if propValue then
            if propValue.value:match("<TDBID:") then
                local hash = propValue.value:match(":.*:"):gsub(":", "")
                local length = propValue.value:match(":..>"):gsub(":", ""):gsub(">", "")
                local hex = "0x" .. length .. hash

                propData = {
                    ["$type"] = "TweakDBID",
                    ["$storage"] = "uint64",
                    ["$value"] = tostring(tonumber(hex))
                }
            else
                propData = {
                    ["$type"] = "TweakDBID",
                    ["$storage"] = "string",
                    ["$value"] = propValue.value
                }
            end
        else
            propData = nil
        end
    elseif propClass == "NodeRef" then
        local hash = NodeRefToHash(propValue)
        if propValue then
            propData = {
                ["$type"] = "NodeRef",
                ["$storage"] = "uint64",
                ["$value"] = tostring(hash):gsub("ULL", "")
            }
        else
            propData = nil
        end
    elseif propClass == "String" then
        propData = propValue
    else
        utils.log(string.format("[%s] Unsupported simple type: %s", prop:GetName().value, propClass))
    end

    return propData
end

local function convertArray(propValue, prop)
    local propData = {}
    local innerType = prop:GetType():GetInnerType():GetMetaType()

    for _, entry in pairs(propValue) do
        local innerData = red.convertAny(innerType, prop:GetType():GetInnerType():GetName().value, entry, prop, propValue)

        table.insert(propData, innerData)
    end

    return propData
end

local function convertHandle(propValue, prop, name)
    if propValue == nil and utils.has_value(handleIncludes, name) then
        propValue = FromVariant(prop:GetType():GetInnerType():MakeInstance())
    end

    if propValue ~= nil then
        return {
            HandleId = "0",
            Data = red.redDataToJSON(propValue)
        }
    end

    return nil
end

local function convertResRef(data, key)
    local value = ""

    if data then
        value = ResourceHelper.GetReferencePath(data, key):ToString()
    end

    return {
        DepotPath = {
            ["$type"] = "ResourcePath",
            ["$storage"] = "string",
            ["$value"] = value
        },
        Flags = "Default"
    }
end

local function convertResRefAsync(propValue)
    local hash = propValue.hash

    local str = ""
    if hash then
        str = ResRef.FromHash(hash):ToString()
    end

    local storage = "string"

    if str == "" then
        storage = "uint64"
        str = tostring(hash):gsub("ULL", "")
    end

    return {
        DepotPath = {
            ["$type"] = "ResourcePath",
            ["$storage"] = storage,
            ["$value"] = str
        },
        Flags = "Default"
    }
end

---@private
---@param metaType ERTTIType
---@param propType string
---@param value ISerializable
---@param prop ReflectionProp
---@param data ISerializable Parent of value
function red.convertAny(metaType, propType, value, prop, data)
    local propData = nil

    if metaType == ERTTIType.Name then
        propData = convertCName(value)
    elseif metaType == ERTTIType.Fundamental then
        propData = convertFundamental(value, propType)
    elseif metaType == ERTTIType.Class then
        propData = red.redDataToJSON(value)
    elseif metaType == ERTTIType.Simple then -- LocalizationString, Buffers, CRUID
        propData = convertSimple(value, propType, prop)
    elseif metaType == ERTTIType.Enum then
        propData = value.value
    elseif metaType == ERTTIType.Array or metaType == ERTTIType.StaticArray or metaType == ERTTIType.NativeArray or metaType == ERTTIType.FixedArray then
        propData = convertArray(value, prop)
    elseif metaType == ERTTIType.Handle or metaType == ERTTIType.WeakHandle then
        propData = convertHandle(value, prop, prop:GetName().value)
    elseif metaType == ERTTIType.ResourceReference then
        propData = convertResRef(data, prop:GetName().value)
    elseif metaType == ERTTIType.ResourceAsyncReference then
        propData = convertResRefAsync(value)
    else
        utils.log(string.format("[%s] Unsupported type: %s", prop:GetName().value, metaType))
    end

    return propData
end

---Converts a ISerializable instance to json data
---@param data ISerializable
---@return table
function red.redDataToJSON(data)
    local root

    pcall(function ()
       root = Reflection.GetClassOf(ToVariant(data), true)
    end)

    if not root then return nil end

    local converted = {
        ["$type"] = root:GetName().value
    }

    local classes = {root}
    while root:GetParent() do
        root = root:GetParent()
        table.insert(classes, root)
    end

    for _, class in pairs(classes) do
        for _, prop in pairs(class:GetProperties()) do
            local propData = nil
            local metaType = prop:GetType():GetMetaType()
            local propType = prop:GetType():GetName().value
            local value = FromVariant(prop:GetValue(ToVariant(data)))

            if not utils.has_value(exportExludes, prop:GetName().value) then
                propData = red.convertAny(metaType, propType, value, prop, data)
            end

            if propData then
                converted[prop:GetName().value] = propData
            end
        end
    end

    return converted
end

--- IMPORT

-- GetMod("entSpawner").i(entColliderComponent.new())
-- GetMod("entSpawner").i(Color.new())

local function importCName(value)
    CName.add(value["$value"])
    return value["$value"]
end

local function importFundamental(value, propType)
    local propData = nil

    if propType == "Bool" then
        propData = value == 1
    elseif propType == "uint64" or propType == "Uint64" then
        propData = loadstring("return " .. value .. "ULL", "")()
    else
        local succ = pcall(function()
            propData = value
        end)
        if not succ then
            propData = value
        end
    end

    return propData
end

local function importSimple(value, propType)
    local propData = nil

    if propType == "LocalizationString" then
        propData = ToLocalizationString(value["value"])
    elseif propType == "CRUID" then
        propData = CreateCRUID(loadstring("return " .. value .. "ULL", "")())
    elseif propType == "TweakDBID" then
        propData = TweakDBID.new(value["$value"])
    elseif propType == "NodeRef" then
        propData = HashToNodeRef(loadstring("return " .. value["$value"] .. "ULL", "")())
    end

    return propData
end

local function importClass(value, propType)
    local propData = nil

    if propType == "Vector3" then
        propData = Vector3.new(value.X, value.Y, value.Z)
    elseif propType == "Vector4" then
        propData = Vector4.new(value.X, value.Y, value.Z, 0)
    elseif propType == "WorldPosition" then
        local pos = WorldPosition.new()
        pos:SetVector4(Vector4.new(value.x.Bits / 131072, value.y.Bits / 131072, value.z.Bits / 131072))
        propData = pos
    else
        propData = NewObject(propType)
        red.JSONToRedData(value, propData)
    end

    return propData
end

local function importEnum(value, propType, enumName)
    local propData = nil

    for _, enum in pairs(Reflection.GetTypeOf(ToVariant(Enum.new(propType, 0))):GetConstants()) do
        if enum:GetName().value == value then
            propData = Enum.new(enumName, tonumber(enum:GetValue()))
            break
        end
    end

    return propData
end

local function importArray(value, data, key, prop)
    local propData = {}

    for index, entry in pairs(value) do
        local innerType = prop:GetType():GetInnerType()

        if type(entry) == "table" and entry.HandleId then
            entry = entry.Data
            innerType = innerType:GetInnerType()
        end

        local entryInstance
        if innerType:GetMetaType() == ERTTIType.Class then
            entryInstance = data[key][index] or NewObject(entry["$type"])
        end

        local propType = type(entry) == "table" and entry["$type"] or nil

        if not propType then
            propType = innerType:GetName().value
        end

        local entryData = red.importAny(innerType:GetMetaType(), propType, entry, nil, entryInstance, index)

        table.insert(propData, entryData)
    end

    return propData
end

local function importHandle(value, data, key)
    local propData = data[key] or NewObject(value.Data["$type"])
    red.JSONToRedData(value.Data, propData)
    return propData
end

local function importResourceRef(data, value, key)
    ResourceHelper.LoadReferenceResource(data, key, value["DepotPath"]["$value"], true)
end

local function importResourceRefAsync(value)
    if value["DepotPath"]["$storage"] == "string" then
        return ResRef.FromString(value["DepotPath"]["$value"])
    else
        return ResRef.FromHash(loadstring("return " .. value["DepotPath"]["$value"] .. "ULL", "")())
    end
end

---@private
---@param metaType ERTTIType
---@param propType string
---@param value table
---@param prop ReflectionProp
---@param data ISerializable Parent of value
---@param key string
---@return any
function red.importAny(metaType, propType, value, prop, data, key)
    local propData = nil

    if metaType == ERTTIType.Name then
        propData = importCName(value)
    elseif metaType == ERTTIType.Fundamental then
        propData = importFundamental(value, propType)
    elseif metaType == ERTTIType.Simple then
        propData = importSimple(value, propType)
    elseif metaType == ERTTIType.Class then
        propData = importClass(value, propType)
    elseif metaType == ERTTIType.Enum then
        propData = importEnum(value, propType, propType)
    elseif metaType == ERTTIType.Array or metaType == ERTTIType.StaticArray or metaType == ERTTIType.NativeArray or metaType == ERTTIType.FixedArray then
        propData = importArray(value, data, key, prop)
    elseif metaType == ERTTIType.Handle or metaType == ERTTIType.WeakHandle then
        propData = importHandle(value, data, key)
    elseif metaType == ERTTIType.ResourceReference then
        propData = importResourceRef(data, value, key)
    elseif metaType == ERTTIType.ResourceAsyncReference then
        propData = importResourceRefAsync(value)
    else
        utils.log("Unsupported type: ", metaType)
    end

    return propData
end

function red.JSONToRedData(json, data)
    json["$type"] = nil

    for key, value in pairs(json) do
        local prop = Reflection.GetClassOf(ToVariant(data), true):GetProperty(key)
        local propType = prop:GetType():GetName().value
        local metaType = prop:GetType():GetMetaType()

        local propData = red.importAny(metaType, propType, value, prop, data, key)

        if propData then
            data[key] = propData
        end
    end
end

return red