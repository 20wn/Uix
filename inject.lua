-- MAYSTRO client loader (resource version, loaded by fxmanifest client_scripts).
-- Same Lua as the Susano payload so both entry points behave identically.

local isMenuVisible    = true
local duiObj           = nil
local txd              = nil
local txn              = nil
local chosenKeyControl = nil
local chosenKeyName    = nil
local spectating       = nil

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
            -- 2D draws stack in call order and FiveM has no layer/order native, so the
            -- menu is drawn from a thread created this frame: it resumes after the
            -- scripts already running and lands on top of their HUD and scaleforms.
            CreateThread(function()
                DrawSprite("maystro_txd", "maystro_txn", 0.5, 0.5, 1.0, 1.0, 0.0, 255, 255, 255, 255)
            end)

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

-- FiveM does not register every native in every build or realm, and calling a nil global
-- kills the thread that made the call, so the optional reads go through here.
local function try(fn, fallback, ...)
    if type(fn) ~= "function" then return fallback end
    local ok, value = pcall(fn, ...)
    if ok and value ~= nil then return value end
    return fallback
end

local HAS_PING = type(GetPlayerPing) == "function"

-- Vehicle class buckets used for the player-list icon.
local function playerKind(ped)
    if not ped or ped == 0 or not IsPedInAnyVehicle(ped, false) then
        return "foot"
    end
    local cls = GetVehicleClass(GetVehiclePedIsIn(ped, false))
    if cls == 8 then return "bike" end
    if cls == 14 then return "boat" end
    if cls == 15 or cls == 16 then return "air" end
    return "car"
end

-- GetPlayers hands back server IDs, but the PLAYER natives want a player index.
local function PedOf(src)
    local idx = GetPlayerFromServerId(src)
    if idx < 0 then return 0 end
    return GetPlayerPed(idx)
end

local function NameOf(src)
    local idx = GetPlayerFromServerId(src)
    if idx < 0 then return nil end
    return GetPlayerName(idx)
end

local function PingOf(src)
    local idx = GetPlayerFromServerId(src)
    if idx < 0 or not HAS_PING then return -1 end
    return try(GetPlayerPing, -1, idx)
end

local function BuildPlayerList()
    local list = {}
    local seen = {}
    local me = PlayerPedId()
    local mx, my, mz = table.unpack(GetEntityCoords(me, true))

    local function add(srv, ped)
        local streamed = srv and srv >= 0 and ped and ped ~= 0 and DoesEntityExist(ped)
        if srv == nil or srv < 0 or seen[srv] then return end
        seen[srv] = true

        local dist, kind = -1, "unknown"
        if streamed then
            local tx, ty, tz = table.unpack(GetEntityCoords(ped, true))
            dist = math.floor(GetDistanceBetweenCoords(mx, my, mz, tx, ty, tz, false))
            kind = playerKind(ped)
        end

        list[#list + 1] = {
            id   = srv,
            name = NameOf(srv) or ("ID " .. tostring(srv)),
            ping = PingOf(srv),
            kind = kind,
            dist = dist
        }
    end

    -- These are player indices, so their peds are guaranteed and carry a distance.
    for _, idx in ipairs(GetActivePlayers()) do
        add(tonumber(GetPlayerServerId(idx)), GetPlayerPed(idx))
    end

    -- GetPlayers is the whole server, so anyone outside our streaming range still gets a
    -- row; they simply have no ped, which shows as "?" instead of a distance. Some builds
    -- hand these back as strings, so tonumber keeps the IDs comparable.
    for _, srv in ipairs(GetPlayers()) do
        local asNum = tonumber(srv)
        if asNum then add(asNum, PedOf(asNum)) end
    end

    table.sort(list, function(a, b)
        if a.dist < 0 then return false end
        if b.dist < 0 then return true end
        return a.dist < b.dist
    end)
    return list
end

local lastPlayerCount = -1
local lastListError

local function PushPlayerList()
    if not duiObj then return end
    -- Never let one bad read take the push thread down with it; report it once instead.
    local ok, list = pcall(BuildPlayerList)
    if not ok then
        local msg = tostring(list)
        if msg ~= lastListError then
            lastListError = msg
            print("[MAYSTRO] player list failed: " .. msg)
        end
        return
    end
    if #list ~= lastPlayerCount then
        print(("[MAYSTRO] players pushed: %d (ping native: %s)"):format(#list, HAS_PING and "yes" or "missing"))
        lastPlayerCount = #list
    end
    SendDuiMessage(duiObj, json.encode({
        action   = "playerList",
        players  = list,
        self     = GetPlayerServerId(PlayerId()),
        spectate = spectating or 0
    }))
end

local function SetSpectate(target)
    local ped = PlayerPedId()
    if target then
        NetworkSetInSpectatorMode(true, PedOf(target))
        spectating = target
    else
        NetworkSetInSpectatorMode(false, ped)
        spectating = nil
    end
end

local function CopyOutfit(fromPed, toPed)
    for comp = 0, 11 do
        SetPedComponentVariation(toPed, comp,
            GetPedDrawableVariation(fromPed, comp),
            GetPedTextureVariation(fromPed, comp), 0)
    end
    for prop = 0, 9 do
        local idx = GetPedPropIndex(fromPed, prop)
        if idx >= 0 then
            SetPedPropIndex(toPed, prop, idx, GetPedPropTextureIndex(fromPed, prop), true)
        else
            ClearPedProp(toPed, prop)
        end
    end
    local blend = type(GetPedHeadBlendData) == "function" and GetPedHeadBlendData(fromPed) or nil
    if type(blend) == "table" and type(SetPedHeadBlendData) == "function" then
        SetPedHeadBlendData(toPed,
            blend.shapeFirst, blend.shapeSecond, blend.shapeThird,
            blend.skinFirst, blend.skinSecond, blend.skinThird,
            blend.shapeMix, blend.skinMix, blend.thirdMix, blend.isParent)
    end
    if type(GetPedHairColor) == "function" and type(SetPedHairColor) == "function" then
        local hair, highlights = GetPedHairColor(fromPed)
        SetPedHairColor(toPed, hair or 0, highlights or 0)
    end
end

RegisterNUICallback("serverAction", function(data, cb)
    if data.action == "refresh" then
        PushPlayerList()
    else
        local target = tonumber(data.id)
        local tped = target and PedOf(target) or 0

        if data.action == "spectate" then
            if spectating == target then
                SetSpectate(nil)
            elseif tped and tped ~= 0 then
                SetSpectate(target)
            end
        elseif data.action == "copyOutfit" then
            if tped and tped ~= 0 then
                local ok, err = pcall(CopyOutfit, tped, PlayerPedId())
                if not ok then print("[MAYSTRO] copy outfit failed: " .. tostring(err)) end
            end
        end

        PushPlayerList()
    end
    if cb then cb("ok") end
end)

CreateThread(function()
    while true do
        Wait(isMenuVisible and 500 or 2000)
        if duiObj and isMenuVisible then
            if spectating and PedOf(spectating) == 0 then
                SetSpectate(nil)
            end
            PushPlayerList()
        end
    end
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
        -- The menu owns W/S/A/D and the arrows while it is open, and spectator mode owns
        -- the camera, so flying is paused in both: otherwise scrolling the list drags the
        -- body up and down.
        if Features.noclip and not isMenuVisible and not spectating then
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
