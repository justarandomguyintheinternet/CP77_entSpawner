local utils = require("modules/utils/utils")
local tween = require("modules/tween/tween")

---@class camera
local camera = {
    active = false,
    distance = 3,
    xOffset = 0,
    deltaTime = 0,
    components = {},
    playerTransform = nil,
    cameraTransform = nil,
    preTransitionCameraDistance = 0,
    translateSpeed = 4,
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
    if not Game.GetPlayer() then return end

    if not camera.playerTransform then
        camera.playerTransform = { position = GetPlayer():GetWorldPosition(), rotation = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetRotation() }
        camera.cameraTransform = { position = GetPlayer():GetWorldPosition(), rotation = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetRotation() }
    end

    if state == camera.active then return end

    camera.active = state

    if camera.active then
        if Vector4.Distance(GetPlayer():GetWorldPosition(), camera.cameraTransform.position) > 50 then
            camera.cameraTransform.position = GetPlayer():GetWorldPosition()
        end

        Game.GetPlayer():GetFPPCameraComponent():SetLocalPosition(Vector4.new(- camera.xOffset, - camera.distance, 0, 0))
        setSceneTier(4)

        for _, component in pairs(GetPlayer():GetComponents()) do
            if component:IsA("entIVisualComponent") and component:IsEnabled() then
                table.insert(camera.components, component.name.value)
                component:Toggle(false)
            end
        end

        camera.playerTransform.position = GetPlayer():GetWorldPosition()
        camera.playerTransform.rotation = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetRotation()

        GetPlayer():GetFPPCameraComponent().pitchMax = camera.cameraTransform.rotation.pitch
        GetPlayer():GetFPPCameraComponent().pitchMin = camera.cameraTransform.rotation.pitch

        camera.update()
    else
        camera.cameraTransform.position = GetPlayer():GetWorldPosition()

        local distance = Vector4.Distance(GetPlayer():GetWorldPosition(), camera.playerTransform.position)
        if distance > 50 then
            camera.transition(camera.cameraTransform.position, camera.playerTransform.position, camera.cameraTransform.rotation, camera.playerTransform.rotation, 0, distance / 50)
            camera.preTransitionCameraDistance = camera.distance
        else
            GetPlayer():GetFPPCameraComponent():SetLocalPosition(Vector4.new(0.0, 0, 0, 0))
            setSceneTier(1)

            for _, component in pairs(camera.components) do
                local instance = GetPlayer():FindComponentByName(component)
                if instance then
                    instance:Toggle(true)
                end
            end

            camera.components = {}
            camera.transitionTween = nil

            Game.GetTeleportationFacility():Teleport(GetPlayer(), camera.playerTransform.position, camera.playerTransform.rotation)
            GetPlayer():GetFPPCameraComponent().pitchMax = camera.playerTransform.rotation.pitch
            GetPlayer():GetFPPCameraComponent().pitchMin = camera.playerTransform.rotation.pitch
        end
    end

    GetPlayer():DisableCameraBobbing(camera.active)
end

function camera.update()
    if not GetPlayer() then return end

    if camera.transitionTween then
        local done = camera.transitionTween:update(camera.deltaTime)

        if done then
            camera.transitionTween = nil

            if not camera.active then
                for _, component in pairs(camera.components) do
                    GetPlayer():FindComponentByName(component):Toggle(true)
                end
                setSceneTier(1)

                GetPlayer():GetFPPCameraComponent().pitchMax = camera.playerTransform.rotation.pitch
                GetPlayer():GetFPPCameraComponent().pitchMin = camera.playerTransform.rotation.pitch

                camera.distance = camera.preTransitionCameraDistance
            end
        else
            camera.cameraTransform.position = Vector4.new(camera.transitionTween.subject.x, camera.transitionTween.subject.y, camera.transitionTween.subject.z, 0)
            camera.distance = camera.transitionTween.subject.distance

            GetPlayer():GetFPPCameraComponent():SetLocalPosition(Vector4.new(0, - camera.distance, 0, 0))
            Game.GetTeleportationFacility():Teleport(GetPlayer(), camera.cameraTransform.position, EulerAngles.new(0, 0, camera.transitionTween.subject.yaw))
            return
        end
    end

    if not camera.active then return end

    if ImGui.IsMouseDragging(ImGuiMouseButton.Middle, 0) then
        local x, y = ImGui.GetMouseDragDelta(ImGuiMouseButton.Middle, 0)
        ImGui.ResetMouseDragDelta(ImGuiMouseButton.Middle)

        local distanceMultiplier = math.max(1, (camera.distance / 10))

        if ImGui.IsKeyDown(ImGuiKey.LeftShift) then
            camera.cameraTransform.position = utils.addVector(camera.cameraTransform.position, utils.multVector(camera.cameraTransform.rotation:GetUp(), (y / camera.translateSpeed) * camera.deltaTime  * distanceMultiplier))
            camera.cameraTransform.position = utils.subVector(camera.cameraTransform.position, utils.multVector(camera.cameraTransform.rotation:GetRight(), (x / camera.translateSpeed) * camera.deltaTime  * distanceMultiplier))
        elseif ImGui.IsKeyDown(ImGuiKey.LeftCtrl) then
            camera.distance = camera.distance + (y / camera.zoomSpeed) * camera.deltaTime * distanceMultiplier
            camera.distance = math.max(0.1, camera.distance)

            GetPlayer():GetFPPCameraComponent():SetLocalPosition(Vector4.new(0, - camera.distance, 0, 0))
        else
            camera.cameraTransform.rotation.yaw = camera.cameraTransform.rotation.yaw - (x / camera.rotateSpeed) * camera.deltaTime
            camera.cameraTransform.rotation.pitch = camera.cameraTransform.rotation.pitch - (y / camera.rotateSpeed) * camera.deltaTime
            GetPlayer():GetFPPCameraComponent().pitchMax = camera.cameraTransform.rotation.pitch
            GetPlayer():GetFPPCameraComponent().pitchMin = camera.cameraTransform.rotation.pitch
        end
    end

    Game.GetTeleportationFacility():Teleport(GetPlayer(), camera.cameraTransform.position, camera.cameraTransform.rotation)
    Game.GetStatPoolsSystem():RequestSettingStatPoolValue(GetPlayer():GetEntityID(), gamedataStatPoolType.Health, 100, nil)
end

function camera.updateXOffset(adjustedCenterX)
    if not camera.active then return end

    local centerDir, _ = camera.screenToWorld(adjustedCenterX, 0)
    camera.xOffset = ((1 / centerDir.y) * camera.distance) * centerDir.x

    GetPlayer():GetFPPCameraComponent():SetLocalPosition(Vector4.new(- camera.xOffset, - camera.distance, 0, 0))
end

function camera.transition(fromPos, toPos, fromRot, toRot, toDistance, duration)
    camera.transitionTween = tween.new(duration,
    { x = fromPos.x, y = fromPos.y, z = fromPos.z, yaw = fromRot.yaw, distance = camera.distance },
    { x = toPos.x, y = toPos.y, z = toPos.z, yaw = toRot.yaw, distance = toDistance },
    tween.easing.inOutQuad)
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

function camera.worldToScreen(position)
    local res = Game.GetCameraSystem():ProjectPoint(position)

    return res.x, res.y
end

return camera