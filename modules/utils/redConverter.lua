local utils = require("modules/utils/utils")
local red = {}

--GetMod("entSpawner").e(Game.GetTargetingSystem():GetLookAtObject(Game.GetPlayer(), false, false):FindComponentByName("spotlight_lightsource"))
--GetMod("entSpawner").e(Game.GetTargetingSystem():GetLookAtObject(Game.GetPlayer(), false, false):FindComponentByName("Collider8411"))
-- print(FromVariant(Reflection.GetClassOf(ToVariant(FixedPoint.new())):GetProperty("Bits"):GetValue(ToVariant(Game.GetTargetingSystem():GetLookAtObject(Game.GetPlayer(), false, false):FindComponentByName("spotlight_lightsource").localTransform.Position.z))))
--GetMod("entSpawner").e(entColliderComponent.new( { colliders = { physicsColliderBox.new() } } ))
-- print(propType, prop:GetType():GetName().value, " | Name: ", prop:GetName().value, " | Value: ", propValue, " | Class: ", class:GetName().value, " | Value directly ", data[prop:GetName().value])
--GetMod("entSpawner").e(Game.FindEntityByID(entEntityID.new({hash=12264210ULL})):FindComponentByName("Light2103"))

--- EXPORT

local exportExludes = {
    "appearancePath",
    "meshResource",
    "worldTransform",
    "appearanceName"
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
    elseif propClass == "Uint64" then
        propData = tostring(propValue):gsub("ULL", "")
    end

    return propData
end

local function convertSimple(propValue, propClass)
    local propData = tostring(propValue)

    if propClass == "LocalizationString" then
        propData = GameDump(propValue)
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
        if propValue and tostring(hash) ~= "0ULL" then
            propData = {
                ["$type"] = "NodeRef",
                ["$storage"] = "Uint64",
                ["$value"] = tostring(hash):gsub("ULL", "")
            }
        else
            propData = nil
        end
    else
        utils.log("Unsupported simple type: ", propClass)
    end

    return propData
end

local function convertArray(propValue, prop)
    local propData = {}
    local innerType = prop:GetType():GetInnerType():GetMetaType()

    for _, entry in pairs(propValue) do
        local innerData = red.redDataToJSON(entry)

        if innerType == ERTTIType.Handle or innerType == ERTTIType.WeakHandle then
            table.insert(propData, {
                HandleId = "0",
                Data = innerData
            })
        else
            table.insert(propData, innerData)
        end
    end

    return propData
end

local function convertHandle(propValue)
    if propValue ~= nil then
        return {
            HandleId = "0",
            Data = red.redDataToJSON(propValue)
        }
    end

    return nil
end

local function convertResRef(propValue)
    local hash = propValue.hash

    local string = ""
    if hash then
        string = ResRef.FromHash(hash):ToString()
    end

    if string ~= "" then
        return {
            DepotPath = {
                ["$type"] = "ResourcePath",
                ["$storage"] = "string",
                ["$value"] = string
            },
            Flags = "Default"
        }
    end

    return nil
end

function red.redDataToJSON(data)
    local root = Reflection.GetClassOf(ToVariant(data), true)

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
            local propType = prop:GetType():GetMetaType()
            local propData = nil
            local propValue = FromVariant(prop:GetValue(ToVariant(data)))
            local propClass = prop:GetType():GetName().value

            if not utils.has_value(exportExludes, prop:GetName().value) then
                if propType == ERTTIType.Name then
                    propData = convertCName(propValue)
                elseif propType == ERTTIType.Fundamental then
                    propData = convertFundamental(propValue, propClass)
                elseif propType == ERTTIType.Class then
                    propData = red.redDataToJSON(propValue)
                elseif propType == ERTTIType.Simple then -- LocalizationString, Buffers, CRUID
                    propData = convertSimple(propValue, propClass)
                elseif propType == ERTTIType.Enum then
                    propData = tostring(propValue):match(":%s*(.+)%s")
                elseif propType == ERTTIType.Array or propType == ERTTIType.StaticArray or propType == ERTTIType.NativeArray or propType == ERTTIType.FixedArray then
                    propData = convertArray(propValue, prop)
                elseif propType == ERTTIType.Handle or propType == ERTTIType.WeakHandle then
                    propData = convertHandle(propValue)
                elseif propType == ERTTIType.ResourceReference or propType == ERTTIType.ResourceAsyncReference then
                    propData = convertResRef(propValue)
                else
                    utils.log("Unsupported type: ", propType)
                end
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
    elseif propType == "Uint64" then
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
        propData = value
    elseif propType == "CRUID" then
        propData = CreateCRUID(loadstring("return " .. value .. "ULL", "")())
    elseif propType == "TweakDBID" then
        propData = TweakDBID.new(value["$value"])
    elseif propType == "NodeRef" then
        propData = HashToNodeRef(loadstring("return " .. value .. "ULL", "")())
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

local function importEnum(value, propType, prop)
    local propData = nil

    for _, enum in pairs(Reflection.GetTypeOf(ToVariant(Enum.new(propType, 0))):GetConstants()) do
        if enum:GetName().value == value then
            propData = Enum.new(prop:GetType():GetName().value, tonumber(enum:GetValue()))
            break
        end
    end

    return propData
end

local function importArray(value, data, key)
    local propData = {}

    for index, entry in pairs(value) do
        if entry.HandleId then
            entry = entry.Data
        end
        local entryData = data[key][index] or NewObject(entry["$type"])
        red.JSONToRedData(entry, entryData)
        table.insert(propData, entryData)
    end

    return propData
end

local function importHandle(value, data, key)
    local propData = data[key] or NewObject(value.Data["$type"])
    red.JSONToRedData(value.Data, propData)
    return propData
end

local function importResource(value)
    if value["DepotPath"]["$storage"] == "string" then
        return ResRef.FromString(value["DepotPath"]["$value"])
    else
        return ResRef.FromHash(loadstring("return " .. value["DepotPath"]["$value"] .. "ULL", "")())
    end
end

function red.JSONToRedData(json, data)
    json["$type"] = nil

    for key, value in pairs(json) do
        local prop = Reflection.GetClassOf(ToVariant(data), true):GetProperty(key)
        local propType = prop:GetType():GetName().value
        local metaType = prop:GetType():GetMetaType()

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
            propData = importEnum(value, propType, prop)
        elseif metaType == ERTTIType.Array or metaType == ERTTIType.StaticArray or metaType == ERTTIType.NativeArray or metaType == ERTTIType.FixedArray then
            propData = importArray(value, data, key)
        elseif metaType == ERTTIType.Handle or metaType == ERTTIType.WeakHandle then
            propData = importHandle(value, data, key)
        elseif metaType == ERTTIType.ResourceReference or metaType == ERTTIType.ResourceAsyncReference then
            propData = importResource(value)
        else
            utils.log("Unsupported type: ", metaType)
        end

        if propData then
            data[key] = propData
        end
    end
end

return red