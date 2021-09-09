#!/usr/bin/env lua

ROW_MASK = 0xFFFF
COL_MASK = 0x000F000F000F000F

UP = 0
DOWN = 1
LEFT = 2
RIGHT = 3

TABLESIZE = 65536
row_table = {}
score_table = {}
score_heur_table ={}

SCORE_LOST_PENALTY = 200000.0
SCORE_MONOTONICITY_POWER = 4.0
SCORE_MONOTONICITY_WEIGHT = 47.0
SCORE_SUM_POWER = 3.5
SCORE_SUM_WEIGHT = 11.0
SCORE_MERGES_WEIGHT = 700.0
SCORE_EMPTY_WEIGHT = 270.0
CPROB_THRESH_BASE = 0.0001
CACHE_DEPTH_LIMIT = 15

luadeps = require 'luadeps'

math.randomseed(os.time())

function unif_random(n)
    return math.random(0, n - 1)
end

function unpack_col(row)
    return (row | (row << 12) | (row << 24) | (row << 36)) & COL_MASK
end

function reverse_row(row)
    return ((row >> 12) | ((row >> 4) & 0x00F0)  | ((row << 4) & 0x0F00) | (row << 12)) & ROW_MASK
end

function print_board(board)
    print('-----------------------------')
    for i = 0, 3, 1 do
        for j = 0, 3, 1 do
            local power_val = board & 0xf
            if (power_val == 0) then
                io.write(string.format('|%6s', ' '))
            else
                io.write(string.format('|%6d', (1 << power_val)))
            end
            board = board >> 4
        end
        print('|')
    end
    print('-----------------------------')
end

function transpose(x)
    local a1 = x & 0xF0F00F0FF0F00F0F
    local a2 = x & 0x0000F0F00000F0F0
    local a3 = x & 0x0F0F00000F0F0000
    local a = a1 | (a2 << 12) | (a3 >> 12)
    local b1 = a & 0xFF00FF0000FF00FF
    local b2 = a & 0x00FF00FF00000000
    local b3 = a & 0x00000000FF00FF00
    return (b1 | (b2 >> 24) | (b3 << 24))
end

function count_empty(x)
    x = x | ((x >> 2) & 0x3333333333333333)
    x = x | (x >> 1)
    x = ~x & 0x1111111111111111
    x = x + (x >> 32)
    x = x + (x >> 16)
    x = x + (x >> 8)
    x = x + (x >> 4)
    return x & 0xf
end

function init_tables()
    for row = 0, 65535, 1 do
        local result = 0
        local score = 0.0
        local line = {}
        line[0] = row & 0xf
        line[1] = (row >> 4) & 0xf
        line[2] = (row >> 8) & 0xf
        line[3] = (row >> 12) & 0xf

        for i = 0, 3, 1 do
            local rank = line[i]
            if (rank >= 2) then
                score = score + (rank - 1) * (1 << rank)
            end
        end
        score_table[row] = score

        local sum = 0.0
        local empty = 0
        local merges = 0
        local prev = 0
        local counter = 0

        for i = 0, 3, 1 do
            local rank = line[i]

            sum = sum + rank ^ SCORE_SUM_POWER
            if (rank == 0) then
                empty = empty + 1
            else
                if (prev == rank) then
                    counter = counter + 1
                elseif (counter > 0) then
                    merges = merges + 1 + counter
                    counter = 0
                end
                prev = rank
            end
        end
        if (counter > 0) then
            merges = merges + 1 + counter
        end

        local monotonicity_left = 0.0
        local monotonicity_right = 0.0

        for i = 1, 3, 1 do
            if (line[i - 1] > line[i]) then
                monotonicity_left = monotonicity_left +
                    (line[i - 1] ^ SCORE_MONOTONICITY_POWER) - (line[i] ^ SCORE_MONOTONICITY_POWER)
            else
                monotonicity_right = monotonicity_right +
                    (line[i] ^ SCORE_MONOTONICITY_POWER) - (line[i - 1] ^ SCORE_MONOTONICITY_POWER)
            end
        end

        score_heur_table[row] = SCORE_LOST_PENALTY + SCORE_EMPTY_WEIGHT * empty + SCORE_MERGES_WEIGHT * merges -
            SCORE_MONOTONICITY_WEIGHT * math.min(monotonicity_left, monotonicity_right) - SCORE_SUM_WEIGHT * sum

        i = 0
        while (i < 3) do
            j = i + 1
            while (j < 4) do
                if (line[j] ~= 0) then
                    break
                end
                j = j + 1
            end
            if (j == 4) then
                break
            end

            if (line[i] == 0) then
                line[i] = line[j]
                line[j] = 0
                i = i - 1
            elseif (line[i] == line[j]) then
                if (line[i] ~= 0xf) then
                    line[i] = line[i] + 1
                end
                line[j] = 0
            end
            i = i + 1
        end

        result = line[0] | (line[1] << 4) | (line[2] << 8) | (line[3] << 12)
        row_table[row] = row ~ result
    end
end

function execute_move_col(board, move)
    local ret = board
    local t = transpose(board)
    if (move == UP) then
        ret = ret ~ unpack_col(row_table[t & ROW_MASK])
        ret = ret ~ (unpack_col(row_table[(t >> 16) & ROW_MASK]) << 4)
        ret = ret ~ (unpack_col(row_table[(t >> 32) & ROW_MASK]) << 8)
        ret = ret ~ (unpack_col(row_table[(t >> 48) & ROW_MASK]) << 12)
    elseif (move == DOWN) then
        ret = ret ~ unpack_col(reverse_row(row_table[reverse_row(t & ROW_MASK)]))
        ret = ret ~ (unpack_col(reverse_row(row_table[reverse_row((t >> 16) & ROW_MASK)])) << 4)
        ret = ret ~ (unpack_col(reverse_row(row_table[reverse_row((t >> 32) & ROW_MASK)])) << 8)
        ret = ret ~ (unpack_col(reverse_row(row_table[reverse_row((t >> 48) & ROW_MASK)])) << 12)
    end
    return ret
end

function execute_move_row(board, move)
    local ret = board
    if (move == LEFT) then
        ret = ret ~ row_table[board & ROW_MASK]
        ret = ret ~ (row_table[(board >> 16) & ROW_MASK] << 16)
        ret = ret ~ (row_table[(board >> 32) & ROW_MASK] << 32)
        ret = ret ~ (row_table[(board >> 48) & ROW_MASK] << 48)
    elseif (move == RIGHT) then
        ret = ret ~ reverse_row(row_table[reverse_row(board & ROW_MASK)])
        ret = ret ~ (reverse_row(row_table[reverse_row((board >> 16) & ROW_MASK)]) << 16)
        ret = ret ~ (reverse_row(row_table[reverse_row((board >> 32) & ROW_MASK)]) << 32)
        ret = ret ~ (reverse_row(row_table[reverse_row((board >> 48) & ROW_MASK)]) << 48)
    end
    return ret
end

function execute_move(move, board)
    if (move == UP) or (move == DOWN) then
        return execute_move_col(board, move)
    elseif (move == LEFT) or (move == RIGHT) then
        return execute_move_row(board, move)
    else
        return 0xFFFFFFFFFFFFFFFF
    end
end

function score_helper(board, table)
    return table[board & ROW_MASK] + table[(board >> 16) & ROW_MASK] +
           table[(board >> 32) & ROW_MASK] + table[(board >> 48) & ROW_MASK]
end

function score_board(board)
    return score_helper(board, score_table)
end

function score_heur_board(board)
    return score_helper(board, score_heur_table) + score_helper(transpose(board), score_heur_table)
end

function count_distinct_tiles(board)
    bitset = 0

    while (board ~= 0) do
        bitset = bitset | (1 << (board & 0xf))
        board = board >> 4
    end

    bitset = bitset >> 1
    count = 0

    while (bitset ~= 0) do
        bitset = bitset & (bitset - 1)
        count = count + 1
    end
    return count
end

function score_tilechoose_node(state, board, cprob)
    if (cprob < CPROB_THRESH_BASE or state.curdepth >= state.depth_limit) then
        state.maxdepth = math.max(state.curdepth, state.maxdepth)
        return score_heur_board(board)
    end
    if (state.curdepth < CACHE_DEPTH_LIMIT) then
        if (state.trans_table[board] ~= nil) then
            local entry = state.trans_table[board]

            if (entry.depth <= state.curdepth) then
                state.cachehits = state.cachehits + 1
                return entry.heuristic
            end
        end
    end

    local num_open = count_empty(board)
    cprob = cprob / num_open
    local res = 0.0
    local tmp = board
    local tile_2 = 1

    while (tile_2 ~= 0) do
        if ((tmp & 0xf) == 0) then
            res = res + score_move_node(state, board | tile_2, cprob * 0.9) * 0.9
            res = res + score_move_node(state, board | (tile_2 << 1), cprob * 0.1) * 0.1
        end
        tmp = tmp >> 4
        tile_2 = tile_2 << 4
    end
    res = res / num_open

    if (state.curdepth < CACHE_DEPTH_LIMIT) then
        local entry = {
            depth = state.curdepth,
            heuristic = res
        }
        state.trans_table[board] = entry
        state.tablesize = state.tablesize + 1
    end

    return res
end

function score_move_node(state, board, cprob)
    local best = 0.0

    state.curdepth = state.curdepth + 1
    for move = 0, 3, 1 do
        newboard = execute_move(move, board)

        state.moves_evaled = state.moves_evaled + 1
        if (board ~= newboard) then
            best = math.max(best, score_tilechoose_node(state, newboard, cprob))
        end
    end
    state.curdepth = state.curdepth - 1

    return best
end

function _score_toplevel_move(state, board, move)
    local newboard = execute_move(move, board)

    if (board == newboard) then
        return 0.0
    end

    return score_tilechoose_node(state, newboard, 1.0) + 0.000001
end

function score_toplevel_move(board, move)
    local res = 0.0
    local state = {
        trans_table = {},
        tablesize = 0;
        maxdepth = 0,
        curdepth = 0,
        cachehits = 0,
        moves_evaled = 0,
        depth_limit = 0,
    }

    state.depth_limit = math.max(3, count_distinct_tiles(board) - 2)

    res = _score_toplevel_move(state, board, move)

    print(string.format("Move %d: result %f: eval'd %d moves (%d cache hits, %d cache size) (maxdepth=%d)", move, res,
           state.moves_evaled, state.cachehits, state.tablesize, state.maxdepth))

    return res
end

function find_best_move(board)
    local move = 0
    local best = 0.0
    local bestmove = -1

    print_board(board)
    print(string.format("Current scores: heur %d, actual %d", math.floor(score_heur_board(board)), score_board(board)))

    for move = 0, 3, 1 do
        local res = score_toplevel_move(board, move)

        if (res > best) then
            best = res
            bestmove = move
        end
    end
    print(string.format("Selected bestmove: %d, result: %f", bestmove, best))

    return bestmove
end

function draw_tile()
    local rd = unif_random(10)
    if (rd < 9) then
       return 1
    else
       return 2
    end
end

function insert_tile_rand(board, tile)
    local index = unif_random(count_empty(board))
    local tmp = board
    while true do
        while ((tmp & 0xf) ~= 0) do
            tmp = tmp >> 4
            tile = tile << 4
        end
        if (index == 0) then
            break
        end
        index = index - 1
        tmp = tmp >> 4
        tile = tile << 4
    end
    return board | tile
end

function initial_board()
    local board = draw_tile() << (unif_random(16) << 2)
    return insert_tile_rand(board, draw_tile())
end

function play_game(get_move)
    local board = initial_board()
    local scorepenalty = 0
    local last_score = 0
    local current_score = 0
    local moveno = 0

    while true do
        luadeps.c_clear_screen()
        local move = 0
        while (move < 4) do
            if (execute_move(move, board) ~= board) then
                break
            end
            move = move + 1
        end
        if (move == 4) then
            break
        end

        current_score = score_board(board) - scorepenalty
        moveno = moveno + 1
        print(string.format('Move #%d, current score=%d(+%d)', moveno, current_score, current_score - last_score))
        last_score = current_score

        move = get_move(board)
        if (move < 0) then
            break
        end

        repeat
            local newboard = execute_move(move, board)
            if (newboard == board) then
                moveno = moveno - 1
                break
            end

            tile = draw_tile()
            if (tile == 2) then
                scorepenalty = scorepenalty + 4
            end

            board = insert_tile_rand(newboard, tile)
        until true
    end

    print_board(board)
    print(string.format('Game over. Your score is %d.', current_score))
end

luadeps.c_term_init()
init_tables()
play_game(find_best_move)
luadeps.c_term_clear()
