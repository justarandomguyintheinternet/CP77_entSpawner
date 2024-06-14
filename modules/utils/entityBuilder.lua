local cache = require("modules/utils/cache")
local utils = require("modules/utils/utils")
local task = require("modules/utils/tasks")

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

---Gets the approximate offset of a component, not consdidring the parent componentes
---@param component entIComponent
local function getComponentOffset(component)
    local offset = WorldTransform.new()
    offset:SetPosition(Vector4.Transform(component:GetLocalToWorld(), component:GetLocalPosition()))
    offset:SetOrientation(component:GetLocalOrientation())

    return offset
end

---Gets the bounding box of an entity, and the position and rotation of each mesh component
---@param entity entEntity
---@param callback function Gets a table with the bounding box and a table with the meshes
function builder.getEntityBBox(entity, callback)
    local components = entity:GetComponents()
    local meshes = {}
    local bBoxPoints = {}

    local meshesTask = task:new()

    for _, component in ipairs(components) do
        if (component:IsA("entMeshComponent") or component:IsA("entSkinnedMeshComponent")) and not (ResRef.FromHash(component.mesh.hash):ToString():match("base\\spawner")) and not (ResRef.FromHash(component.mesh.hash):ToString():match("base\\amm_props\\mesh\\invis_")) then
            meshesTask:addTask(function ()
                local offset = WorldTransform.new()
                offset = getComponentOffset(component)
                local path = ResRef.FromHash(component.mesh.hash):ToString()

                cache.tryGet(path .. "_bBox_max", path .. "_bBox_min")
                .notFound(function (task)
                    builder.registerLoadResource(path, function(resource)
                        local min = resource.boundingBox.Min
                        local max = resource.boundingBox.Max

                        cache.addValue(path .. "_bBox_max", utils.fromVector(max))
                        cache.addValue(path .. "_bBox_min", utils.fromVector(min))
                        print("Loaded BBOX for mesh " .. path)
                        task:taskCompleted()
                    end)
                end)
                .found(function ()
                    local min = ToVector4(cache.getValue(path .. "_bBox_min"))
                    local max = ToVector4(cache.getValue(path .. "_bBox_min"))

                    table.insert(meshes, {
                        min = min,
                        max = max,
                        pos = offset:GetWorldPosition():ToVector4(),
                        rot = offset:GetOrientation():ToEulerAngles(),
                        path = path,
                        app = component.meshAppearance.value
                    })

                    table.insert(bBoxPoints, offset:GetOrientation():Transform(min))
                    table.insert(bBoxPoints, offset:GetOrientation():Transform(max))

                    meshesTask:taskCompleted()
                end)
            end)
        end
    end

    meshesTask:onFinalize(function ()
        local bboxMin, bboxMax = utils.getVector4BBox(bBoxPoints)
        callback({ bBox = { min = bboxMin, max = bboxMax }, meshes = meshes })
    end)

    meshesTask:run()
end

return builder