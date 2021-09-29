#!/usr/bin/env python
# -*- coding: UTF-8 -*-

import os
import sys
import random
import math

random.seed()

def unif_random(n):
    return random.randrange(n)

def clear_screen():
    if os.name == 'posix':
        _ = os.system('clear')
    else:
        _ = os.system('cls')

ROW_MASK = 0xFFFF
COL_MASK = 0x000F000F000F000F
INT64_MASK = 0xFFFFFFFFFFFFFFFF

UP = 0
DOWN = 1
LEFT = 2
RIGHT = 3

TABLESIZE = 65536
row_left_table = [0] * TABLESIZE
row_right_table = [0] * TABLESIZE
score_table = [0] * TABLESIZE
score_heur_table = [0] * TABLESIZE

SCORE_LOST_PENALTY = 200000.0
SCORE_MONOTONICITY_POWER = 4.0
SCORE_MONOTONICITY_WEIGHT = 47.0
SCORE_SUM_POWER = 3.5
SCORE_SUM_WEIGHT = 11.0
SCORE_MERGES_WEIGHT = 700.0
SCORE_EMPTY_WEIGHT = 270.0
CPROB_THRESH_BASE = 0.0001
CACHE_DEPTH_LIMIT = 15

def unpack_col(row):
    return (row | (row << 12) | (row << 24) | (row << 36)) & COL_MASK

def reverse_row(row):
    return ((row >> 12) | ((row >> 4) & 0x00F0)  | ((row << 4) & 0x0F00) | (row << 12)) & ROW_MASK

def print_board(board):
    sys.stdout.write('-----------------------------%s' % os.linesep)
    for i in range(0, 4):
        for j in range(0, 4):
            power_val = board & 0xf
            if power_val == 0:
                sys.stdout.write('|%6c' % ' ')
            else:
                sys.stdout.write("|%6d" % (1 << power_val))
            board >>= 4
        sys.stdout.write('|%s' % os.linesep)
    sys.stdout.write('-----------------------------%s' % os.linesep)

def transpose(x):
    a1 = x & 0xF0F00F0FF0F00F0F
    a2 = x & 0x0000F0F00000F0F0
    a3 = x & 0x0F0F00000F0F0000
    a = a1 | (a2 << 12) | (a3 >> 12)
    b1 = a & 0xFF00FF0000FF00FF
    b2 = a & 0x00FF00FF00000000
    b3 = a & 0x00000000FF00FF00
    return b1 | (b2 >> 24) | (b3 << 24)

def count_empty(x):
    x |= (x >> 2) & 0x3333333333333333
    x |= (x >> 1)
    x = ~x & 0x1111111111111111
    x += x >> 32
    x += x >> 16
    x += x >> 8
    x += x >> 4
    return x & 0xf

class trans_table_entry_t:
    def __init__(self, depth, heuristic):
        self.depth = depth
        self.heuristic = heuristic

class eval_state:
    def __init__(self):
        self.trans_table = {}
        self.maxdepth = 0
        self.curdepth = 0
        self.nomoves = 0
        self.tablehits = 0
        self.cachehits = 0
        self.moves_evaled = 0
        self.depth_limit = 0

def init_tables():
    for row in range(0, 65536):
        result = 0
        rev_row = 0
        rev_result = 0
        score = 0
        line = [row & 0xf, (row >> 4) & 0xf, (row >> 8) & 0xf, (row >> 12) & 0xf]

        for i in range(0, 4):
            rank = line[i]
            if rank >= 2:
                score += (rank - 1) * (1 << rank)
        score_table[row] = score

        sum_ = 0.0
        empty = 0
        merges = 0
        prev = 0
        counter = 0
        for i in range(0, 4):
            rank = line[i]

            sum_ += math.pow(rank, SCORE_SUM_POWER)
            if rank == 0:
                empty += 1
            else:
                if prev == rank:
                    counter += 1
                elif counter > 0:
                    merges += 1 + counter
                    counter = 0
                prev = rank

        if counter > 0:
            merges += 1 + counter

        monotonicity_left = 0.0
        monotonicity_right = 0.0

        for i in range(1, 4):
            if line[i - 1] > line[i]:
                monotonicity_left += math.pow(line[i - 1], SCORE_MONOTONICITY_POWER) - math.pow(line[i], SCORE_MONOTONICITY_POWER)
            else:
                monotonicity_right += math.pow(line[i], SCORE_MONOTONICITY_POWER) - math.pow(line[i - 1], SCORE_MONOTONICITY_POWER)

        score_heur_table[row] = SCORE_LOST_PENALTY + SCORE_EMPTY_WEIGHT * empty + SCORE_MERGES_WEIGHT * merges - \
            SCORE_MONOTONICITY_WEIGHT * min(monotonicity_left, monotonicity_right) - SCORE_SUM_WEIGHT * sum_

        i = 0
        while i < 3:
            j = i + 1
            while j < 4:
                if line[j] != 0:
                    break
                j += 1
            if j == 4:
                break

            if line[i] == 0:
                line[i] = line[j]
                line[j] = 0
                i -= 1
            elif line[i] == line[j]:
                if line[i] != 0xf:
                    line[i] += 1
                line[j] = 0
            i += 1
        result = line[0] | (line[1] << 4) | (line[2] << 8) | (line[3] << 12)

        rev_row = reverse_row(row)
        rev_result = reverse_row(result)
        row_left_table[row] = row ^ result
        row_right_table[rev_row] = rev_row ^ rev_result

def execute_move(board, move):
    ret = board
    if move == UP:
        t = transpose(board)
        ret ^= unpack_col(row_left_table[t & ROW_MASK])
        ret ^= unpack_col(row_left_table[(t >> 16) & ROW_MASK]) << 4
        ret ^= unpack_col(row_left_table[(t >> 32) & ROW_MASK]) << 8
        ret ^= unpack_col(row_left_table[(t >> 48) & ROW_MASK]) << 12
    elif move == DOWN:
        t = transpose(board)
        ret ^= unpack_col(row_right_table[t & ROW_MASK])
        ret ^= unpack_col(row_right_table[(t >> 16) & ROW_MASK]) << 4
        ret ^= unpack_col(row_right_table[(t >> 32) & ROW_MASK]) << 8
        ret ^= unpack_col(row_right_table[(t >> 48) & ROW_MASK]) << 12
    elif move == LEFT:
        ret ^= row_left_table[board & ROW_MASK]
        ret ^= row_left_table[(board >> 16) & ROW_MASK] << 16
        ret ^= row_left_table[(board >> 32) & ROW_MASK] << 32
        ret ^= row_left_table[(board >> 48) & ROW_MASK] << 48
    elif move == RIGHT:
        ret ^= row_right_table[board & ROW_MASK]
        ret ^= row_right_table[(board >> 16) & ROW_MASK] << 16
        ret ^= row_right_table[(board >> 32) & ROW_MASK] << 32
        ret ^= row_right_table[(board >> 48) & ROW_MASK] << 48
    return ret

def score_helper(board, table):
    return table[board & ROW_MASK] + table[(board >> 16) & ROW_MASK] + \
           table[(board >> 32) & ROW_MASK] + table[(board >> 48) & ROW_MASK]

def score_board(board):
    return score_helper(board, score_table)

def score_heur_board(board):
    return score_helper(board, score_heur_table) + score_helper(transpose(board), score_heur_table)

def draw_tile():
    rd = unif_random(10)
    if rd < 9:
       return 1
    else:
       return 2

def insert_tile_rand(board, tile):
    index = unif_random(count_empty(board))
    tmp = board
    while True:
        while (tmp & 0xf) != 0:
            tmp >>= 4
            tile <<= 4
        if index == 0:
            break
        index -= 1
        tmp >>= 4
        tile <<= 4
    return (board | tile) & INT64_MASK

def initial_board():
    board = draw_tile() << (unif_random(16) << 2)
    return insert_tile_rand(board, draw_tile())

def get_depth_limit(board):
    bitset = 0

    while board != 0:
        bitset |= 1 << (board & 0xf)
        board >>= 4

    if bitset <= 128:
        return 1
    elif bitset <= 512:
        return 2
    return 3

def score_tilechoose_node(state, board, cprob):
    if (cprob < CPROB_THRESH_BASE) or (state.curdepth >= state.depth_limit):
        state.maxdepth = max(state.curdepth, state.maxdepth)
        state.tablehits += 1
        return score_heur_board(board)

    if state.curdepth < CACHE_DEPTH_LIMIT:
        if board in state.trans_table:
            entry = state.trans_table[board]

            if entry.depth <= state.curdepth:
                state.cachehits += 1
                return entry.heuristic

    num_open = count_empty(board)
    cprob /= num_open
    res = 0.0
    tmp = board
    tile_2 = 1
    while tile_2 != 0:
        if (tmp & 0xf) == 0:
            res += score_move_node(state, board | tile_2, cprob * 0.9) * 0.9
            res += score_move_node(state, board | ((tile_2 << 1) & INT64_MASK), cprob * 0.1) * 0.1
        tmp >>= 4
        tile_2 <<= 4
        tile_2 &= INT64_MASK
    res = res / num_open

    if state.curdepth < CACHE_DEPTH_LIMIT:
        state.trans_table[board] = trans_table_entry_t(state.curdepth, res)

    return res

def score_move_node(state, board, cprob):
    best = 0.0
    state.curdepth += 1
    for move in range(0, 4):
        newboard = execute_move(board, move)
        state.moves_evaled += 1
        if board != newboard:
            best = max(best, score_tilechoose_node(state, newboard, cprob))
        else:
            state.nomoves += 1
    state.curdepth -= 1
    return best

def _score_toplevel_move(state, board, move):
    newboard = execute_move(board, move)
    if (board == newboard):
        return 0.0
    return score_tilechoose_node(state, newboard, 1.0) + 0.000001

def score_toplevel_move(board, move):
    res = 0.0
    state = eval_state()
    state.depth_limit = get_depth_limit(board)
    res = _score_toplevel_move(state, board, move)
    sys.stdout.write("Move %d: result %f: eval'd %d moves (%d no moves, %d table hits, %d cache hits, %d cache size) (maxdepth=%d)%s" % (move, res,
           state.moves_evaled, state.nomoves, state.tablehits, state.cachehits, len(state.trans_table), state.maxdepth, os.linesep))
    return res

def find_best_move(board):
    best = 0.0
    bestmove = -1
    print_board(board)
    sys.stdout.write("Current scores: heur %d, actual %d%s" % (score_heur_board(board), score_board(board), os.linesep))
    for move in range(0, 4):
        res = score_toplevel_move(board, move)
        if res > best:
            best = res
            bestmove = move
    sys.stdout.write("Selected bestmove: %d, result: %f%s" % (bestmove, best, os.linesep))
    return bestmove

def play_game(get_move):
    board = initial_board()
    scorepenalty = 0
    last_score = 0
    current_score = 0
    moveno = 0

    init_tables()
    while True:
        clear_screen()
        move = 0
        while move < 4:
            if execute_move(board, move) != board:
                break
            move += 1
        if move == 4:
            break

        current_score = score_board(board) - scorepenalty
        moveno += 1
        sys.stdout.write('Move #%d, current score=%d(+%d)%s' % (moveno, current_score, current_score - last_score, os.linesep))
        last_score = current_score
        sys.stdout.flush()

        move = get_move(board)
        if move < 0:
            break

        newboard = execute_move(board, move)
        if newboard == board:
            moveno -= 1
            continue

        tile = draw_tile()
        if tile == 2:
            scorepenalty += 4

        board = insert_tile_rand(newboard, tile)

    print_board(board)
    sys.stdout.write('Game over. Your score is %d.%s' % (current_score, os.linesep))
    sys.stdout.flush()


if __name__ == "__main__":
    play_game(find_best_move)
