local visualizer = {}

function visualizer.attachArrows(entity, scale)
    if not entity then return end

    local component = entMeshComponent.new()
    component.name = "arrows"
    component.mesh = ResRef.FromString("base\\spawner\\arrow.mesh")
    component.visualScale = Vector3.new(scale.x, scale.y, scale.z)
    component.meshAppearance = "all"
    component.visible = false
    entity:AddComponent(component)
end

function visualizer.showArrows(entity, state)
    if not entity then return end

    local component = entity:FindComponentByName("arrows")
    component:Toggle(state)
end

function visualizer.highlightArrow(entity, app)
    if not entity then return end

    local component = entity:FindComponentByName("arrows")

    component.meshAppearance = CName.new(app)
    component:LoadAppearance()
end

return visualizer