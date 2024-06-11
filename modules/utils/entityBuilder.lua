local cache = require("modules/utils/cache")
local utils = require("modules/utils/utils")

local builder = {
    callbacks = {}
}

local listener

function builder.hook()
    listener = NewProxy({
            OnEntityAssemble = {
                args = {'handle:EntityLifecycleEvent'},
                callback = function (event)
                    local entity = event:GetEntity()
                    local idHash = entity:GetEntityID().hash

                    if builder.callbacks[tonumber(idHash)] then
                        builder.callbacks[tonumber(idHash)](entity)
                        builder.callbacks[tonumber(idHash)] = nil
                    end
                end
            },
            OnResourceReady = {
                args = {'handle:ResourceToken'},
                callback = function(token)
                    if not token then return end
                    if token:IsFailed() or not token:IsFinished() then return end

                    if builder.callbacks[tonumber(token:GetHash())] then
                        builder.callbacks[tonumber(token:GetHash())](token:GetResource())
                        builder.callbacks[tonumber(token:GetHash())] = nil
                    end
                end
            }
        })
    Game.GetCallbackSystem():RegisterCallback('Entity/Initialize', listener:Target(), listener:Function('OnEntityAssemble'), true)
end

---Register a callback to be called when the entity with the specified entEntityID is assembled
---@param entityID entEntityID
---@param callback function Gets the entity passed as an argument
function builder.registerAssembleCallback(entityID, callback)
    builder.callbacks[tonumber(entityID.hash)] = callback
end

---Loads the specified resource and calls the callback when it is ready
---@param path string
---@param callback function Gets the resource passed as an argument
function builder.registerLoadResource(path, callback)
    local token = Game.GetResourceDepot():LoadResource(path)

    if not token:IsFailed() then
        builder.callbacks[tonumber(token:GetHash())] = callback
        token:RegisterCallback(listener:Target(), listener:Function('OnResourceReady'))
    end
end

---Recursively gets the real offset of a component
---@param component entIComponent
---@param components table
---@param offset WorldTransform
---@param slotName string
local function getComponentOffset(component, components, offset, slotName)
    print("Finding offset for " .. component.name.value, slotName)
    --- Add localTransform offset
    local pos = offset:GetWorldPosition()
    print(pos:ToVector4(), "pos b4 rotation")
    pos:SetVector4(offset:GetOrientation():Transform(pos:ToVector4()))
    print(pos:ToVector4(), "pos after rotation")
    pos = Game['OperatorAdd;WorldPositionWorldPosition;WorldPosition'](pos, component.localTransform:GetWorldPosition())
    print(pos:ToVector4(), "pos after addition")

    local rot = offset:GetOrientation()
    rot = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](rot, component.localTransform:GetOrientation())

    --- Add slot specifc offset
    if component:IsA("entSlotComponent") then
        local _, slot = component:GetSlotTransform(slotName)
        if slot then
            print("Slot Position:", slot:GetWorldPosition():ToVector4())
            pos:SetVector4(slot:GetOrientation():Transform(pos:ToVector4()))
            print(pos:ToVector4(), "pos after rotation of slot transform")
            pos = Game['OperatorAdd;WorldPositionWorldPosition;WorldPosition'](pos, slot:GetWorldPosition())
            print(pos:ToVector4(), "pos after addition of slot transform")
            rot = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](rot, slot:GetOrientation())
        end
    end

    offset:SetWorldPosition(pos)
    offset:SetOrientation(rot)

    if component.parentTransform then
        print(component.name.value .. " has parent ", component.parentTransform.bindName.value)
        local bindName = component.parentTransform.bindName.value
        if bindName == "" then
            return offset
        end

        for _, c in pairs(components) do
            if c.name.value == bindName then
                if component.parentTransform.slotName.value ~= "None" then
                    _, a = c:GetSlotTransform(component.parentTransform.slotName.value)
                print(a:GetWorldPosition():ToVector4(), "slot global pos")
                end
                return getComponentOffset(c, components, offset, component.parentTransform.slotName.value)
            end
        end
    end

    return offset
end

function builder.getEntityBBox(entity, callback)
    local components = entity:GetComponents()
    local meshes = {}
    local bBoxPoints = {}
    local meshesToLoad = 0
    local componentsChecked = 0

    for _, component in ipairs(components) do
        if (component:IsA("entMeshComponent") or component:IsA("entSkinnedMeshComponent")) and not (ResRef.FromHash(component.mesh.hash):ToString():match("base\\spawner")) then
            local offset = WorldTransform.new()
            offset = getComponentOffset(component, components, offset, "")

            meshesToLoad = meshesToLoad + 1
            builder.registerLoadResource(ResRef.FromHash(component.mesh.hash):ToString(), function(resource)
                local min = resource.boundingBox.Min
                local max = resource.boundingBox.Max

                table.insert(meshes, {
                    min = min,
                    max = max,
                    pos = offset:GetWorldPosition():ToVector4(),
                    rot = offset:GetOrientation():ToEulerAngles(),
                    path = ResRef.FromHash(component.mesh.hash):ToString(),
                    app = component.meshAppearance.value
                })

                table.insert(bBoxPoints, offset:GetOrientation():Transform(min))
                table.insert(bBoxPoints, offset:GetOrientation():Transform(max))

                meshesToLoad = meshesToLoad - 1
                if meshesToLoad == 0 and componentsChecked == #components then
                    local bboxMin, bboxMax = utils.getVector4BBox(bBoxPoints)
                    callback({ bBox = { min = bboxMin, max = bboxMax }, meshes = meshes })
                end
            end)
        end
        componentsChecked = componentsChecked + 1
    end

    if meshesToLoad == 0 then
        local bboxMin, bboxMax = utils.getVector4BBox(bBoxPoints)
        callback({ bBox = { min = bboxMin, max = bboxMax }, meshes = meshes })
    end
end

return builder