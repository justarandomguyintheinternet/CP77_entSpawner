local utils = require("modules/utils/utils")
local tween = require("modules/tween/tween")

local camera = {
    active = false,
    distance = 3,
    deltaTime = 0,
    components = {},
    playerPosition = nil,
    cameraPosition = nil,
    translateSpeed = 3,
    rotateSpeed = 0.4,
    zoomSpeed = 2.75,
    transitionTween = nil,
    suspendState = false
}

local function setSceneTier(tier)
    local blackboardDefs = Game.GetAllBlackboardDefs()
    local blackboardPSM = Game.GetBlackboardSystem():GetLocalInstanced(GetPlayer():GetEntityID(), blackboardDefs.PlayerStateMachine)
    blackboardPSM:SetInt(blackboardDefs.PlayerStateMachine.SceneTier, tier, true)
end

function camera.toggle(state)
    if not camera.playerPosition then
        camera.playerPosition = GetPlayer():GetWorldPosition()
        camera.cameraPosition = GetPlayer():GetWorldPosition()
    end

    if state == camera.active then return end

    camera.active = state

    if camera.active then
        Game.GetPlayer():GetFPPCameraComponent():SetLocalPosition(Vector4.new(0, - camera.distance, 0, 0))
        setSceneTier(4)

        for _, component in pairs(GetPlayer():GetComponents()) do
            if component:IsA("entIVisualComponent") and component:IsEnabled() then
                table.insert(camera.components, component.name.value)
                component:Toggle(false)
            end
        end

        camera.playerPosition = GetPlayer():GetWorldPosition()

        -- camera.transition(camera.playerPosition, camera.cameraPosition, 1)
        camera.update()
    else
        GetPlayer():GetFPPCameraComponent():SetLocalPosition(Vector4.new(0.0, 0, 0, 0))
        setSceneTier(1)

        for _, component in pairs(camera.components) do
            GetPlayer():FindComponentByName(component):Toggle(true)
        end

        camera.components = {}
        camera.transitionTween = nil
        camera.cameraPosition = GetPlayer():GetWorldPosition()

        Game.GetTeleportationFacility():Teleport(GetPlayer(), camera.playerPosition, GetPlayer():GetWorldOrientation():ToEulerAngles())
    end

    GetPlayer():DisableCameraBobbing(camera.active)
end

function camera.suspend(state)
    if camera.active and not state and not camera.suspendState then
        camera.suspendState = true
        camera.toggle(false)
    elseif not camera.active and state and camera.suspendState then
        camera.suspendState = false
        camera.toggle(true)
    end
end

function camera.update()
    local cameraRotation = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetRotation()

    if camera.transitionTween then
        local done = camera.transitionTween:update(camera.deltaTime)

        if done then
            camera.transitionTween = nil
        else
            camera.cameraPosition = Vector4.new(camera.transitionTween.subject.x, camera.transitionTween.subject.y, camera.transitionTween.subject.z, 0)
            Game.GetTeleportationFacility():Teleport(GetPlayer(), camera.cameraPosition, cameraRotation)
            return
        end
    end

    if not camera.active then return end

    if ImGui.IsMouseDragging(ImGuiMouseButton.Middle, 0) then
        local x, y = ImGui.GetMouseDragDelta(ImGuiMouseButton.Middle, 0)
        ImGui.ResetMouseDragDelta(ImGuiMouseButton.Middle)

        if ImGui.IsKeyDown(ImGuiKey.LeftShift) then
            camera.cameraPosition = utils.addVector(camera.cameraPosition, utils.multVector(cameraRotation:GetUp(), (y / camera.translateSpeed) * camera.deltaTime))
            camera.cameraPosition = utils.subVector(camera.cameraPosition, utils.multVector(cameraRotation:GetRight(), (x / camera.translateSpeed) * camera.deltaTime))
        elseif ImGui.IsKeyDown(ImGuiKey.LeftCtrl) then
            camera.distance = camera.distance + (y / camera.zoomSpeed) * camera.deltaTime
            camera.distance = math.max(0.1, camera.distance)

            GetPlayer():GetFPPCameraComponent():SetLocalPosition(Vector4.new(0, - camera.distance, 0, 0))
        else
            cameraRotation.yaw = cameraRotation.yaw - (x / camera.rotateSpeed) * camera.deltaTime
            local pitch = cameraRotation.pitch - (y / camera.rotateSpeed) * camera.deltaTime
            GetPlayer():GetFPPCameraComponent().pitchMax = pitch
            GetPlayer():GetFPPCameraComponent().pitchMin = pitch
        end
    end

    Game.GetTeleportationFacility():Teleport(GetPlayer(), camera.cameraPosition, cameraRotation)
end

function camera.updateXOffset(adjustedCenterX)
    if not camera.active then return end

    local centerDir, _ = camera.screenToWorld(adjustedCenterX, 0)
    local camXOffset = ((1 / centerDir.y) * camera.distance) * centerDir.x

    GetPlayer():GetFPPCameraComponent():SetLocalPosition(Vector4.new(-camXOffset, - camera.distance, 0, 0))
end

function camera.transition(from, to, duration)
    camera.transitionTween = tween.new(duration, { x = from.x, y = from.y, z = from.z }, { x = to.x, y = to.y, z = to.z }, tween.easing.inOutQuad)
end

function camera.screenToWorld(x, y)
    local cameraRotation = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetRotation()
    local pov = Game.GetPlayer():GetFPPCameraComponent():GetFOV()
    local width, height = GetDisplayResolution()

    local vertical = EulerAngles.new(0, pov / 2, 0):GetForward()
    local vecRelative = Vector4.new(vertical.z * (width / height) * x, vertical.y * 1, vertical.z * y, 0)

    local vecGlobal = Vector4.RotateAxis(vecRelative, Vector4.new(1, 0, 0, 0), math.rad(cameraRotation.pitch))
    vecGlobal = Vector4.RotateAxis(vecGlobal, Vector4.new(0, 0, 1, 0), math.rad(cameraRotation.yaw))

    return vecRelative, vecGlobal
end

return camera