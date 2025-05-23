local cache = require("modules/utils/cache")
local utils = require("modules/utils/utils")
local task = require("modules/utils/tasks")
local intersection = require("modules/utils/editor/intersection")

local builder = {
    assembleCallbacks = {},
    attachCallbacks = {},
    resourceCallbacks = {}
}

function builder.init()
    Observe('EntityBuilder', 'OnAttached', function(_, event)
        if not event then return end
        if type(event.GetEntity) ~= "function" then return end

        local entity
        pcall(function ()
            entity = event:GetEntity()
        end)

        if not entity then return end

        local idHash = entity:GetEntityID().hash

        if builder.attachCallbacks[tostring(idHash)] then
            builder.attachCallbacks[tostring(idHash)](entity)
            builder.attachCallbacks[tostring(idHash)] = nil
        end
    end)

    Observe('EntityBuilder', 'OnAssemble', function(_, event)
        if not event then return end
        if type(event.GetEntity) ~= "function" then return end

        local entity = event:GetEntity()

        if not entity then return end

        local idHash = entity:GetEntityID().hash

        if builder.assembleCallbacks[tostring(idHash)] then
            builder.assembleCallbacks[tostring(idHash)](entity)
            builder.assembleCallbacks[tostring(idHash)] = nil
        end
    end)

    Observe('EntityBuilder', 'OnResourceReady', function(_, token)
        if type(token) ~= "userdata" then
            print("Token not userdata")
            return
        end
        if not IsDefined(token) then return end
        if token:IsFailed() or not token:IsFinished() then return end

        if builder.resourceCallbacks[tostring(token:GetHash())] then
            for _, callback in ipairs(builder.resourceCallbacks[tostring(token:GetHash())]) do
                callback(token:GetResource())
            end

            builder.resourceCallbacks[tostring(token:GetHash())] = nil
        end
    end)
end

---Register a callback to be called when the entity with the specified entEntityID is assembled
---@param entityID entEntityID
---@param callback function Gets the entity passed as an argument
function builder.registerAssembleCallback(entityID, callback)
    builder.assembleCallbacks[tostring(entityID.hash)] = callback
end

---Register a callback to be called when the entity with the specified entEntityID is attached
---@param entityID entEntityID
---@param callback function Gets the entity passed as an argument
function builder.registerAttachCallback(entityID, callback)
    builder.attachCallbacks[tostring(entityID.hash)] = callback
end

---Loads the specified resource and calls the callback when it is ready
---@param path string
---@param callback function Gets the resource passed as an argument
function builder.registerLoadResource(path, callback)
    pcall(function ()
        local pathAsHash = loadstring("return " .. path, "")()
        if type(pathAsHash) == "cdata" then
            path = ResRef.FromHash(pathAsHash)
        end
    end)

    local token = Game.GetResourceDepot():LoadResource(path)

    if not token:IsFailed() then
        Game.GetScriptableServiceContainer():GetService("EntityBuilder"):RegisterResourceCallback(token)
        if not builder.resourceCallbacks[tostring(token:GetHash())] then
            builder.resourceCallbacks[tostring(token:GetHash())] = { callback }
        else
            table.insert(builder.resourceCallbacks[tostring(token:GetHash())], callback)
        end
    end
end

---Gets the positional and rotational offset of a component, relative to the owner entity
---@param component entIComponent
function builder.getComponentOffset(entity, component)
    local localToWorld = component:GetLocalToWorld()

    local posDiff = utils.subVector(localToWorld:GetTranslation(), entity:GetWorldPosition())

    if Vector4.Length(posDiff) > 250 then
        posDiff = Vector4.new(0, 0, 0)
    end

    local rotDiff = Quaternion.MulInverse(localToWorld:GetRotation():ToQuat(), entity:GetWorldOrientation())

    local offset = WorldTransform.new()
    offset:SetPosition(posDiff)
    offset:SetOrientation(rotDiff)

    return offset
end

function builder.shouldUseMesh(component)
    local enabled = component:IsEnabled()
    local isDestruction = component:IsA("entPhysicalDestructionComponent")
    local isMesh = component:IsA("entMeshComponent") or component:IsA("entSkinnedMeshComponent")
    local ignore = false
    local meshExists = false

    if isMesh or isDestruction then
        local path = ResRef.FromHash(component.mesh.hash):ToString()
        ignore = path:match("base\\spawner") or path:match("base\\amm_props\\mesh\\invis_")
        meshExists = Game.GetResourceDepot():ResourceExists(ResRef.FromHash(component.mesh.hash))
    end

    return { use = enabled and isMesh and meshExists and not ignore, meshExists = meshExists, isDestruction = isDestruction }
end

---Gets the bounding box of an entity, if not yet loaded, it will load the meshes and cache their bboxes
---@param entity entEntity
---@param callback function Gets a table with the bounding box and a table with the meshes
function builder.getEntityBBox(entity, callback)
    local entityPath = ResRef.ToString(entity:GetTemplatePath())
    entityPath = entityPath == "" and tostring(entity:GetTemplatePath():GetHash()) or entityPath
    local components = entity:GetComponents()
    local meshes = {}
    local bBoxPoints = {}

    local meshesTask = task:new()

    for _, component in ipairs(components) do
        local use = builder.shouldUseMesh(component)

        if use.use or (use.isDestruction and use.meshExists) then
            local path = ResRef.FromHash(component.mesh.hash):ToString()
            if path == "" then
                path = tostring(component.mesh.hash)
            end

            meshesTask:addTask(function ()
                local offset = builder.getComponentOffset(entity, component)
                utils.log("[entityBuilder] task for mesh " .. path)

                cache.tryGet(path .. "_bBox_max", path .. "_bBox_min", path .. "_collision")
                .notFound(function (task)
                    utils.log("[entityBuilder] MISSING: BBOX for mesh " .. path)

                    builder.registerLoadResource(path, function(resource)
                        local min = resource.boundingBox.Min
                        local max = resource.boundingBox.Max

                        local collision = false
                        for _, param in pairs(resource.parameters) do
                            if param:IsA("meshMeshParamPhysics") then
                                collision = true
                                break
                            end
                        end

                        cache.addValue(path .. "_bBox_max", utils.fromVector(max))
                        cache.addValue(path .. "_bBox_min", utils.fromVector(min))
                        cache.addValue(path .. "_collision", collision)

                        utils.log("[entityBuilder] LOADED: BBOX for mesh " .. path)

                        task:taskCompleted()
                    end)
                end)
                .found(function ()
                    local originalScale = Vector4.Vector3To4(component.visualScale or Vector3.new(1, 1, 1))
                    local scalingFactor = intersection.getResourcePathScalingFactor(path, originalScale)
                    local scale = utils.multVecXVec(originalScale, scalingFactor)

                    local min = utils.multVecXVec(ToVector4(cache.getValue(path .. "_bBox_min")), scale)
                    local max = utils.multVecXVec(ToVector4(cache.getValue(path .. "_bBox_max")), scale)

                    table.insert(bBoxPoints, utils.addVector(
                        offset:GetOrientation():Transform(min),
                        offset:GetWorldPosition():ToVector4()
                    ))
                    table.insert(bBoxPoints, utils.addVector(
                        offset:GetOrientation():Transform(max),
                        offset:GetWorldPosition():ToVector4()
                    ))

                    table.insert(meshes, {
                        position = offset:GetWorldPosition():ToVector4(),
                        rotation = offset:GetOrientation(),
                        bbox = {
                            min = min,
                            max = max
                        },
                        path = path,
                        originalScale = originalScale,
                        collision = cache.getValue(path .. "_collision") and (component:IsA("entPhysicalMeshComponent") or component:IsA("entPhysicalDestructionComponent")),
                        app = component.meshAppearance.value,
                        globalPosition = component:GetLocalToWorld():GetTranslation(),
                        globalRotation = component:GetLocalToWorld():GetRotation()
                    })

                    utils.log("[entityBuilder] FOUND: BBOX for mesh " .. path)
                    utils.log("[entityBuilder] " .. meshesTask.tasksTodo - 1 .. " Meshes todo for " .. entityPath)
                    meshesTask:taskCompleted()
                end)
            end)
        end
    end

    meshesTask:onFinalize(function ()
        utils.log("[entityBuilder] onFinalize BBOX for entity " .. entityPath)
        local bboxMin, bboxMax = utils.getVector4BBox(bBoxPoints)
        callback({ bBox = { min = bboxMin, max = bboxMax }, meshes = meshes }) -- Keep mesh for more accurate bbox check for entity
    end)

    meshesTask.taskDelay = 0.015
    meshesTask:run(true)
end

return builder