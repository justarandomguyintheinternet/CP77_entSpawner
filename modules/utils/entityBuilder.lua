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
                    if not event then return end

                    local entity = event:GetEntity()
                    local idHash = entity:GetEntityID().hash

                    if builder.callbacks[tostring(idHash)] then
                        builder.callbacks[tostring(idHash)](entity)
                        builder.callbacks[tostring(idHash)] = nil
                    end
                end
            },
            OnResourceReady = {
                args = {'handle:ResourceToken'},
                callback = function(token)
                    if type(token) ~= "userdata" then
                        print("Token not userdata")
                        return
                    end
                    if not IsDefined(token) then return end
                    if token:IsFailed() or not token:IsFinished() then return end

                    if builder.callbacks[tostring(token:GetHash())] then
                        builder.callbacks[tostring(token:GetHash())](token:GetResource())
                        builder.callbacks[tostring(token:GetHash())] = nil
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
    builder.callbacks[tostring(entityID.hash)] = callback
end

---Loads the specified resource and calls the callback when it is ready
---@param path string
---@param callback function Gets the resource passed as an argument
function builder.registerLoadResource(path, callback)
    local pathAsHash = loadstring("return " .. path, "")()
    if type(pathAsHash) == "cdata" then
        path = ResRef.FromHash(pathAsHash)
    end

    local token = Game.GetResourceDepot():LoadResource(path)

    if not token:IsFailed() then
        builder.callbacks[tostring(token:GetHash())] = callback
        token:RegisterCallback(listener:Target(), listener:Function('OnResourceReady'))
    end
end

---Gets the approximate offset of a component, not considering the parent componentes
---@param component entIComponent
local function getComponentOffset(component)
    local offset = WorldTransform.new()
    offset:SetPosition(component:GetLocalPosition())
    offset:SetOrientation(component:GetLocalOrientation())

    return offset
end

local function shouldUseMesh(component)
    local enabled = component:IsEnabled()
    local isMesh = component:IsA("entMeshComponent") or component:IsA("entSkinnedMeshComponent")
    local ignore = false
    local meshExists = false

    if isMesh then
        ignore = ResRef.FromHash(component.mesh.hash):ToString():match("base\\spawner") or ResRef.FromHash(component.mesh.hash):ToString():match("base\\amm_props\\mesh\\invis_")
        meshExists = Game.GetResourceDepot():ResourceExists(ResRef.FromHash(component.mesh.hash))
    end

    return enabled and isMesh and meshExists and not ignore
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
        if shouldUseMesh(component) then
            local path = ResRef.FromHash(component.mesh.hash):ToString()
            if path == "" then
                path = tostring(component.mesh.hash)
            end

            meshesTask:addTask(function ()
                local offset = getComponentOffset(component)
                utils.log("[entityBuilder] task for mesh " .. path)

                cache.tryGet(path .. "_bBox_max", path .. "_bBox_min", path .. "_collisions")
                .notFound(function (task)
                    utils.log("[entityBuilder] notFound BBOX for mesh " .. path)

                    builder.registerLoadResource(path, function(resource)
                        local min = resource.boundingBox.Min
                        local max = resource.boundingBox.Max

                        cache.addValue(path .. "_bBox_max", utils.fromVector(max))
                        cache.addValue(path .. "_bBox_min", utils.fromVector(min))

                        utils.log("[entityBuilder] loaded from resource BBOX for mesh " .. path)

                        task:taskCompleted()
                    end)
                end)
                .found(function ()
                    local min = ToVector4(cache.getValue(path .. "_bBox_min"))
                    local max = ToVector4(cache.getValue(path .. "_bBox_max"))

                    table.insert(meshes, {
                        min = min,
                        max = max,
                        pos = offset:GetWorldPosition():ToVector4(),
                        rot = offset:GetOrientation():ToEulerAngles(),
                        path = path,
                        app = component.meshAppearance.value,
                        name = component.name.value
                    })

                    table.insert(bBoxPoints, offset:GetOrientation():Transform(min))
                    table.insert(bBoxPoints, offset:GetOrientation():Transform(max))

                    utils.log("[entityBuilder] found BBOX for mesh " .. path)
                    utils.log("[entityBuilder] meshesTask todo: " .. meshesTask.tasksTodo - 1)
                    meshesTask:taskCompleted()
                end)
            end)
        end
    end

    meshesTask:onFinalize(function ()
        utils.log("[entityBuilder] onFinalize BBOX for entity " .. ResRef.ToString(entity:GetTemplatePath()))
        local bboxMin, bboxMax = utils.getVector4BBox(bBoxPoints)
        callback({ bBox = { min = bboxMin, max = bboxMax }, meshes = meshes })
    end)

    meshesTask.taskDelay = 0.1
    meshesTask:run(true)
end

return builder