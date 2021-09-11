#!/usr/bin/env python
# -*- coding: UTF-8 -*-

import os
import sys
import random

random.seed()

def unif_random(n):
    return random.randrange(n)

def clear_screen():
    if os.name == 'posix':
        _ = os.system('clear')
    else:
        _ = os.system('cls')

class _get_ch_win32:
    def __call__(self):
        import msvcrt
        return msvcrt.getwch()

class _get_ch_unix:
    def __call__(self):
        import tty, termios
        fd = sys.stdin.fileno()
        setting = termios.tcgetattr(fd)
        try:
            tty.setraw(sys.stdin.fileno())
            ch = sys.stdin.read(1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, setting)
        return ch

class _get_ch:
    def __init__(self):
        if os.name == 'posix':
            self.impl = _get_ch_unix()
        else:
            self.impl = _get_ch_win32()

    def __call__(self):
        return self.impl()
        
get_ch = _get_ch()

ROW_MASK = 0xFFFF
COL_MASK = 0x000F000F000F000F
INT64_MASK = 0xFFFFFFFFFFFFFFFF

UP = 0
DOWN = 1
LEFT = 2
RIGHT = 3
RETRACT = 4

TABLESIZE = 65536
row_table = [0] * TABLESIZE
score_table = [0] * TABLESIZE

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

def init_tables():
    for row in range(0, 65536):
        result = 0
        score = 0
        line = [row & 0xf, (row >> 4) & 0xf, (row >> 8) & 0xf, (row >> 12) & 0xf]

        for i in range(0, 4):
            rank = line[i]
            if rank >= 2:
                score += (rank - 1) * (1 << rank)
        score_table[row] = score

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
        row_table[row] = row ^ result

def execute_move_col(board, move):
    ret = board
    t = transpose(board)
    if move == UP:
        ret ^= unpack_col(row_table[t & ROW_MASK])
        ret ^= unpack_col(row_table[(t >> 16) & ROW_MASK]) << 4
        ret ^= unpack_col(row_table[(t >> 32) & ROW_MASK]) << 8
        ret ^= unpack_col(row_table[(t >> 48) & ROW_MASK]) << 12
    elif move == DOWN:
        ret ^= unpack_col(reverse_row(row_table[reverse_row(t & ROW_MASK)]))
        ret ^= unpack_col(reverse_row(row_table[reverse_row((t >> 16) & ROW_MASK)])) << 4
        ret ^= unpack_col(reverse_row(row_table[reverse_row((t >> 32) & ROW_MASK)])) << 8
        ret ^= unpack_col(reverse_row(row_table[reverse_row((t >> 48) & ROW_MASK)])) << 12
    return ret

def execute_move_row(board, move):
    ret = board
    if move == LEFT:
        ret ^= row_table[board & ROW_MASK]
        ret ^= row_table[(board >> 16) & ROW_MASK] << 16
        ret ^= row_table[(board >> 32) & ROW_MASK] << 32
        ret ^= row_table[(board >> 48) & ROW_MASK] << 48
    elif move == RIGHT:
        ret ^= reverse_row(row_table[reverse_row(board & ROW_MASK)])
        ret ^= reverse_row(row_table[reverse_row((board >> 16) & ROW_MASK)]) << 16
        ret ^= reverse_row(row_table[reverse_row((board >> 32) & ROW_MASK)]) << 32
        ret ^= reverse_row(row_table[reverse_row((board >> 48) & ROW_MASK)]) << 48
    return ret

def execute_move(move, board):
    if move == UP or move == DOWN:
        return execute_move_col(board, move)
    elif move == LEFT or move == RIGHT:
        return execute_move_row(board, move)
    else:
        return INT64_MASK

def score_helper(board, table):
    return table[board & ROW_MASK] + table[(board >> 16) & ROW_MASK] + \
           table[(board >> 32) & ROW_MASK] + table[(board >> 48) & ROW_MASK]

def score_board(board):
    return score_helper(board, score_table)

def ask_for_move(board):
    print_board(board)

    while True:
        allmoves = "wsadkjhl"
        pos = 0

        movechar = get_ch()

        if movechar == 'q':
            return -1
        elif movechar == 'r':
            return RETRACT
        pos = allmoves.find(movechar)
        if pos != -1:
            return pos % 4

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

def play_game(get_move):
    board = initial_board()
    scorepenalty = 0
    last_score = 0
    current_score = 0
    moveno = 0

    MAX_RETRACT = 64
    retract_vec = [0] * MAX_RETRACT
    retract_penalty_vec = [0] * MAX_RETRACT
    retract_pos = 0
    retract_num = 0

    while True:
        clear_screen()
        move = 0
        while move < 4:
            if execute_move(move, board) != board:
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

        if move == RETRACT:
            if moveno <= 1 or retract_num <= 0:
                moveno -= 1
                continue
            moveno -= 2
            if retract_pos == 0 and retract_num > 0:
                retract_pos = MAX_RETRACT
            retract_pos -= 1
            board = retract_vec[retract_pos]
            scorepenalty = scorepenalty - retract_penalty_vec[retract_pos]
            retract_num -= 1
            continue

        newboard = execute_move(move, board)
        if newboard == board:
            moveno -= 1
            continue

        tile = draw_tile()
        if tile == 2:
            scorepenalty += 4
            retract_penalty_vec[retract_pos] = 4
        else:
            retract_penalty_vec[retract_pos] = 0
        retract_vec[retract_pos] = board
        retract_pos += 1
        if retract_pos == MAX_RETRACT:
            retract_pos = 0
        if retract_num < MAX_RETRACT:
            retract_num += 1

        board = insert_tile_rand(newboard, tile)

    print_board(board)
    sys.stdout.write('Game over. Your score is %d.%s' % (current_score, os.linesep))
    sys.stdout.flush()


if __name__ == "__main__":
    init_tables()
    play_game(ask_for_move)
