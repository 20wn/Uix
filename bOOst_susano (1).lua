-- Susano loader: inject the original Lua UI into a FiveM resource VM.
-- The HTML/JS URL and original UI rendering are kept unchanged.

local payload = [=[
-- Starts closed. It used to start true because that was the only thing that made the draw
-- thread paint the keybind prompt, and the first press of a freshly bound key then CLOSED the
-- menu instead of opening it -- which looks like "one press does nothing, spamming opens it".
-- The prompt is painted by chosenKeyControl == nil now, so the flag can tell the truth.
local isMenuVisible    = false
local duiObj           = nil
local txd              = nil
local txn              = nil
local chosenKeyControl = nil
local chosenKeyName    = nil
local spectating       = nil
local lastToggleAt     = 0
-- Defined further down, but the thread that starts the UI already wants to call it.
local ScanDispatchScripts

-- The cache-buster is what guarantees a fresh push actually arrives, but a per-injection value
-- throws the page cache away every single time and that is where the slow start comes from. A
-- 5-minute bucket still beats githack's own staleness and lets quick re-injects load warm.
local webStamp = (type(GetCloudTimeAsInt) == "function")
    and math.floor(GetCloudTimeAsInt() / 300000)
    or math.floor(GetGameTimer() / 300000)
local WebURL = "https://raw.githack.com/20wn/Uix/main/index.html?v=" .. tostring(webStamp)

local Features = {
    godmode     = false,
    superJump   = false,
    invisible   = false,
    punch       = false,
    noclip      = false,
    noclipSpeed = 2,
    freecam     = false,
    freecamSpeed = 1,
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
        Wait(50)
    end

    local duiHandle = GetDuiHandle(duiObj)
    txd = CreateRuntimeTxd("maystro_txd")
    txn = CreateRuntimeTextureFromDuiHandle(txd, "maystro_txn", duiHandle)
    Wait(250)
    SendDuiMessage(duiObj, json.encode({ action = "setResource", name = GetCurrentResourceName() }))
    SendDuiMessage(duiObj, json.encode({ action = "showKeybind" }))
    -- The DUI page only owns a message listener once its own script has run, so a single early
    -- push can land on nothing -- and without setResource the page has no resource name to POST
    -- to, so every option it clicks silently does nothing. Re-pushing the name is harmless and
    -- removes the need to guess how long the page needs.
    CreateThread(function()
        for i = 1, 8 do
            Wait(600)
            if not duiObj then return end
            SendDuiMessage(duiObj, json.encode({ action = "setResource", name = GetCurrentResourceName() }))
        end
    end)
    print("[MAYSTRO] UI Loaded!")
    -- Says which natives this build registers, so a nil-native crash names itself here
    -- instead of showing up later as some other resource's script error.
    print(("[MAYSTRO] natives probe list: ping=%s getPlayers=%s activePlayers=%s serverId=%s fromServerId=%s exists=%s coords=%s class=%s"):format(
        type(GetPlayerPing), type(GetPlayers), type(GetActivePlayers), type(GetPlayerServerId),
        type(GetPlayerFromServerId), type(DoesEntityExist), type(GetEntityCoords), type(GetVehicleClass)))
    print(("[MAYSTRO] natives probe acts: spectator=%s headBlend=%s hair=%s component=%s"):format(
        type(NetworkSetInSpectatorMode), type(GetPedHeadBlendData), type(GetPedHairColor),
        type(SetPedComponentVariation)))
    print(("[MAYSTRO] natives probe look: citizen=%s faceFeature=%s overlayData=%s hairColor=%s eyes=%s palette=%s"):format(
        type(Citizen), type(GetPedFaceFeature), type(GetPedHeadOverlayData),
        type(GetPedHairColor), type(GetPedEyeColor), type(GetPedPaletteVariation)))
end

-- FiveM has no draw-order native: 2D calls stack in the order the threads that make them
-- resume, and threads waiting on Wait(0) resume in creation order. So the menu draws from the
-- newest thread in the VM, which puts it above every overlay started before it. Creating that
-- thread when the menu opens is what keeps it on top; wrapping the draw in CreateThread inside
-- the frame does nothing, because a new thread runs immediately until its first Wait.
local drawGen = 0

local function StartDrawThread()
    drawGen = drawGen + 1
    local myGen = drawGen

    CreateThread(function()
        while true do
            Wait(0)
            -- Checked right after the wait: a thread that only finds out at the loop top
            -- would still draw one more frame on top of the newer one.
            if drawGen ~= myGen then return end
            if not (txd and txn) then goto continue end
            -- The page shows either the menu or the "press a key" prompt, and a prompt nothing
            -- ever draws is a prompt nobody sees: right after an injection he would be pressing
            -- keys with no feedback at all and conclude the UI is broken.
            if not (isMenuVisible or chosenKeyControl == nil) then goto continue end

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

            ::continue::
        end
    end)
end

local function ToggleMenu(state)
    if state == nil then
        isMenuVisible = not isMenuVisible
    else
        isMenuVisible = state
    end
    SetNuiFocus(false, false)
    -- Opening restarts the draw thread so this menu becomes the newest one in the VM.
    if isMenuVisible then StartDrawThread() end
    if duiObj then
        -- openMenu/closeMenu set the page's state instead of flipping it, so a DUI still serving
        -- an older cached copy cannot end up hidden while the game is drawing it (that reads as
        -- "the menu never opens").
        SendDuiMessage(duiObj, json.encode({ action = isMenuVisible and "openMenu" or "closeMenu" }))
    end
    print(isMenuVisible and "[MAYSTRO] Menu Opened" or "[MAYSTRO] Menu Closed")
end

CreateThread(function()
    InitUI()
    SetNuiFocus(false, false)
    StartDrawThread()
    -- The resource list is only trustworthy once the session is up, and the responder rows have
    -- to be built from what this server actually runs.
    Wait(3000)
    ScanDispatchScripts()
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
                    -- No Wait here: a sleeping loop misses every press that happens while it is
                    -- asleep, and a missed press is the difference between "one tap opens it" and
                    -- "I have to hammer the key".
                    break
                end
            end
        else
            -- Debounce is a timestamp, not a sleep, so the next press is always seen on the
            -- frame it arrives.
            local now = GetGameTimer()
            if now - lastToggleAt > 120 then
                if IsDisabledControlJustPressed(0, chosenKeyControl) or IsControlJustPressed(0, chosenKeyControl) then
                    lastToggleAt = now
                    ToggleMenu()
                end
            end

            -- Arrows only: W/S/A/D belong to walking and noclip, so the menu must not
            -- answer to them.
            if isMenuVisible then
                if IsDisabledControlJustPressed(0, 172) then
                    SendDuiMessage(duiObj, json.encode({ action = "keydown", key = "ArrowUp" }))
                end
                if IsDisabledControlJustPressed(0, 173) then
                    SendDuiMessage(duiObj, json.encode({ action = "keydown", key = "ArrowDown" }))
                end
                if IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 18) then
                    SendDuiMessage(duiObj, json.encode({ action = "keydown", key = "Enter" }))
                end
                if IsDisabledControlJustPressed(0, 194) then
                    SendDuiMessage(duiObj, json.encode({ action = "keydown", key = "Backspace" }))
                end
                if IsDisabledControlJustPressed(0, 174) then
                    SendDuiMessage(duiObj, json.encode({ action = "keydown", key = "ArrowLeft" }))
                end
                if IsDisabledControlJustPressed(0, 175) then
                    SendDuiMessage(duiObj, json.encode({ action = "keydown", key = "ArrowRight" }))
                end
            end
        end

        ::continue::
    end
end)

-- Both flying modes stop the body from behaving like a ped: noclip also drops collision so the
-- world cannot push him back, and the freeze is shared so turning one on while the other is
-- already on cannot leave the body frozen after both are off.
local function SyncFlyFreeze()
    local ped = PlayerPedId()
    local flying = (Features.noclip or Features.freecam) == true
    SetEntityCollision(ped, not Features.noclip, not Features.noclip)
    FreezeEntityPosition(ped, flying)
end

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
        SyncFlyFreeze()
    elseif id == "freecam" then
        Features.freecam = enabled
        if val then Features.freecamSpeed = val end
        SyncFlyFreeze()
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
local HAS_SERVER_LIST = type(GetPlayers) == "function"

-- Responder/dispatch: the rows cannot be written against a guessed script, because every server
-- runs a different one and calling an export that is not there kills the thread that tried it.
-- So this first finds what is actually running and prints the export names it offers; the calls
-- then go to those, and a server with nothing installed gets one honest line instead of a menu
-- full of buttons that pretend to work.
local DispatchWords = { "responder", "dispatch", "911", "mdt", "cad", "alert", "callout" }
local DispatchGuesses = {
    "responder", "ps-dispatch", "qb-dispatch", "xs-dispatch", "ls-dispatch-esx",
    "simple911", "Simple911_v2", "dispatch", "qb-cad", "lc-cad", "mdt"
}

local function isDispatchName(name)
    local lower = tostring(name):lower()
    for _, word in ipairs(DispatchWords) do
        if lower:find(word, 1, true) then return true end
    end
    return false
end

local function exportNamesOf(resource)
    if type(GetResourceExports) ~= "function" then return nil end
    local ok, exp = pcall(GetResourceExports, resource)
    if not ok or type(exp) ~= "table" then return nil end
    local names = {}
    for key, value in pairs(exp) do
        if type(key) == "string" and key ~= "" then
            names[#names + 1] = key
        elseif type(value) == "string" and value ~= "" then
            names[#names + 1] = value
        end
    end
    table.sort(names)
    return names
end

ScanDispatchScripts = function()
    local candidates = {}
    if type(GetAllClientResources) == "function" then
        local ok, list = pcall(GetAllClientResources)
        if ok and type(list) == "table" then
            for _, name in ipairs(list) do
                if isDispatchName(name) then candidates[#candidates + 1] = name end
            end
        end
    end
    if #candidates == 0 then
        for _, name in ipairs(DispatchGuesses) do candidates[#candidates + 1] = name end
    end

    local found, states = {}, {}
    for _, name in ipairs(candidates) do
        local state = "unknown"
        if type(GetResourceState) == "function" then
            state = tostring(try(GetResourceState, "", name))
        end
        states[name] = state
        if state == "started" then
            local exports = exportNamesOf(name)
            found[#found + 1] = { name = name, exports = exports }
            print(("[MAYSTRO] dispatch script: %s exports=%s"):format(
                name, exports and (#exports > 0 and table.concat(exports, ", ") or "none") or "unreadable"))
        end
    end
    if #found == 0 then
        print(("[MAYSTRO] dispatch scan: nothing started (list=%s state=%s exports=%s, probed %d names)")
            :format(type(GetAllClientResources) == "function" and "yes" or "no",
                type(GetResourceState) == "function" and "yes" or "no",
                type(GetResourceExports) == "function" and "yes" or "no", #candidates))
    end
    return found
end

-- Server ID -> the player index this client knows it by. Caching it while listing means an
-- action never has to convert again, which matters on builds where the converter is absent.
local indexById = {}

local function IndexOf(src)
    if indexById[src] then return indexById[src] end
    return try(GetPlayerFromServerId, -1, src)
end

-- The PLAYER natives want a player index, not the server ID GetPlayers hands back.
local function PedOf(src)
    local idx = IndexOf(src)
    if idx < 0 then return 0 end
    return try(GetPlayerPed, 0, idx)
end

local function NameOf(src)
    local idx = IndexOf(src)
    if idx < 0 then return nil end
    return try(GetPlayerName, nil, idx)
end

local function PingOf(src)
    local idx = IndexOf(src)
    if idx < 0 or not HAS_PING then return -1 end
    return try(GetPlayerPing, -1, idx)
end

-- The local player's server ID, or this index if the build has no converter.
local function MyServerId()
    local idx = try(PlayerId, 0)
    return tonumber(try(GetPlayerServerId, nil, idx)) or idx
end

-- A nonzero ped is enough when DoesEntityExist is one of the natives this build lacks.
local function pedExists(ped)
    if not ped or ped == 0 then return false end
    if type(DoesEntityExist) ~= "function" then return true end
    return try(DoesEntityExist, true, ped) and true or false
end

-- Vehicle class buckets used for the player-list icon.
local function playerKind(ped)
    if not pedExists(ped) then return "foot" end
    if not try(IsPedInAnyVehicle, false, ped, false) then return "foot" end
    local cls = try(GetVehicleClass, -1, try(GetVehiclePedIsIn, 0, ped, false))
    if cls == 8 then return "bike" end
    if cls == 14 then return "boat" end
    if cls == 15 or cls == 16 then return "air" end
    return "car"
end

-- Coords come back as three values, so they need their own guarded read.
local function coordsOf(ent)
    if type(GetEntityCoords) ~= "function" then return nil end
    local ok, x, y, z = pcall(GetEntityCoords, ent, true)
    if not ok or x == nil then return nil end
    return x, y, z
end

local function BuildPlayerList()
    local list = {}
    local seen = {}
    local me = try(PlayerPedId, 0)
    local mx, my, mz = coordsOf(me)

    local function add(srv, ped, idx)
        if srv == nil or srv < 0 or seen[srv] then return end
        seen[srv] = true
        if idx then indexById[srv] = tonumber(idx) or idx end

        local streamed = pedExists(ped)
        local dist, kind = -1, "unknown"
        if streamed then
            kind = playerKind(ped)
            local tx, ty, tz = coordsOf(ped)
            if tx and mx then
                dist = math.floor(try(GetDistanceBetweenCoords, -1, mx, my, mz, tx, ty, tz, false) or -1)
            end
        end

        list[#list + 1] = {
            id   = srv,
            name = NameOf(srv) or ("ID " .. tostring(srv)),
            ping = PingOf(srv),
            kind = kind,
            dist = dist
        }
    end

    -- Player indices carry real peds, so they are the rows that can show a distance. If
    -- GetActivePlayers is missing too, the plain slot scan uses only stock GTA natives.
    if type(GetActivePlayers) == "function" then
        for _, idx in ipairs(try(GetActivePlayers, {}) or {}) do
            add(tonumber(try(GetPlayerServerId, nil, idx)) or idx, try(GetPlayerPed, 0, idx), idx)
        end
    else
        for idx = 0, 31 do
            if try(NetworkIsPlayerActive, false, idx) then
                add(tonumber(try(GetPlayerServerId, nil, idx)) or idx, try(GetPlayerPed, 0, idx), idx)
            end
        end
    end

    -- GetPlayers lists the whole server, so anyone outside our streaming range still gets a
    -- row; they simply have no ped, which shows as "?" instead of a distance.
    if HAS_SERVER_LIST then
        for _, srv in ipairs(try(GetPlayers, {}) or {}) do
            local asNum = tonumber(srv)
            if asNum then add(asNum, PedOf(asNum)) end
        end
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
        print(("[MAYSTRO] players pushed: %d (ping=%s serverList=%s)"):format(#list,
            HAS_PING and "yes" or "missing", HAS_SERVER_LIST and "yes" or "missing"))
        lastPlayerCount = #list
    end
    SendDuiMessage(duiObj, json.encode({
        action   = "playerList",
        players  = list,
        self     = MyServerId(),
        spectate = spectating or 0
    }))
end

-- Spectating needs both the native and a real ped for the target; without either the toggle
-- says so instead of throwing inside the NUI callback.
local function SetSpectate(target)
    if type(NetworkSetInSpectatorMode) ~= "function" then
        print("[MAYSTRO] spectate unavailable: NetworkSetInSpectatorMode is not registered")
        return
    end
    if target then
        local ped = PedOf(target)
        if not pedExists(ped) then return end
        pcall(NetworkSetInSpectatorMode, true, ped)
        spectating = target
    else
        pcall(NetworkSetInSpectatorMode, false, try(PlayerPedId, 0))
        spectating = nil
    end
end

-- Reading a whole character out of someone else's ped needs the CFX appearance natives, and this
-- VM is Susano's, so every one of them is optional: what is missing is skipped and named in the
-- report line instead of killing the copy halfway through.
local COMPONENT_IDS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
local PROP_IDS      = { 0, 1, 2, 6, 7 }
local FACE_FEATURE_COUNT = 20
local HEAD_OVERLAY_COUNT = 12
-- makeUp, blush and lipstick pick their colour out of a different palette than the rest.
local OVERLAY_PALETTE_2 = { [4] = true, [5] = true, [8] = true }

local function tofloat(value) return (tonumber(value) or 0) + 0.0 end

local function hashOf(name) return try(GetHashKey, 0, name) end

local function isFreemode(ped)
    local model = try(GetEntityModel, 0, ped)
    return model == hashOf("mp_m_freemode_01") or model == hashOf("mp_f_freemode_01")
end

-- GET_PED_HEAD_BLEND_DATA fills a padded struct, which Lua cannot hand over as a pointer, so the
-- read goes through Citizen's out-parameter helpers.
local function readHeadBlend(ped)
    if type(Citizen) ~= "table" or type(Citizen.InvokeNative) ~= "function"
        or type(Citizen.PointerValueIntInitialized) ~= "function"
        or type(Citizen.PointerValueFloatInitialized) ~= "function" then
        return nil
    end

    local pi, pf = Citizen.PointerValueIntInitialized, Citizen.PointerValueFloatInitialized
    local ok, shapeFirst, shapeSecond, shapeThird, skinFirst, skinSecond, skinThird, shapeMix, skinMix, thirdMix =
        pcall(Citizen.InvokeNative, 0x2746BD9D88C5C5D0, ped,
            pi(0), pi(0), pi(0), pi(0), pi(0), pi(0), pf(0), pf(0), pf(0))
    if not ok then return nil end

    local function mix(value)
        value = tonumber(value) or 0
        if value < 0 then value = 0 elseif value > 1 then value = 1 end
        return value
    end

    return {
        tonumber(shapeFirst) or 0, tonumber(shapeSecond) or 0, tonumber(shapeThird) or 0,
        tonumber(skinFirst) or 0, tonumber(skinSecond) or 0, tonumber(skinThird) or 0,
        mix(shapeMix), mix(skinMix), mix(thirdMix)
    }
end

local function CopyHead(fromPed, toPed, targetIndex, rep)
    if isFreemode(toPed) then
        local blend = readHeadBlend(fromPed)
        if blend and type(SetPedHeadBlendData) == "function" then
            SetPedHeadBlendData(toPed, blend[1], blend[2], blend[3], blend[4], blend[5], blend[6],
                tofloat(blend[7]), tofloat(blend[8]), tofloat(blend[9]), false)
            rep.blend = "ok"
        elseif targetIndex and targetIndex >= 0
            and type(NetworkApplyCachedPlayerHeadBlendData) == "function" then
            -- When the blend cannot be read out of the ped, the game still holds the face of every
            -- player in the session, so the copy comes from that cache instead.
            if try(NetworkApplyCachedPlayerHeadBlendData, false, toPed, targetIndex) then
                rep.blend = "cached"
            end
        end

        if type(GetPedFaceFeature) == "function" and type(SetPedFaceFeature) == "function" then
            for index = 0, FACE_FEATURE_COUNT - 1 do
                SetPedFaceFeature(toPed, index, tofloat(GetPedFaceFeature(fromPed, index)))
            end
            rep.face = "ok"
        end

        if type(GetPedHeadOverlayData) == "function" then
            for index = 0, HEAD_OVERLAY_COUNT - 1 do
                local _, value, _, firstColor, secondColor, opacity = GetPedHeadOverlayData(fromPed, index)
                value = tonumber(value) or 255
                if value == 255 then
                    try(SetPedHeadOverlay, nil, toPed, index, 0, 0.0)
                else
                    try(SetPedHeadOverlay, nil, toPed, index, value, tofloat(opacity))
                    if type(SetPedHeadOverlayColor) == "function" then
                        try(SetPedHeadOverlayColor, nil, toPed, index,
                            OVERLAY_PALETTE_2[index] and 2 or 1,
                            tonumber(firstColor) or 0, tonumber(secondColor) or 0)
                    end
                end
            end
            rep.overlays = "ok"
        end
    end

    local hairStyle = try(GetPedDrawableVariation, -1, fromPed, 2)
    if hairStyle and hairStyle >= 0 then
        try(SetPedComponentVariation, nil, toPed, 2, hairStyle,
            try(GetPedTextureVariation, 0, fromPed, 2) or 0, 0)
        rep.hair = "style"
    end

    if type(GetPedHairColor) == "function" and type(SetPedHairColor) == "function" then
        local color = math.max(0, try(GetPedHairColor, -1, fromPed) or -1)
        local highlight = math.max(0, try(GetPedHairHighlightColor, -1, fromPed) or -1)
        try(SetPedHairColor, nil, toPed, color, highlight)
        rep.hair = "ok"
    end

    if type(GetPedEyeColor) == "function" and type(SetPedEyeColor) == "function" then
        try(SetPedEyeColor, nil, toPed, math.max(0, try(GetPedEyeColor, -1, fromPed) or -1))
        rep.eyes = "ok"
    end
end

local function CopyClothes(fromPed, toPed, rep)
    local freemode = isFreemode(toPed)

    for _, component in ipairs(COMPONENT_IDS) do
        -- Face and hair on a freemode character belong to the blend and overlay data; writing a
        -- drawable over them there resets the face that was just copied.
        if not (freemode and (component == 0 or component == 2)) then
            local drawable = try(GetPedDrawableVariation, -1, fromPed, component)
            if drawable and drawable >= 0 then
                SetPedComponentVariation(toPed, component, drawable,
                    try(GetPedTextureVariation, 0, fromPed, component) or 0,
                    try(GetPedPaletteVariation, 0, fromPed, component) or 0)
                rep.clothes = rep.clothes + 1
            end
        end
    end

    for _, prop in ipairs(PROP_IDS) do
        local drawable = try(GetPedPropIndex, -1, fromPed, prop)
        if drawable and drawable >= 0 then
            try(SetPedPropIndex, nil, toPed, prop, drawable,
                try(GetPedPropTextureIndex, 0, fromPed, prop) or 0, true)
            rep.props = rep.props + 1
        else
            try(ClearPedProp, nil, toPed, prop)
        end
    end
end

-- SetPlayerModel throws away the current ped and builds a new one, so the handle is re-read after
-- the swap and the seat is re-taken if he was riding something.
local function CopyCharacter(fromPed, src)
    local rep = { model = "same", blend = "no", face = "no", overlays = "no",
                  hair = "no", eyes = "no", clothes = 0, props = 0 }
    if not pedExists(fromPed) then return rep end

    local mine = PlayerPedId()
    local fromModel = try(GetEntityModel, 0, fromPed)
    local myModel = try(GetEntityModel, 0, mine)

    if fromModel and fromModel ~= myModel and try(IsModelInCdimage, false, fromModel) then
        local veh = try(GetVehiclePedIsIn, 0, mine, false)
        local seat
        if veh and veh > 0 then
            for candidate = -1, 3 do
                if try(GetPedInVehicleSeat, 0, veh, candidate) == mine then
                    seat = candidate
                    break
                end
            end
        end

        RequestModel(fromModel)
        local deadline = GetGameTimer() + 5000
        while not try(HasModelLoaded, false, fromModel) and GetGameTimer() < deadline do
            Wait(0)
        end

        if try(HasModelLoaded, false, fromModel) then
            SetPlayerModel(PlayerId(), fromModel)
            SetModelAsNoLongerNeeded(fromModel)
            Wait(150)
            mine = PlayerPedId()
            if isFreemode(mine) then
                try(SetPedDefaultComponentVariation, nil, mine)
            end
            if veh and veh > 0 and seat then
                try(SetPedIntoVehicle, nil, mine, veh, seat)
            end
            rep.model = "swapped"
        else
            rep.model = "load timeout"
        end
    end

    local targetIndex = src and IndexOf(src) or nil
    if targetIndex and targetIndex < 0 then targetIndex = nil end

    CopyHead(fromPed, mine, targetIndex, rep)
    CopyClothes(fromPed, mine, rep)
    return rep
end

RegisterNUICallback("serverAction", function(data, cb)
    if data.action == "refresh" then
        PushPlayerList()
    elseif data.action == "responderScan" then
        CreateThread(function() ScanDispatchScripts() end)
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
            if pedExists(tped) then
                -- The model swap waits for streaming, so the copy runs on its own thread and
                -- reports which parts this build could actually read.
                CreateThread(function()
                    local ok, rep = pcall(CopyCharacter, tped, target)
                    if ok then
                        print(("[MAYSTRO] character copied: model=%s blend=%s face=%s overlays=%s hair=%s eyes=%s clothes=%d props=%d"):format(
                            rep.model, rep.blend, rep.face, rep.overlays, rep.hair, rep.eyes, rep.clothes, rep.props))
                    else
                        print("[MAYSTRO] copy character failed: " .. tostring(rep))
                    end
                end)
            end
        elseif data.action == "teleport" then
            local tx, ty, tz
            if pedExists(tped) then tx, ty, tz = coordsOf(tped) end
            if tx then
                -- Driving means the car travels with him, so the vehicle is the entity to move.
                local mine = PlayerPedId()
                local veh = try(GetVehiclePedIsIn, 0, mine, false)
                local ent = (veh and veh > 0) and veh or mine
                local ok, err = pcall(SetEntityCoords, ent, tx, ty, tz, false, false, false, true)
                if not ok then print("[MAYSTRO] teleport failed: " .. tostring(err)) end
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

-- The arrows navigate the menu while it is open, so they only fly when it is closed. W/S/A/D,
-- SPACE and SHIFT are not menu keys and fly in both states. This replaces "no flying while the
-- menu is open", which was the trap that made noclip look dead: switching it on inside the menu
-- and then pressing a key moved nothing at all.
local ArrowKey = { [172] = true, [173] = true, [174] = true, [175] = true }
local function flyKey(controlId)
    if isMenuVisible and ArrowKey[controlId] then return false end
    return held(controlId)
end

-- One direction for both flying modes: h and p are the radian heading and pitch of whatever the
-- view owns, so the camera always steers. SPACE rises, SHIFT or LEFT CTRL sinks.
local function flyVector(h, p, speed)
    local dx, dy, dz = 0.0, 0.0, 0.0
    if flyKey(32) or flyKey(172) then
        dx = dx - math.sin(h) * speed * math.cos(p)
        dy = dy + math.cos(h) * speed * math.cos(p)
        dz = dz + math.sin(p) * speed
    end
    if flyKey(33) or flyKey(173) then
        dx = dx + math.sin(h) * speed * math.cos(p)
        dy = dy - math.cos(h) * speed * math.cos(p)
        dz = dz - math.sin(p) * speed
    end
    if flyKey(34) or flyKey(174) then
        dx = dx - math.cos(h) * speed
        dy = dy - math.sin(h) * speed
    end
    if flyKey(35) or flyKey(175) then
        dx = dx + math.cos(h) * speed
        dy = dy + math.sin(h) * speed
    end
    if flyKey(22) then dz = dz + speed end
    if flyKey(21) or flyKey(36) then dz = dz - speed end
    return dx, dy, dz
end

local freecam = nil
local warnedNoCamNatives = false

local function StopFreecam()
    if not freecam then return end
    try(RenderScriptCams, nil, false, true, 400, true, false)
    try(DestroyCam, nil, freecam, false)
    freecam = nil
    SyncFlyFreeze()
    print("[MAYSTRO] Freecam off")
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

        -- Spectator mode owns the camera, so it takes the view away from both flying modes; the
        -- freecam has to hand it back before anything else runs.
        if not Features.freecam or spectating then StopFreecam() end

        if spectating then
            -- the spectator camera drives itself
        elseif Features.freecam then
            sleep = 0
            if not freecam then
                local from = try(GetGameplayCamCoord, nil)
                local rot = try(GetGameplayCamRot, nil, 2)
                if type(CreateCamWithParams) ~= "function" or not from or not rot then
                    if not warnedNoCamNatives then
                        warnedNoCamNatives = true
                        print("[MAYSTRO] cam natives unavailable - freecam disabled")
                    end
                    Features.freecam = false
                else
                    freecam = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA",
                        from[1], from[2], from[3], rot[1], 0.0, rot[3], 55.0, true, 2)
                    try(SetCamAffectsAiming, nil, freecam, true)
                    SyncFlyFreeze()
                    print("[MAYSTRO] Freecam on")
                end
            end

            if freecam then
                local rot = try(GetCamRot, nil, freecam, 2)
                local pos = try(GetCamCoord, nil, freecam)
                if rot and pos then
                    -- Mouse look: control 1 is left/right, 2 is up/down. Pitch is clamped so the
                    -- camera cannot flip over, which would invert the movement axes.
                    local mx = try(GetDisabledControlNormal, 0, 0, 1)
                    local my = try(GetDisabledControlNormal, 0, 0, 2)
                    local rx = math.max(-89.0, math.min(89.0, rot[1] + my * 4.0))
                    local rz = (rot[3] - mx * 4.0) % 360.0
                    try(SetCamRot, nil, freecam, rx, 0.0, rz, 2)
                    local speed = (Features.freecamSpeed or 1) * 0.5
                    local dx, dy, dz = flyVector(math.rad(rz), math.rad(-rx), speed)
                    try(SetCamCoord, nil, freecam, pos[1] + dx, pos[2] + dy, pos[3] + dz)
                end
                try(RenderScriptCams, nil, true, false, 0, true, false)
            end
        elseif Features.noclip then
            sleep = 0
            local x, y, z = table.unpack(GetEntityCoords(ped, true))
            local speed = (Features.noclipSpeed or 2) * 0.4
            local h = math.rad(GetGameplayCamRelativeHeading() + GetEntityHeading(ped))
            local p = math.rad(GetGameplayCamRelativePitch())
            local dx, dy, dz = flyVector(h, p, speed)
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
