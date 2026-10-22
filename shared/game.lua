-- A single positive 60-bit Lua integer. Never JSON-encode the packed value.
-- 0..26: A, 27..53: B, 54..56: roll, 57: turn, 58..59: phase.
-- Each side is column-major, three 3-bit slots per column. 0 means empty.
KB = {}
KB.WAITING, KB.PLAYING, KB.FINISHED, KB.FORFEIT = 0, 1, 2, 3
local MASK = (1 << 60) - 1

function KB.die(state, side, column, row)
    return (state >> ((side * 9 + (column - 1) * 3 + row - 1) * 3)) & 7
end

function KB.setDie(state, side, column, row, value)
    local shift = (side * 9 + (column - 1) * 3 + row - 1) * 3
    return (state & ~(7 << shift)) | (value << shift)
end

function KB.roll(state) return (state >> 54) & 7 end
function KB.turn(state) return (state >> 57) & 1 end
function KB.phase(state) return (state >> 58) & 3 end

function KB.meta(state, roll, turn, phase)
    return (state & ((1 << 54) - 1)) | (roll << 54) | (turn << 57) | (phase << 58)
end

function KB.valid(state)
    if math.type(state) ~= 'integer' or state < 0 or state > MASK or KB.roll(state) == 7 then
        return false
    end
    for slot = 0, 17 do
        if ((state >> (slot * 3)) & 7) == 7 then return false end
    end
    return true
end

-- IDs come from a persisted server epoch and monotonically increasing serial.
-- This also handles a network ID being reused for a newly spawned board.
function KB.snapshotOrder(incoming, current)
    if not current then return true end
    if incoming.match == current.match then return incoming.revision >= current.revision end
    local epoch, serial = incoming.match:match('^(%d+):(%d+)$')
    local oldEpoch, oldSerial = current.match:match('^(%d+):(%d+)$')
    if not epoch or not oldEpoch then return false end
    epoch, serial, oldEpoch, oldSerial = tonumber(epoch), tonumber(serial), tonumber(oldEpoch), tonumber(oldSerial)
    return epoch > oldEpoch or (epoch == oldEpoch and serial > oldSerial)
end

function KB.columnScore(state, side, column)
    local counts, score = {}, 0
    for row = 1, 3 do
        local value = KB.die(state, side, column, row)
        if value > 0 then counts[value] = (counts[value] or 0) + 1 end
    end
    for value, count in pairs(counts) do score = score + value * count * count end
    return score
end

function KB.score(state, side)
    local score = 0
    for column = 1, 3 do score = score + KB.columnScore(state, side, column) end
    return score
end

function KB.full(state, side)
    for column = 1, 3 do
        for row = 1, 3 do
            if KB.die(state, side, column, row) == 0 then return false end
        end
    end
    return true
end

function KB.place(state, side, column)
    if math.type(column) ~= 'integer' or column < 1 or column > 3 then
        return nil, 'Choose a column from 1 to 3.'
    end
    if KB.phase(state) ~= KB.PLAYING or KB.turn(state) ~= side then
        return nil, 'It is not your turn.'
    end
    local value = KB.roll(state)
    if value == 0 then return nil, 'Roll before choosing a column.' end
    local empty
    for row = 1, 3 do
        if KB.die(state, side, column, row) == 0 then empty = row; break end
    end
    if not empty then return nil, 'That column is full.' end
    state = KB.setDie(state, side, column, empty, value)
    local kept = {}
    for row = 1, 3 do
        local opposing = KB.die(state, 1 - side, column, row)
        if opposing ~= 0 and opposing ~= value then kept[#kept + 1] = opposing end
    end
    for row = 1, 3 do state = KB.setDie(state, 1 - side, column, row, kept[row] or 0) end
    local phase = (KB.full(state, 0) or KB.full(state, 1)) and KB.FINISHED or KB.PLAYING
    return KB.meta(state, 0, phase == KB.FINISHED and side or 1 - side, phase)
end

-- Browser-safe projection, also used by the spectator DUI.
function KB.decode(state)
    local result = { sides = {}, roll = KB.roll(state), turn = KB.turn(state), phase = KB.phase(state) }
    for side = 0, 1 do
        local board = { columns = {}, scores = {}, total = KB.score(state, side) }
        for column = 1, 3 do
            board.columns[column] = {}
            board.scores[column] = KB.columnScore(state, side, column)
            for row = 1, 3 do board.columns[column][row] = KB.die(state, side, column, row) end
        end
        result.sides[side + 1] = board
    end
    if result.phase == KB.FINISHED then
        local a, b = result.sides[1].total, result.sides[2].total
        result.winner = a == b and -1 or (a > b and 0 or 1)
    elseif result.phase == KB.FORFEIT then
        result.winner = result.turn
    end
    return result
end
