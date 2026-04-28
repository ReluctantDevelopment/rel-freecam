local cam
local freecamActive = false
local playerPed
local startPos

local defaultFov = 60.0
local fov = defaultFov
local minFov = 20.0
local maxFov = 90.0
local moveStep = 0.3
local maxRange = 5.0

local lastUiUpdate = 0
local uiUpdateEveryMs = 100

local function resetCameraPose()
    SetCamCoord(cam, startPos.x, startPos.y, startPos.z)
    SetCamRot(cam, 0.0, 0.0, 0.0, 2)
    fov = defaultFov
    SetCamFov(cam, fov)
end

local function exitFreecam()
    if not freecamActive then return end

    freecamActive = false
    RenderScriptCams(false, false, 0, true, true)

    if cam then
        DestroyCam(cam, false)
        cam = nil
    end

    if playerPed and DoesEntityExist(playerPed) then
        SetFocusEntity(playerPed)
        FreezeEntityPosition(playerPed, false)
    end

    DisplayHud(true)
    DisplayRadar(true)
    hideUi()
end

local function startFreecam()
    if freecamActive then return end

    local gameplayPos = GetGameplayCamCoord()
    local gameplayRot = GetGameplayCamRot(2)

    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, gameplayPos.x, gameplayPos.y, gameplayPos.z)
    SetCamRot(cam, gameplayRot.x, gameplayRot.y, gameplayRot.z, 2)
    SetCamFov(cam, fov)
    RenderScriptCams(true, false, 0, true, true)
    SetFocusPosAndVel(gameplayPos.x, gameplayPos.y, gameplayPos.z, 0.0, 0.0, 0.0)

    startPos = gameplayPos
    freecamActive = true
    playerPed = PlayerPedId()

    showUi()
    FreezeEntityPosition(playerPed, true)

    CreateThread(function()
        while freecamActive do
            DisableAllControlActions(0)

            local camCoords = GetCamCoord(cam)
            local camRot = GetCamRot(cam, 2)
            local pitch, yaw = camRot.x, camRot.z

            local forward = cameraForwardFromAngles(yaw, pitch)
            local right = cameraRightFromYaw(yaw)
            local newCoords = camCoords

            if IsDisabledControlPressed(0, 172) then newCoords = newCoords + forward * moveStep end
            if IsDisabledControlPressed(0, 173) then newCoords = newCoords - forward * moveStep end
            if IsDisabledControlPressed(0, 174) then newCoords = newCoords - right * moveStep end
            if IsDisabledControlPressed(0, 175) then newCoords = newCoords + right * moveStep end
            if IsDisabledControlPressed(0, 44) then newCoords = vector3(newCoords.x, newCoords.y, newCoords.z + moveStep) end
            if IsDisabledControlPressed(0, 38) then newCoords = vector3(newCoords.x, newCoords.y, newCoords.z - moveStep) end

            local mouseX = GetDisabledControlNormal(0, 1)
            local mouseY = GetDisabledControlNormal(0, 2)
            yaw = yaw - mouseX * 5.0
            pitch = clamp(pitch + mouseY * 5.0, -89.0, 89.0)

            SetCamRot(cam, pitch, 0.0, yaw, 2)

            if #(newCoords - startPos) > maxRange then
                exitFreecam()
                break
            end

            SetCamCoord(cam, newCoords.x, newCoords.y, newCoords.z)

            if IsDisabledControlJustPressed(0, 14) then
                fov = math.min(fov + 2.0, maxFov)
                SetCamFov(cam, fov)
            elseif IsDisabledControlJustPressed(0, 15) then
                fov = math.max(fov - 2.0, minFov)
                SetCamFov(cam, fov)
            end

            if IsDisabledControlJustPressed(0, 47) then
                resetCameraPose()
            end

            if IsDisabledControlJustPressed(0, 22) then
                exitFreecam()
                break
            end

            if IsDisabledControlJustPressed(0, 74) then
                toggleUi()
            end

            local now = GetGameTimer()
            if now - lastUiUpdate >= uiUpdateEveryMs then
                lastUiUpdate = now
                sendUiUpdate({
                    fov = string.format("%.0f", fov),
                })
            end

            Wait(0)
        end

        FreezeEntityPosition(playerPed, false)
    end)
end

RegisterCommand("freecam", function()
    startFreecam()
end, false)

RegisterNUICallback('exit', function(_, cb)
    exitFreecam()
    cb('ok')
end)

RegisterNUICallback('reset', function(_, cb)
    if freecamActive then
        DisplayHud(true)
        DisplayRadar(true)
        resetCameraPose()
    end
    cb('ok')
end)
