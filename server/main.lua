-- Rooms by code, like noted_chess, but the server owns the game: every move goes
-- through KBMatch.apply and clients only ever see KB.decode'd snapshots.
local rooms, membership, spectating = {}, {}, {} -- code -> room, player -> code, player -> code
local nicknames, nicknameChangedAt = {}, {}      -- license -> nickname, player -> os.time()
local serial = 0

local function newId()
    serial = serial + 1
    return ('phone:%d'):format(serial)
end

local function makeCode()
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    repeat
        local code = ''
        for _ = 1, Config.RoomCodeLength do
            local index = math.random(1, #chars)
            code = code .. chars:sub(index, index)
        end
        if not rooms[code] then return code end
    until false
end

local function license(player)
    for _, identifier in ipairs(GetPlayerIdentifiers(player) or {}) do
        if identifier:sub(1, 8) == 'license:' then return identifier end
    end
    return 'src:' .. tostring(player)
end

-- The character's first name (qbx_core), falling back to the account name.
local function characterName(player)
    local ok, result = pcall(function()
        local qb = exports.qbx_core:GetPlayer(player)
        return qb and qb.PlayerData and qb.PlayerData.charinfo and qb.PlayerData.charinfo.firstname
    end)
    if ok and type(result) == 'string' and result ~= '' then return result end
    return GetPlayerName(player) or ('Player ' .. player)
end

local function nickname(player)
    local key = license(player)
    if nicknames[key] == nil then
        local ok, stored = pcall(GetResourceKvpString, 'nickname:' .. key)
        nicknames[key] = ok and stored or false
    end
    return nicknames[key] or nil
end

local function playerName(player)
    return nickname(player) or characterName(player)
end

local function profile(player)
    return {
        name = characterName(player), nickname = nickname(player) or '',
        min = Config.Nickname.MinLength, max = Config.Nickname.MaxLength,
    }
end

local function cpuName()
    local names = Config.CpuNames
    if type(names) ~= 'table' or #names == 0 then return 'CPU' end
    return names[math.random(1, #names)]
end

-- Three sinks: the server console (kept in txAdmin's logs), logs/nicknames.log in this
-- resource, and ox_lib's logger, which forwards only when ox:logger and its key are set.
local function log(player, event, message, data)
    local line = ('[%s] %s: %s'):format(os.date('%Y-%m-%d %H:%M:%S'), event, message)
    print('[noted_knucklebones_phone] ' .. line)
    local resource = GetCurrentResourceName()
    local path = ('logs/%ss.log'):format(event)
    local existing = LoadResourceFile(resource, path) or ''
    SaveResourceFile(resource, path, existing .. line .. '\n', -1)
    if lib and lib.logger then
        pcall(lib.logger, player, event, 'noted_knucklebones_phone: ' .. message, data)
    end
end

local function snapshot(room, player)
    local match = room.match
    local names, ready = {}, {}
    for side = 0, 1 do
        names[side + 1] = match.seats[side] and match.seats[side].name or false
        ready[side + 1] = match.ready[side] == true
    end
    return {
        code = room.code, match = match.id, revision = match.revision, public = room.public == true,
        game = KB.decode(match.state), names = names, ready = ready,
        seat = KBMatch.seat(match, player), spectators = room.spectatorCount,
    }
end

local function audience(room)
    local list = {}
    for side = 0, 1 do
        local seat = room.match.seats[side]
        if seat and seat.id and not seat.ai then list[#list + 1] = seat.id end
    end
    for player in pairs(room.spectators) do list[#list + 1] = player end
    return list
end

local function send(player, action, data)
    TriggerClientEvent('kbphone:message', player, action, data)
end

local function publish(room)
    room.spectatorCount = 0
    for _ in pairs(room.spectators) do room.spectatorCount = room.spectatorCount + 1 end
    for _, player in ipairs(audience(room)) do send(player, 'update', snapshot(room, player)) end
end

local function closeRoom(room, message)
    for _, player in ipairs(audience(room)) do
        membership[player], spectating[player] = nil, nil
        send(player, 'closed', { code = room.code, message = message })
    end
    rooms[room.code] = nil
end

local changed

local function scheduleAi(room)
    local match = room.match
    local side = KBMatch.aiSide(match)
    if not side or KB.phase(match.state) ~= KB.PLAYING or KB.turn(match.state) ~= side then return end
    local revision = match.revision
    SetTimeout(Config.AiThinkTime, function()
        if rooms[room.code] ~= room or match.revision ~= revision then return end
        local request = { match = match.id, revision = revision, action = 'roll' }
        if KB.roll(match.state) > 0 then
            request.action, request.column = 'place', KBMatch.aiColumn(match.state, side, math.random)
        end
        local phase, turn = KB.phase(match.state), KB.turn(match.state)
        if KBMatch.apply(match, KBMatch.AI, match.seats[side].name, request, math.random, newId) then changed(room, phase, turn) end
    end)
end

function changed(room, oldPhase, oldTurn)
    local phase, turn = KB.phase(room.match.state), KB.turn(room.match.state)
    if phase == KB.PLAYING and (oldPhase ~= phase or oldTurn ~= turn) then
        room.turnStarted = os.time()
    elseif phase ~= KB.PLAYING then
        room.turnStarted = nil
    end
    publish(room)
    scheduleAi(room)
end

local function createRoom(player, public)
    if membership[player] then return nil, 'Leave your current game first.' end
    local room = { code = makeCode(), match = KBMatch.new(newId()), spectators = {}, spectatorCount = 0, public = public == true }
    rooms[room.code] = room
    return room
end

local function apply(room, player, request)
    local phase, turn = KB.phase(room.match.state), KB.turn(room.match.state)
    local ok, err = KBMatch.apply(room.match, player, playerName(player), request, math.random, newId)
    if ok then
        if request.action == 'ai' then
            -- The rules give the CPU a plain name; the app picks one from the configured list.
            local side = KBMatch.aiSide(room.match)
            if side then room.match.seats[side].name = cpuName() end
        end
        membership[player] = KBMatch.seat(room.match, player) ~= nil and room.code or nil
        changed(room, phase, turn)
    end
    return ok, err
end

local function fresh(room, action)
    return { match = room.match.id, revision = room.match.revision, action = action }
end

RegisterNetEvent('kbphone:create', function(public)
    local player = source
    local room, err = createRoom(player, public)
    if not room then send(player, 'error', { message = err }); return end
    apply(room, player, fresh(room, 'join'))
end)

-- CPU games are never listed: nobody can join them and there is little to watch.
RegisterNetEvent('kbphone:ai', function()
    local player = source
    local room, err = createRoom(player, false)
    if not room then send(player, 'error', { message = err }); return end
    apply(room, player, fresh(room, 'ai'))
end)

RegisterNetEvent('kbphone:join', function(code)
    local player = source
    local room = type(code) == 'string' and rooms[code:upper()]
    if not room then send(player, 'error', { message = 'No game with that code.' }); return end
    if membership[player] then send(player, 'error', { message = 'Leave your current game first.' }); return end
    local ok, err = apply(room, player, fresh(room, 'join'))
    if not ok then send(player, 'error', { message = err }) end
end)

RegisterNetEvent('kbphone:action', function(data)
    local player = source
    if type(data) ~= 'table' or type(data.action) ~= 'string' then return end
    local room = rooms[membership[player] or '']
    if not room then send(player, 'error', { message = 'You are not in a game.' }); return end
    local request = {
        match = data.match, revision = data.revision, action = data.action,
        column = math.tointeger(tonumber(data.column) or -1),
    }
    local ok, err = apply(room, player, request)
    if not ok then
        send(player, 'error', { message = err })
        send(player, 'update', snapshot(room, player))
    end
end)

local function leave(player, reason)
    local room = rooms[membership[player] or '']
    membership[player] = nil
    if not room then return end
    local match = room.match
    local side = KBMatch.seat(match, player)
    if side == nil then return end
    local other = match.seats[1 - side]
    local phase, turn = KB.phase(match.state), KB.turn(match.state)
    KBMatch.apply(match, player, '', fresh(room, 'leave'), math.random, newId)
    -- The leaver is no longer in the room's audience, so tell them directly.
    send(player, 'closed', { code = room.code })
    if not other or other.ai or not other.id then
        closeRoom(room, reason)
    else
        changed(room, phase, turn)
        send(other.id, 'notice', { message = reason })
    end
end

RegisterNetEvent('kbphone:leave', function()
    leave(source, 'Your opponent left the game.')
end)

-- Only public rooms are listed. Private rooms are reachable by code alone.
RegisterNetEvent('kbphone:rooms', function()
    local player = source
    local list = {}
    for code, room in pairs(rooms) do
        if room.public then
            local names = {}
            for side = 0, 1 do names[side + 1] = room.match.seats[side] and room.match.seats[side].name or false end
            list[#list + 1] = { code = code, names = names, phase = KB.phase(room.match.state), spectators = room.spectatorCount }
        end
    end
    table.sort(list, function(a, b)
        if a.phase ~= b.phase then return a.phase < b.phase end
        return a.code < b.code
    end)
    send(player, 'rooms', { rooms = list })
end)

RegisterNetEvent('kbphone:spectate', function(code)
    local player = source
    local room = type(code) == 'string' and rooms[code:upper()]
    if not room then send(player, 'error', { message = 'No game with that code.' }); return end
    local previous = rooms[spectating[player] or '']
    if previous and previous ~= room then previous.spectators[player] = nil; publish(previous) end
    room.spectators[player] = true
    spectating[player] = room.code
    publish(room)
end)

RegisterNetEvent('kbphone:stopSpectating', function()
    local player = source
    local room = rooms[spectating[player] or '']
    spectating[player] = nil
    if room then room.spectators[player] = nil; publish(room) end
end)

-- Nicknames: validated, rate limited, stored per licence, and every change is logged.
local function cleanNickname(raw)
    if type(raw) ~= 'string' then return nil, 'Enter a nickname.' end
    local name = raw:gsub('%s+', ' '):match('^%s*(.-)%s*$')
    if name == '' then return '' end -- clearing the nickname
    local rules = Config.Nickname
    if #name < rules.MinLength then return nil, ('Nicknames need at least %d characters.'):format(rules.MinLength) end
    if #name > rules.MaxLength then return nil, ('Nicknames can be at most %d characters.'):format(rules.MaxLength) end
    if not name:match(rules.Pattern) then return nil, 'Only letters, numbers, spaces, apostrophes and hyphens.' end
    return name
end

RegisterNetEvent('kbphone:nickname', function(raw)
    local player = source
    local now = os.time()
    if (nicknameChangedAt[player] or 0) + Config.Nickname.Cooldown > now then
        send(player, 'error', { message = 'Give it a moment before changing your nickname again.' }); return
    end
    local name, err = cleanNickname(raw)
    if not name then send(player, 'error', { message = err }); return end
    nicknameChangedAt[player] = now
    local key = license(player)
    local before = nickname(player) or ''
    nicknames[key] = name ~= '' and name or false
    pcall(SetResourceKvp, 'nickname:' .. key, name)
    log(player, 'nickname', ('%s (%s, %s) changed nickname "%s" -> "%s"'):format(characterName(player), key, GetPlayerName(player) or '?', before, name),
        { license = key, character = characterName(player), before = before, after = name })
    -- A seat already taken under the old name follows the change.
    local room = rooms[membership[player] or '']
    if room then
        local side = KBMatch.seat(room.match, player)
        if side ~= nil then room.match.seats[side].name = playerName(player); publish(room) end
    end
    send(player, 'profile', profile(player))
    send(player, 'notice', { message = name ~= '' and ('You now play as %s.'):format(name) or 'Nickname cleared.' })
end)

-- The UI asks for this when it mounts; the phone's iframe may not exist when events fire.
RegisterNetEvent('kbphone:refresh', function()
    local player = source
    local room = rooms[membership[player] or ''] or rooms[spectating[player] or '']
    send(player, 'profile', profile(player))
    send(player, 'update', room and snapshot(room, player) or false)
end)

AddEventHandler('playerDropped', function()
    local player = source
    local watched = rooms[spectating[player] or '']
    spectating[player] = nil
    nicknameChangedAt[player] = nil
    if watched then watched.spectators[player] = nil; publish(watched) end
    leave(player, 'Your opponent disconnected.')
end)

CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        for _, room in pairs(rooms) do
            if room.turnStarted and not KBMatch.aiSide(room.match) and now - room.turnStarted >= Config.TurnTimeout then
                local match = room.match
                match.state = KB.meta(match.state, 0, 1 - KB.turn(match.state), KB.FORFEIT)
                match.revision = match.revision + 1
                room.turnStarted = nil
                publish(room)
            end
        end
    end
end)
