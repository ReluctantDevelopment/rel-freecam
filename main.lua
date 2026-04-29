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
local traceMask = 511
local wallBuffer = 0.05
local cameraRadius = 0.2
local sweepStep = 0.15
local stuckTimeoutMs = 10000
local peekCheckDistance = 0.5
local wallClearance = 0.18
local probeOffset = 0.12

local CTRL_FORWARD = 32 -- W
local CTRL_BACK = 33 -- S
local CTRL_LEFT = 34 -- A
local CTRL_RIGHT = 35 -- D
local CTRL_UP = 44 -- Q
local CTRL_DOWN = 38 -- E
local CTRL_FOV_OUT = 14 -- ScrollWheel
local CTRL_FOV_IN = 15 -- ScrollWheel
local CTRL_RESET = 47 -- R
local CTRL_EXIT = 22 -- Space
local CTRL_TOGGLE_UI = 74 -- H

local lastUiUpdate = 0
local uiUpdateEveryMs = 100
local stuckMs = 0
local lastStuckCheckAt = 0
local safeCoords

local function dot(a, b)
    return (a.x * b.x) + (a.y * b.y) + (a.z * b.z)
end

local function normalize(vec)
    local length = #vec
    if length <= 0.0001 then
        return vector3(0.0, 0.0, 0.0), 0.0
    end

    return vector3(vec.x / length, vec.y / length, vec.z / length), length
end

local function castRay(fromCoords, toCoords)
    local probe = StartShapeTestRay(
        fromCoords.x, fromCoords.y, fromCoords.z,
        toCoords.x, toCoords.y, toCoords.z,
        traceMask,
        playerPed,
        7
    )

    local _, hit, hitCoords, surfaceNormal = GetShapeTestResult(probe)
    return hit == 1, hitCoords, surfaceNormal
end

local function getSideVector(direction)
    local flat = vector3(-direction.y, direction.x, 0.0)
    local perp, len = normalize(flat)
    if len <= 0.0001 then
        return vector3(1.0, 0.0, 0.0)
    end
    return perp
end

local function castSweep(fromCoords, toCoords, direction)
    local dir, _ = normalize(direction)
    if #dir <= 0.0001 then
        return false, toCoords, vector3(0.0, 0.0, 0.0)
    end

    local side = getSideVector(dir)
    local up = vector3(0.0, 0.0, 1.0)
    local offsets = {
        vector3(0.0, 0.0, 0.0),
        side * probeOffset,
        side * -probeOffset,
        up * (probeOffset * 0.75),
        up * -(probeOffset * 0.75)
    }

    local closestDistance = math.huge
    local closestNormal

    for i = 1, #offsets do
        local offset = offsets[i]
        local hit, hitCoords, surfaceNormal = castRay(fromCoords + offset, toCoords + offset)
        if hit then
            local hitDistance = #(hitCoords - (fromCoords + offset))
            if hitDistance < closestDistance then
                closestDistance = hitDistance
                closestNormal = surfaceNormal
            end
        end
    end

    if closestDistance == math.huge then
        return false, toCoords, vector3(0.0, 0.0, 0.0)
    end

    local centerHitCoords = fromCoords + (dir * closestDistance)
    return true, centerHitCoords, closestNormal
end

local function applyMovementStep(fromCoords, movement)
    local movementDir, movementLength = normalize(movement)
    if movementLength <= 0.0001 then
        return fromCoords, false
    end

    local target = fromCoords + movement
    local hit, hitCoords, surfaceNormal = castSweep(fromCoords, target, movementDir)
    if not hit then
        return target, false
    end

    local safeDistance = math.max(#(hitCoords - fromCoords) - wallBuffer, 0.0)
    local blockedPos = fromCoords + movementDir * safeDistance

    local remaining = target - blockedPos
    local normalDot = dot(remaining, surfaceNormal)
    local slide = remaining - (surfaceNormal * normalDot)
    local slideDir, slideLength = normalize(slide)
    if slideLength <= 0.0001 then
        return blockedPos, true
    end

    local slideTarget = blockedPos + slide
    local slideHit, slideHitCoords = castSweep(blockedPos, slideTarget, slideDir)
    if not slideHit then
        return slideTarget, true
    end

    local slideSafeDistance = math.max(#(slideHitCoords - blockedPos) - wallBuffer, 0.0)
    return blockedPos + slideDir * slideSafeDistance, true
end

local function isInsideWall(coords)
    local checkDistance = cameraRadius * 0.9
    local dirs = {
        vector3(1.0, 0.0, 0.0),
        vector3(-1.0, 0.0, 0.0),
        vector3(0.0, 1.0, 0.0),
        vector3(0.0, -1.0, 0.0),
        vector3(0.0, 0.0, 1.0),
        vector3(0.0, 0.0, -1.0)
    }

    local blockedCount = 0
    for i = 1, #dirs do
        local dir = dirs[i]
        local hit, hitCoords = castRay(coords, coords + (dir * checkDistance))
        if hit and #(hitCoords - coords) <= (checkDistance * 0.95) then
            blockedCount = blockedCount + 1
        end
    end

    return blockedCount >= 5
end

local function moveWithCollision(fromCoords, toCoords)
    local totalMovement = toCoords - fromCoords
    local movementDir, movementLength = normalize(totalMovement)

    if movementLength <= 0.0001 then
        return toCoords
    end

    local steps = math.max(1, math.ceil(movementLength / sweepStep))
    local stepDistance = movementLength / steps
    local stepMovement = movementDir * stepDistance
    local current = fromCoords
    local hadCollision = false

    for _ = 1, steps do
        local nextPos, stepCollided = applyMovementStep(current, stepMovement)
        if stepCollided then
            hadCollision = true
        end
        if #(nextPos - current) <= 0.0001 then
            break
        end
        current = nextPos
    end

    return current, hadCollision
end

local function preventWallPeek(cameraCoords, yaw, pitch)
    local forward = cameraForwardFromAngles(yaw, pitch)
    local probeTarget = cameraCoords + (forward * peekCheckDistance)
    local hit, hitCoords = castSweep(cameraCoords, probeTarget, forward)
    if not hit then
        return cameraCoords, false
    end

    local distanceToWall = #(hitCoords - cameraCoords)
    if distanceToWall >= wallClearance then
        return cameraCoords, false
    end

    local pushBackDistance = (wallClearance - distanceToWall) + wallBuffer
    local pushedCoords = cameraCoords + (forward * -pushBackDistance)
    local correctedCoords = moveWithCollision(cameraCoords, pushedCoords)
    return correctedCoords, true
end

local function getMovementVector(yaw, pitch)
    local forward = cameraForwardFromAngles(yaw, pitch)
    local right = cameraRightFromYaw(yaw)
    local movement = vector3(0.0, 0.0, 0.0)

    if IsDisabledControlPressed(0, CTRL_FORWARD) then movement = movement + forward * moveStep end
    if IsDisabledControlPressed(0, CTRL_BACK) then movement = movement - forward * moveStep end
    if IsDisabledControlPressed(0, CTRL_LEFT) then movement = movement - right * moveStep end
    if IsDisabledControlPressed(0, CTRL_RIGHT) then movement = movement + right * moveStep end
    if IsDisabledControlPressed(0, CTRL_UP) then movement = vector3(movement.x, movement.y, movement.z + moveStep) end
    if IsDisabledControlPressed(0, CTRL_DOWN) then movement = vector3(movement.x, movement.y, movement.z - moveStep) end

    return movement
end

local function resetCameraPose()
    SetCamCoord(cam, startPos.x, startPos.y, startPos.z)
    SetCamRot(cam, 0.0, 0.0, 0.0, 2)
    fov = defaultFov
    SetCamFov(cam, fov)
    SetFocusPosAndVel(startPos.x, startPos.y, startPos.z, 0.0, 0.0, 0.0)
    safeCoords = startPos
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
    stuckMs = 0
    lastStuckCheckAt = GetGameTimer()
    safeCoords = gameplayPos

    showUi()
    FreezeEntityPosition(playerPed, true)

    CreateThread(function()
        while freecamActive do
            DisableAllControlActions(0)

            local camCoords = GetCamCoord(cam)
            local camRot = GetCamRot(cam, 2)
            local pitch, yaw = camRot.x, camRot.z

            local desiredCoords = camCoords + getMovementVector(yaw, pitch)

            local mouseX = GetDisabledControlNormal(0, 1)
            local mouseY = GetDisabledControlNormal(0, 2)
            yaw = yaw - mouseX * 5.0
            pitch = clamp(pitch + mouseY * 5.0, -89.0, 89.0)

            SetCamRot(cam, pitch, 0.0, yaw, 2)

            local newCoords, collidedWithWall = moveWithCollision(camCoords, desiredCoords)
            if #(newCoords - startPos) > maxRange then
                exitFreecam()
                break
            end

            local wallPeekAdjusted
            newCoords, wallPeekAdjusted = preventWallPeek(newCoords, yaw, pitch)
            local insideWall = isInsideWall(newCoords)
            if insideWall and safeCoords then
                newCoords = safeCoords
                insideWall = isInsideWall(newCoords)
            end
            if not insideWall then
                safeCoords = newCoords
            end

            local now = GetGameTimer()
            local deltaMs = now - lastStuckCheckAt
            lastStuckCheckAt = now

            if collidedWithWall or wallPeekAdjusted or insideWall then
                stuckMs = stuckMs + math.max(deltaMs, 0)
                if stuckMs >= stuckTimeoutMs then
                    exitFreecam()
                    break
                end
            else
                stuckMs = 0
            end

            RequestCollisionAtCoord(newCoords.x, newCoords.y, newCoords.z)
            SetFocusPosAndVel(newCoords.x, newCoords.y, newCoords.z, 0.0, 0.0, 0.0)
            SetCamCoord(cam, newCoords.x, newCoords.y, newCoords.z)

            if IsDisabledControlJustPressed(0, CTRL_FOV_OUT) then
                fov = math.min(fov + 2.0, maxFov)
                SetCamFov(cam, fov)
            elseif IsDisabledControlJustPressed(0, CTRL_FOV_IN) then
                fov = math.max(fov - 2.0, minFov)
                SetCamFov(cam, fov)
            end

            if IsDisabledControlJustPressed(0, CTRL_RESET) then
                resetCameraPose()
            end

            if IsDisabledControlJustPressed(0, CTRL_EXIT) then
                exitFreecam()
                break
            end

            if IsDisabledControlJustPressed(0, CTRL_TOGGLE_UI) then
                toggleUi()
            end

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
