-- Room flow through the real server script with stubbed natives.
dofile('config.lua')
local events, handlers, sent, timers, threads = {}, {}, {}, {}, {}
function RegisterNetEvent(name, fn) events[name] = fn end
function AddEventHandler(name, fn) handlers[name] = fn end
function TriggerClientEvent(name, player, ...) sent[#sent + 1] = { name = name, player = player, args = { ... } } end
function SetTimeout(_, fn) timers[#timers + 1] = fn end
function CreateThread(fn) threads[#threads + 1] = coroutine.create(fn) end
function Wait() coroutine.yield() end
function GetPlayerName(player) return 'P' .. player end
function GetPlayerIdentifiers(player) return { 'license:lic' .. player } end
-- qbx_core: every player is a character whose first name is Char<id>
exports = setmetatable({}, { __index = function() return { GetPlayer = function(_, src)
    return { PlayerData = { charinfo = { firstname = 'Char' .. src } } }
end } end })
local kvp = {}
function SetResourceKvp(key, value) kvp[key] = value end
function GetResourceKvpString(key) return kvp[key] end
local files = {}
function GetCurrentResourceName() return 'noted_knucklebones_phone' end
function LoadResourceFile(_, path) return files[path] end
function SaveResourceFile(_, path, data) files[path] = data; return true end
local logged = {}
lib = { logger = function(src, event, message, data) logged[#logged + 1] = { src = src, event = event, message = message, data = data } end }
local printed = {}
local rawprint = print
function print(...) printed[#printed + 1] = table.concat({ ... }, ' ') end
math.randomseed(4242)
dofile('server/main.lua')

local function fire(name, player, ...)
    source = player
    sent = {}
    events[name](...)
end
local function last(player, action)
    for index = #sent, 1, -1 do
        local message = sent[index]
        if message.name == 'kbphone:message' and message.player == player and message.args[1] == action then
            return message.args[2]
        end
    end
end
local function runAi()
    for _ = 1, 50 do
        local timer = table.remove(timers, 1)
        if not timer then return end
        timer()
    end
    error('CPU timers did not settle')
end

-- Create (private), join by code, play one exchange, leave.
fire('kbphone:create', 1, false)
local view = assert(last(1, 'update'), 'creator gets a snapshot')
assert(view.seat == 0 and view.game.phase == 0 and #view.code == Config.RoomCodeLength, 'creator waits in seat A')
assert(view.public == false and view.names[1] == 'Char1', 'private room, seat named after the character')
assert(last(1, 'profile') == nil, 'profile only arrives on refresh and nickname changes')
fire('kbphone:rooms', 3)
assert(#last(3, 'rooms').rooms == 0, 'private rooms are not listed')
fire('kbphone:join', 2, 'NOPE')
assert(last(2, 'error'), 'bad code rejected')
fire('kbphone:join', 2, view.code:lower())
local joined = assert(last(2, 'update'), 'joiner gets a snapshot')
assert(joined.seat == 1 and joined.game.phase == 1, 'joining starts the game')
assert(last(1, 'update').game.phase == 1, 'creator sees the start')
fire('kbphone:create', 2)
assert(last(2, 'error'), 'cannot open a second room while seated')
local turn = joined.game.turn + 1
fire('kbphone:action', 3 - turn, { action = 'roll', match = joined.match, revision = joined.revision })
assert(last(3 - turn, 'error'), 'off-turn roll rejected')
fire('kbphone:action', turn, { action = 'roll', match = joined.match, revision = joined.revision })
local rolled = assert(last(turn, 'update'))
assert(rolled.game.roll > 0 and rolled.revision == joined.revision + 1, 'roll accepted')
fire('kbphone:action', turn, { action = 'roll', match = joined.match, revision = joined.revision })
assert(last(turn, 'error'), 'stale revision rejected')
fire('kbphone:action', turn, { action = 'place', column = 2, match = rolled.match, revision = rolled.revision })
local placed = assert(last(turn, 'update'))
assert(placed.game.sides[turn].columns[2][1] == rolled.game.roll, 'placed die lands in lane 2')
assert(placed.game.turn == 2 - turn, 'turn passes')

-- Spectators can still watch a private game by code; a public room is listed.
fire('kbphone:create', 3, true)
local open = assert(last(3, 'update'))
assert(open.public == true, 'public room')
fire('kbphone:rooms', 4)
local rooms = assert(last(4, 'rooms')).rooms
assert(#rooms == 1 and rooms[1].code == open.code and rooms[1].phase == 0 and rooms[1].names[1] == 'Char3', 'only the public room is listed')
fire('kbphone:leave', 3)
fire('kbphone:spectate', 3, view.code)
local watched = assert(last(3, 'update'))
assert(watched.seat == nil and watched.spectators == 1, 'spectator snapshot')
fire('kbphone:leave', 1)
assert(last(1, 'closed'), 'the leaver is sent back to the lobby')
assert(last(2, 'update').game.phase == 3 and last(2, 'notice'), 'leaving forfeits and tells the opponent')
assert(last(3, 'update').game.phase == 3, 'spectator sees the forfeit')
fire('kbphone:leave', 2)
assert(last(3, 'closed'), 'empty room closes for spectators')
fire('kbphone:refresh', 2)
assert(last(2, 'update') == false, 'no game after leaving')

-- Cancelling an empty waiting room closes it and tells the creator.
fire('kbphone:create', 4)
local waiting = assert(last(4, 'update'))
fire('kbphone:leave', 4)
assert(last(4, 'closed'), 'cancel from the waiting screen returns to the lobby')
fire('kbphone:join', 5, waiting.code)
assert(last(5, 'error'), 'cancelled room is gone')

-- CPU game: the server plays the other seat on timers until the game finishes.
fire('kbphone:ai', 1)
local game = assert(last(1, 'update'))
local cpu = game.names[2 - game.seat]
local known = false
for _, name in ipairs(Config.CpuNames) do if name == cpu then known = true end end
assert(game.seat ~= nil and game.game.phase == 1 and known, 'CPU game starts at once with a configured name: ' .. tostring(cpu))
fire('kbphone:rooms', 2)
assert(#last(2, 'rooms').rooms == 0, 'CPU games are never listed')
runAi()
local moves = 0
while true do
    fire('kbphone:refresh', 1)
    game = last(1, 'update')
    if game.game.phase ~= 1 then break end
    moves = moves + 1
    assert(moves < 40, 'CPU game did not finish')
    assert(game.game.turn == game.seat and game.game.roll == 0, 'CPU hands the turn back')
    fire('kbphone:action', 1, { action = 'roll', match = game.match, revision = game.revision })
    game = last(1, 'update')
    local column
    for c = 1, 3 do if game.game.sides[game.seat + 1].columns[c][3] == 0 then column = c; break end end
    fire('kbphone:action', 1, { action = 'place', column = column, match = game.match, revision = game.revision })
    runAi()
end
assert(game.game.phase == 2, 'CPU game finishes')
fire('kbphone:action', 1, { action = 'rematch', match = game.match, revision = game.revision })
assert(last(1, 'update').game.phase == 1, 'rematch against the CPU starts at once')
source = 1
handlers.playerDropped()
fire('kbphone:refresh', 1)
assert(last(1, 'update') == false, 'disconnect closes the CPU game')
-- Nicknames: validated, logged, persisted, and reflected in seats.
fire('kbphone:refresh', 6)
local me = assert(last(6, 'profile'))
assert(me.name == 'Char6' and me.nickname == '', 'profile carries the character name')
assert(me.min == Config.Nickname.MinLength and me.max == Config.Nickname.MaxLength, 'profile carries the configured limits')
fire('kbphone:nickname', 6, 'x')
assert(last(6, 'error'), 'too short rejected')
fire('kbphone:nickname', 6, 'bad<script>')
assert(last(6, 'error'), 'bad characters rejected')
fire('kbphone:nickname', 6, '  Slick   Rick ')
assert(last(6, 'profile').nickname == 'Slick Rick', 'nickname trimmed and saved')
assert(#logged == 1 and logged[1].src == 6 and logged[1].data.after == 'Slick Rick' and logged[1].data.license == 'license:lic6', 'change logged to lib.logger')
assert(printed[#printed]:find('Char6') and printed[#printed]:find('Slick Rick'), 'change printed to the console')
assert(kvp['nickname:license:lic6'] == 'Slick Rick', 'nickname persisted')
assert(files['logs/nicknames.log'] and files['logs/nicknames.log']:find('Slick Rick'), 'change appended to logs/nicknames.log')
fire('kbphone:nickname', 6, 'Other')
assert(last(6, 'error'), 'rate limited')
fire('kbphone:create', 6, true)
assert(last(6, 'update').names[1] == 'Slick Rick', 'seat uses the nickname')
nicknames = nil
fire('kbphone:leave', 6)
print = rawprint
print('PASS: phone rooms by code, authority, spectating, leave/forfeit, CPU game, rematch, disconnect, public/private, nicknames')
