local visualizer = {}

local previewComponentNames = {
    "box",
    "sphere",
    "capsule_body",
    "capsule_top",
    "capsule_bottom"
}

local function addMesh(entity, name, mesh, scale, app, enabled)
    local parent = nil
    for _, component in pairs(entity:GetComponents()) do
        if component:IsA("entMeshComponent") or component.name.value == "targeting" then
            parent = component
            break
        end
    end
    if not parent then parent = entity:GetComponents()[1] end

    local component = entMeshComponent.new()
    component.name = name
    component.mesh = ResRef.FromString(mesh)
    component.visualScale = ToVector3(scale)
    component.meshAppearance = app
    component.isEnabled = enabled

    -- Bind to something, to avoid weird bug where other components would lose their localTransform
    if parent then
        local parentTransform = entHardTransformBinding.new()
        parentTransform.bindName = parent.name.value
        component.parentTransform = parentTransform
    end

    entity:AddComponent(component)
end

---Creates and attached a box mesh, with the component name "box"
---@param entity entEntity
---@param scale { x : number, y : number, z : number }
---@param color? string
function visualizer.addBox(entity, scale, color)
    if not entity then return end

    if not color then
        local colors = { "red", "green", "blue" }
        color = colors[math.random(1, 3)]
    end

    addMesh(entity, "box", "base\\spawner\\cube.mesh", scale, color, true)
end

---Creates and attached a sphere mesh, with the component name "sphere"
---@param entity entEntity
---@param radius number
---@param color? string
function visualizer.addSphere(entity, radius, color)
    if not entity then return end

    if not color then
        local colors = { "red", "green", "blue" }
        color = colors[math.random(1, 3)]
    end

    addMesh(entity, "sphere", "base\\spawner\\sphere.mesh", { x = radius, y = radius, z = radius }, color, true)
end

function visualizer.addCapsule(entity, radius, height, color)
    if not entity then return end

    if not color then
        local colors = { "red", "green", "blue" }
        color = colors[math.random(1, 3)]
    end

    addMesh(entity, "capsule_body", "base\\spawner\\capsule_body.mesh", { x = radius, y = radius, z = height / 2 }, color, true)
    addMesh(entity, "capsule_bottom", "base\\spawner\\capsule_cap.mesh", { x = radius, y = radius, z = radius }, color, true)
    addMesh(entity, "capsule_top", "base\\spawner\\capsule_cap.mesh", { x = radius, y = radius, z = radius }, color, true)

    local component = entity:FindComponentByName("capsule_top")
    component:SetLocalPosition(Vector4.new(0, 0, height / 2, 0))
    local component = entity:FindComponentByName("capsule_bottom")
    component:SetLocalPosition(Vector4.new(0, 0, -height / 2, 0))
    component:SetLocalOrientation(EulerAngles.new(0, 180, 0):ToQuat())
end

---Creates and attached the arrow mesh, with the component name "arrows"
---@param entity entEntity
---@param scale { x : number, y : number, z : number }
function visualizer.attachArrows(entity, scale, active, app)
    if not entity then return end

    addMesh(entity, "arrows", "base\\spawner\\arrow.mesh", scale, app, active)
end

---Updates the scale of the given visualizer mesh
---@param entity entEntity
---@param scale { x : number, y : number, z : number }
---@param componentName string box|sphere|arrows
function visualizer.updateScale(entity, scale, componentName)
    if not entity then return end

    local component = entity:FindComponentByName(componentName)
    component.visualScale = ToVector3(scale)

    if component:IsEnabled() then
        component:Toggle(false)
        component:Toggle(true)
    end
end

function visualizer.updateCapsuleScale(entity, radius, height)
    if not entity then return end

    local top = entity:FindComponentByName("capsule_top")
    top.visualScale = ToVector3({ x = radius, y = radius, z = radius })
    top:SetLocalPosition(Vector4.new(0, 0, height / 2, 0))

    if top:IsEnabled() then
        top:Toggle(false)
        top:Toggle(true)
    end

    local bottom = entity:FindComponentByName("capsule_bottom")
    bottom.visualScale = ToVector3({ x = radius, y = radius, z = radius })
    bottom:SetLocalPosition(Vector4.new(0, 0, -height / 2, 0))
    bottom:SetLocalOrientation(EulerAngles.new(0, 180, 0):ToQuat())

    if bottom:IsEnabled() then
        bottom:Toggle(false)
        bottom:Toggle(true)
    end

    local body = entity:FindComponentByName("capsule_body")
    body.visualScale = ToVector3({ x = radius, y = radius, z = height / 2 })

    if body:IsEnabled() then
        body:Toggle(false)
        body:Toggle(true)
    end
end

function visualizer.showArrows(entity, state)
    if not entity then return end

    local component = entity:FindComponentByName("arrows")
    component:Toggle(state)
end

---Toggles the visibility of all visualizion meshes except for arrows
function visualizer.toggleAll(entity, state)
    if not entity then return end

    for _, name in pairs(previewComponentNames) do
        local component = entity:FindComponentByName(name)

        if component then
            component:Toggle(state)
        end
    end
end

function visualizer.highlightArrow(entity, app)
    if not entity then return end

    local component = entity:FindComponentByName("arrows")

    component.meshAppearance = CName.new(app)
    component:LoadAppearance()
end

return visualizer