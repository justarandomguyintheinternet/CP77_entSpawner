local builder = {
    callbacks = {}
}

function builder.hook()
    local inputListener = NewProxy({
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
            }
        })

    Game.GetCallbackSystem():RegisterCallback('Entity/Initialize', inputListener:Target(), inputListener:Function('OnEntityAssemble'), true)
end

function builder.registerCallback(entityID, callback)
    builder.callbacks[tonumber(entityID.hash)] = callback
end

return builder