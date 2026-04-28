function cameraForwardFromAngles(yaw, pitch)
    return vector3(
        -math.sin(math.rad(yaw)) * math.cos(math.rad(pitch)),
        math.cos(math.rad(yaw)) * math.cos(math.rad(pitch)),
        math.sin(math.rad(pitch))
    )
end

function cameraRightFromYaw(yaw)
    return vector3(
        math.sin(math.rad(yaw + 90)),
        -math.cos(math.rad(yaw + 90)),
        0
    )
end

function clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

function sendUiUpdate(data)
    SendNUIMessage({
        type = 'update',
        data = data
    })
end

function showUi()
    SendNUIMessage({
        type = 'show'
    })
end

function hideUi()
    SendNUIMessage({
        type = 'hide'
    })
end

function toggleUi()
    SendNUIMessage({
        type = 'toggle'
    })
end
