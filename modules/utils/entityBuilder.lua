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
                    if entity:GetTemplatePath():GetHash() ~= ResRef.FromString("base\\game_object.ent"):GetHash() then return end

                    -- local comp = entMeshComponent.new()
                    -- comp.name = "cube"
                    -- comp.mesh = ResRef.FromString("engine\\meshes\\editor\\cube.mesh")
                    -- entity:AddComponent(comp)

                    if builder.callbacks[tonumber(idHash)] then
                        builder.callbacks[tonumber(idHash)](entity)
                        builder.callbacks[tonumber(idHash)] = nil
                    end
                end
            },
            OnResourceReady = {
                args = {'handle:ResourceToken'},
                callback = function(token)
                    if builder.callbacks[tonumber(token:GetHash())] then
                        builder.callbacks[tonumber(token:GetHash())](token:GetResource())
                        builder.callbacks[tonumber(token:GetHash())] = nil
                    end
                end
            }
        })
    Game.GetCallbackSystem():RegisterCallback('Entity/Initialize', listener:Target(), listener:Function('OnEntityAssemble'), true)
end

function builder.registerAssembleCallback(entityID, callback)
    builder.callbacks[tonumber(entityID.hash)] = callback
end

function builder.registerLoadResource(path, callback)
    local token = Game.GetResourceDepot():LoadResource(path)

    if not token:IsFailed() then
        builder.callbacks[tonumber(token:GetHash())] = callback
        token:RegisterCallback(listener:Target(), listener:Function('OnResourceReady'))
    end
end

return builder