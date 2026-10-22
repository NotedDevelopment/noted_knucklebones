-- Pure authority logic; no FiveM natives or yields. Tested independently.
KBMatch = {}
-- Seat id of the computer opponent. Player ids are numbers, so it never collides.
KBMatch.AI = 'ai'

function KBMatch.new(id)
    return { id = id, revision = 0, state = 0, seats = {}, ready = {} }
end

function KBMatch.aiSide(match)
    for side = 0, 1 do
        if match.seats[side] and match.seats[side].ai then return side end
    end
end

-- Greedy: the column with the best score margin after the move, ties broken randomly.
function KBMatch.aiColumn(state, side, random)
    local best, bestValue = {}, nil
    for column = 1, 3 do
        local after = KB.place(state, side, column)
        if after then
            local value = KB.score(after, side) - KB.score(after, 1 - side)
            if not bestValue or value > bestValue then
                best, bestValue = { column }, value
            elseif value == bestValue then
                best[#best + 1] = column
            end
        end
    end
    return best[random(1, #best)]
end

function KBMatch.seat(match, player)
    for side = 0, 1 do
        if match.seats[side] and match.seats[side].id == player then return side end
    end
end

function KBMatch.apply(match, player, name, request, random, newId)
    if request.match ~= match.id or request.revision ~= match.revision then
        return false, 'The board changed. It has been refreshed; try again.'
    end
    local side, phase = KBMatch.seat(match, player), KB.phase(match.state)
    local action = request.action
    if action == 'join' then
        if side ~= nil then return false, 'You already have a seat.' end
        if phase ~= KB.WAITING then return false, 'This game has already started.' end
        if request.side == 0 or request.side == 1 then
            -- A chair maps to one side; the first free seat otherwise.
            if match.seats[request.side] then return false, 'That seat is taken.' end
            side = request.side
        else
            side = not match.seats[0] and 0 or (not match.seats[1] and 1 or nil)
        end
        if side == nil then return false, 'Both seats are occupied.' end
        match.seats[side] = { id = player, name = name }
        if match.seats[0] and match.seats[1] then
            match.state = KB.meta(0, 0, random(0, 1), KB.PLAYING)
        end
    elseif action == 'ai' then
        if phase ~= KB.WAITING then return false, 'This game has already started.' end
        local mine = side or (not match.seats[0] and 0 or (not match.seats[1] and 1 or nil))
        if mine == nil then return false, 'Both seats are occupied.' end
        if match.seats[1 - mine] then return false, 'A player is waiting. Take a seat to play them.' end
        match.seats[mine] = match.seats[mine] or { id = player, name = name }
        match.seats[1 - mine] = { id = KBMatch.AI, name = 'AI', ai = true }
        match.state = KB.meta(0, 0, random(0, 1), KB.PLAYING)
    elseif side == nil then
        return false, 'Take a seat first.'
    elseif action == 'roll' then
        if phase ~= KB.PLAYING or KB.turn(match.state) ~= side then
            return false, 'It is not your turn.'
        end
        if KB.roll(match.state) ~= 0 then return false, 'Place your current die first.' end
        match.state = KB.meta(match.state, random(1, 6), side, phase)
    elseif action == 'place' then
        local state, err = KB.place(match.state, side, request.column)
        if not state then return false, err end
        match.state = state
    elseif action == 'leave' then
        if phase == KB.PLAYING then
            match.state = KB.meta(match.state, 0, 1 - side, KB.FORFEIT)
        end
        match.seats[side], match.ready = nil, {}
        -- A lone remaining player can start a fresh lobby via rematch. The AI never stays alone.
        local other = match.seats[1 - side]
        if not other or other.ai then
            match.id, match.state, match.ready, match.seats = newId(), 0, {}, {}
        end
    elseif action == 'rematch' then
        if phase ~= KB.FINISHED and phase ~= KB.FORFEIT then
            return false, 'Finish the current game first.'
        end
        if match.ready[side] then return false, 'Waiting for the other player.' end
        match.ready[side] = true
        local other = match.seats[1 - side]
        if not other or other.ai or match.ready[1 - side] then
            local both = match.seats[0] and match.seats[1]
            match.id, match.ready = newId(), {}
            match.state = KB.meta(0, 0, both and random(0, 1) or 0, both and KB.PLAYING or KB.WAITING)
        end
    else
        return false, 'Unknown action.'
    end
    -- Monotonic for the lifetime of the entity, including rematches.
    match.revision = match.revision + 1
    return true
end
