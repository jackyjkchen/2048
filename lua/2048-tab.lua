#!/usr/bin/env lua

ROW_MASK = 0xFFFF
COL_MASK = 0x000F000F000F000F

UP = 0
DOWN = 1
LEFT = 2
RIGHT = 3
RETRACT = 4

TABLESIZE = 65536
row_table = {}
score_table = {}

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
        local score = 0
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

function ask_for_move(board)
    print_board(board)

    while true do
        local allmoves = "wsadkjhl"
        local pos = 0
        local movechar = string.char(luadeps.c_getch())

        if (movechar == 'q') then
            return -1
        elseif (movechar == 'r') then
            return RETRACT
        end
        pos = string.find(allmoves, movechar)
        if (pos ~= nil) then
            return (pos - 1) % 4
        end
    end
end

function play_game(get_move)
    local board = initial_board()
    local scorepenalty = 0
    local last_score = 0
    local current_score = 0
    local moveno = 0
    local MAX_RETRACT = 64
    local retract_vec = {}
    local retract_penalty_vec = {}
    local retract_pos = 0
    local retract_num = 0

    init_tables()
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
            if (move == RETRACT) then
                if ((moveno <= 1) or (retract_num <= 0)) then
                    moveno = moveno - 1
                    break
                end
                moveno = moveno - 2
                if ((retract_pos == 0) and (retract_num > 0)) then
                    retract_pos = MAX_RETRACT
                end
                retract_pos = retract_pos - 1
                board = retract_vec[retract_pos]
                scorepenalty = scorepenalty - retract_penalty_vec[retract_pos]
                retract_num = retract_num - 1
                break
            end

            local newboard = execute_move(move, board)
            if (newboard == board) then
                moveno = moveno - 1
                break
            end

            tile = draw_tile()
            if (tile == 2) then
                scorepenalty = scorepenalty + 4
                retract_penalty_vec[retract_pos] = 4
            else
                retract_penalty_vec[retract_pos] = 0
            end
            retract_vec[retract_pos] = board
            retract_pos = retract_pos + 1
            if (retract_pos == MAX_RETRACT) then
                retract_pos = 0
            end
            if (retract_num < MAX_RETRACT) then
                retract_num = retract_num + 1
            end

            board = insert_tile_rand(newboard, tile)
        until true
    end

    print_board(board)
    print(string.format('Game over. Your score is %d.', current_score))
end

play_game(ask_for_move)
