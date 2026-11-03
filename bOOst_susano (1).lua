-- Susano loader: inject the original Lua UI into a FiveM resource VM.
-- The HTML/JS URL and original UI rendering are kept unchanged.

local payload = [=[
local isMenuVisible    = true
local duiObj           = nil
local txd              = nil
local txn              = nil
local chosenKeyControl = nil
local chosenKeyName    = nil

local WebURL = "https://raw.githack.com/20wn/Uix/main/index.html?v=" .. tostring(GetGameTimer())

local Features = {
    godmode     = false,
    superJump   = false,
    invisible   = false,
    punch       = false,
    noclip      = false,
    noclipSpeed = 2,
    ragdoll     = false
}

-- SPACE is deliberately absent: it is the noclip ascend key, so binding the menu
-- to it would close the menu every time he flies up.
local KeyMap = {
    [166] = "F5",  [167] = "F6",  [168] = "F7",  [169] = "F8",
    [56]  = "F9",  [57]  = "F10", [344] = "F11",
    [288] = "F1",  [289] = "F2",  [170] = "F3",
    [121] = "INSERT", [211] = "DELETE", [212] = "HOME",
    [213] = "PAGEUP",  [214] = "PAGEDOWN",
    [244] = "M",  [73]  = "X",  [74]  = "H",  [38]  = "E",
    [44]  = "Q",  [45]  = "R",  [47]  = "G",  [23]  = "F",
    [249] = "N",  [246] = "Y",  [245] = "T",
    [157] = "1",  [158] = "2",  [159] = "3",  [160] = "4",
    [164] = "5",  [165] = "6",  [161] = "7",  [162] = "8",
    [163] = "9",  [156] = "0",  [243] = "~"
}

local function InitUI()
    if duiObj then return end

    duiObj = CreateDui(WebURL, 1920, 1080)
    if not duiObj then
        print("[MAYSTRO] CreateDui failed")
        return
    end

    local timeout = GetGameTimer() + 15000
    while not IsDuiAvailable(duiObj) do
        if GetGameTimer() > timeout then
            print("[MAYSTRO] DUI load timeout")
            DestroyDui(duiObj)
            duiObj = nil
            return
        end
        Wait(100)
    end

    local duiHandle = GetDuiHandle(duiObj)
    txd = CreateRuntimeTxd("maystro_txd")
    txn = CreateRuntimeTextureFromDuiHandle(txd, "maystro_txn", duiHandle)
    Wait(600)
    SendDuiMessage(duiObj, json.encode({ action = "setResource", name = GetCurrentResourceName() }))
    SendDuiMessage(duiObj, json.encode({ action = "showKeybind" }))
    print("[MAYSTRO] UI Loaded!")
end

local function ToggleMenu(state)
    if state == nil then
        isMenuVisible = not isMenuVisible
    else
        isMenuVisible = state
    end
    SetNuiFocus(false, false)
    print(isMenuVisible and "[MAYSTRO] Menu Opened" or "[MAYSTRO] Menu Closed")
end

CreateThread(function()
    InitUI()
    SetNuiFocus(false, false)

    while true do
        Wait(0)
        if isMenuVisible and txd and txn then
            DrawSprite("maystro_txd", "maystro_txn", 0.5, 0.5, 1.0, 1.0, 0.0, 255, 255, 255, 255)

            if not chosenKeyControl then
                SetMouseCursorActiveThisFrame()
            end

            if duiObj then
                local mx = GetDisabledControlNormal(0, 239)
                local my = GetDisabledControlNormal(0, 240)
                SendDuiMouseMove(duiObj, math.floor(mx * 1920), math.floor(my * 1080))

                if IsDisabledControlJustPressed(0, 237) or IsControlJustPressed(0, 237) then
                    SendDuiMouseDown(duiObj, "left")
                elseif IsDisabledControlJustReleased(0, 237) or IsControlJustReleased(0, 237) then
                    SendDuiMouseUp(duiObj, "left")
                end
            end
        end
    end
end)

CreateThread(function()
    Wait(500)
    while true do
        Wait(0)
        if not duiObj then goto continue end

        if not chosenKeyControl then
            for controlId, keyName in pairs(KeyMap) do
                if IsDisabledControlJustPressed(0, controlId) or IsControlJustPressed(0, controlId) then
                    chosenKeyControl = controlId
                    chosenKeyName = keyName
                    print("[MAYSTRO] Key Chosen: " .. keyName)
                    SendDuiMessage(duiObj, json.encode({ action = "setKeybind", key = keyName }))
                    Wait(400)
                    break
                end
            end
        else
            if IsDisabledControlJustPressed(0, chosenKeyControl) or IsControlJustPressed(0, chosenKeyControl) then
                ToggleMenu()
                SendDuiMessage(duiObj, json.encode({ action = "toggleMenu" }))
                Wait(200)
            end

            if isMenuVisible then
                if IsDisabledControlJustPressed(0, 172) or IsDisabledControlJustPressed(0, 32) then
                    SendDuiMessage(duiObj, json.encode({ action = "keydown", key = "ArrowUp" }))
                end
                if IsDisabledControlJustPressed(0, 173) or IsDisabledControlJustPressed(0, 33) then
                    SendDuiMessage(duiObj, json.encode({ action = "keydown", key = "ArrowDown" }))
                end
                if IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 18) then
                    SendDuiMessage(duiObj, json.encode({ action = "keydown", key = "Enter" }))
                end
                if IsDisabledControlJustPressed(0, 194) then
                    SendDuiMessage(duiObj, json.encode({ action = "keydown", key = "Backspace" }))
                end
                if IsDisabledControlJustPressed(0, 174) or IsDisabledControlJustPressed(0, 34) then
                    SendDuiMessage(duiObj, json.encode({ action = "keydown", key = "ArrowLeft" }))
                end
                if IsDisabledControlJustPressed(0, 175) or IsDisabledControlJustPressed(0, 35) then
                    SendDuiMessage(duiObj, json.encode({ action = "keydown", key = "ArrowRight" }))
                end
            end
        end

        ::continue::
    end
end)

RegisterNUICallback("itemClicked", function(data, cb)
    local id = data.id
    local enabled = data.enabled
    local val = data.val
    print(("[MAYSTRO] itemClicked: %s enabled=%s val=%s"):format(tostring(id), tostring(enabled), tostring(val)))
    local ped = PlayerPedId()
    local player = PlayerId()

    if id == "godmode" then
        Features.godmode = enabled
        SetEntityInvincible(ped, enabled)
        SetPlayerInvincible(player, enabled)
    elseif id == "superJump" then
        Features.superJump = enabled
    elseif id == "invisible" then
        Features.invisible = enabled
        SetEntityVisible(ped, not enabled, 0)
    elseif id == "punch" then
        Features.punch = enabled
    elseif id == "noclip" then
        Features.noclip = enabled
        if val then Features.noclipSpeed = val end
        SetEntityCollision(ped, not enabled, not enabled)
        FreezeEntityPosition(ped, enabled)
    elseif id == "ragdoll" then
        Features.ragdoll = enabled
        if enabled then
            SetPedToRagdoll(ped, 3000, 3000, 0, 0, 0, 0)
        end
    end

    if cb then cb("ok") end
end)

-- Picking a new key in the UI has to clear the bound key here too, otherwise the
-- old key keeps toggling the menu and the new key never takes over.
RegisterNUICallback("resetKeybind", function(_, cb)
    chosenKeyControl = nil
    chosenKeyName = nil
    print("[MAYSTRO] Keybind reset - waiting for a new key")
    if cb then cb("ok") end
end)

-- Disabled variants too: other scripts and GTA states switch keys off, and
-- control 21 only covers LEFT SHIFT, so RIGHT SHIFT would read as nothing.
local function held(controlId)
    return IsControlPressed(0, controlId) or IsDisabledControlPressed(0, controlId)
end

CreateThread(function()
    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local player = PlayerId()

        if Features.godmode then
            sleep = 0
            SetEntityInvincible(ped, true)
            SetPlayerInvincible(player, true)
            ClearPedBloodDamage(ped)
            SetEntityHealth(ped, 200)
        end
        if Features.superJump then
            sleep = 0
            SetSuperJumpThisFrame(player)
        end
        if Features.punch then
            sleep = 0
            SetPlayerMeleeWeaponDamageModifier(player, 100.0)
        end
        if Features.noclip then
            sleep = 0
            local x, y, z = table.unpack(GetEntityCoords(ped, true))
            local speed = (Features.noclipSpeed or 2) * 0.4
            -- SHIFT boosts and CTRL slows; neither touches altitude.
            if held(21) then speed = speed * 2.5 end
            if held(36) then speed = speed * 0.35 end
            local h = math.rad(GetGameplayCamRelativeHeading() + GetEntityHeading(ped))
            local p = math.rad(GetGameplayCamRelativePitch())
            local dx, dy, dz = 0.0, 0.0, 0.0
            -- W/S fly toward the camera, pitch included, so the view steers the flight.
            if held(32) then dx = dx - math.sin(h) * speed * math.cos(p); dy = dy + math.cos(h) * speed * math.cos(p); dz = dz + math.sin(p) * speed end
            if held(33) then dx = dx + math.sin(h) * speed * math.cos(p); dy = dy - math.cos(h) * speed * math.cos(p); dz = dz - math.sin(p) * speed end
            if held(34) then dx = dx - math.cos(h) * speed; dy = dy - math.sin(h) * speed end
            if held(35) then dx = dx + math.cos(h) * speed; dy = dy + math.sin(h) * speed end
            if held(172) or held(22) then dz = dz + speed end
            if held(173) then dz = dz - speed end
            SetEntityCoordsNoOffset(ped, x + dx, y + dy, z + dz, true, true, true)
        end

        Wait(sleep)
    end
end)

print("[MAYSTRO] Injected into resource VM!")
]=]

if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
    print("[MAYSTRO] Susano.InjectResource is unavailable in this environment")
    return
end

Susano.InjectResource("any", payload, Susano.NEW_THREAD)
print("[MAYSTRO] Injection queued")
