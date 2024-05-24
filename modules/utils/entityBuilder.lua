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
                    if not success or token:IsFailed() or not token:IsFinished() then return end

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

return builder