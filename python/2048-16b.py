#!/usr/bin/env python
# -*- coding: UTF-8 -*-

import os
import sys
import copy
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

board_t = [0] * 4

UP = 0
DOWN = 1
LEFT = 2
RIGHT = 3
RETRACT = 4

def unpack_col(row):
    board = [0] * 4
    board[0] = (row & 0xF000) >> 12
    board[1] = (row & 0x0F00) >> 8
    board[2] = (row & 0x00F0) >> 4
    board[3] = row & 0x000F
    return board

def reverse_row(row):
    return (row >> 12) | ((row >> 4) & 0x00F0)  | ((row << 4) & 0x0F00) | (row << 12)

def print_board(board):
    sys.stdout.write('-----------------------------%s' % os.linesep)
    t = copy.deepcopy(board)
    for i in range(0, 4):
        for j in range(0, 4):
            power_val = t[3 - i] & 0xf
            if power_val == 0:
                sys.stdout.write('|%6c' % ' ')
            else:
                sys.stdout.write("|%6d" % (1 << power_val))
            t[3 - i] = t[3 - i] >> 4
        sys.stdout.write('|%s' % os.linesep)
    sys.stdout.write('-----------------------------%s' % os.linesep)

def transpose(board):
    x = copy.deepcopy(board)
    a1_0 = x[0] & 0xF0F0
    a1_1 = x[1] & 0x0F0F
    a1_2 = x[2] & 0xF0F0
    a1_3 = x[3] & 0x0F0F
    a2_1 = x[1] & 0xF0F0
    a2_3 = x[3] & 0xF0F0
    a3_0 = x[0] & 0x0F0F
    a3_2 = x[2] & 0x0F0F
    r0 = a1_0 | (a2_1 >> 4)
    r1 = a1_1 | (a3_0 << 4)
    r2 = a1_2 | (a2_3 >> 4)
    r3 = a1_3 | (a3_2 << 4)
    b1_0 = r0 & 0xFF00
    b1_1 = r1 & 0xFF00
    b1_2 = r2 & 0x00FF
    b1_3 = r3 & 0x00FF
    b2_0 = r0 & 0x00FF
    b2_1 = r1 & 0x00FF
    b3_2 = r2 & 0xFF00
    b3_3 = r3 & 0xFF00

    x[0] = b1_0 | (b3_2 >> 8)
    x[1] = b1_1 | (b3_3 >> 8)
    x[2] = b1_2 | (b2_0 << 8)
    x[3] = b1_3 | (b2_1 << 8)
    return x

def count_empty(board):
    sum = 0
    for i in range(0, 4):
        x = board[i]
        x = x | ((x >> 2) & 0x3333)
        x = x | (x >> 1)
        x = ~x & 0x1111
        x = x + (x >> 8)
        x = x + (x >> 4)
        sum = sum + x
    return sum & 0xf

def execute_move_helper(row):
    i = 0
    line = [row & 0xf, (row >> 4) & 0xf, (row >> 8) & 0xf, (row >> 12) & 0xf]
    while i < 3:
        j = i + 1
        while j < 4:
            if line[j] != 0:
                break
            j = j + 1
        if j == 4:
            break

        if line[i] == 0:
            line[i] = line[j]
            line[j] = 0
            i = i - 1
        elif line[i] == line[j]:
            if line[i] != 0xf:
                line[i] = line[i] + 1
            line[j] = 0
        i = i + 1

    return  line[0] | (line[1] << 4) | (line[2] << 8) | (line[3] << 12)

def execute_move_col(board, move):
    ret = copy.deepcopy(board)
    t = transpose(board)
    for i in range(0, 4):
        row = t[3 - i]
        if move == UP:
            tmp = unpack_col(row ^ execute_move_helper(row))
        elif move == DOWN:
            tmp = unpack_col(row ^ reverse_row(execute_move_helper(reverse_row(row))))
        ret[0] = ret[0] ^ (tmp[0] << (i << 2))
        ret[1] = ret[1] ^ (tmp[1] << (i << 2))
        ret[2] = ret[2] ^ (tmp[2] << (i << 2))
        ret[3] = ret[3] ^ (tmp[3] << (i << 2))
    return ret

def execute_move_row(board, move):
    t = copy.deepcopy(board)
    for i in range(0, 4):
        row = t[3 - i]
        if move == LEFT:
            t[3 - i] = t[3 - i] ^ (row ^ execute_move_helper(row))
        elif move == RIGHT:
            t[3 - i] = t[3 - i] ^ (row ^ reverse_row(execute_move_helper(reverse_row(row))))
    return t

def execute_move(move, board):
    if (move == UP) or (move == DOWN):
        return execute_move_col(board, move)
    elif (move == LEFT) or (move == RIGHT):
        return execute_move_row(board, move)
    else:
        raise

def score_helper(board):
    score = 0
    for j in range(0, 4):
        row = board[3 - j]
        for i in range(0, 4):
            rank = (row >> (i << 2)) & 0xf
            if rank >= 2:
                score = score + (rank - 1) * (1 << rank)
    return score

def score_board(board):
    return score_helper(board)

def draw_tile():
    rd = unif_random(10)
    if rd < 9:
       return 1
    else:
       return 2

def insert_tile_rand(board, tile):
    index = unif_random(count_empty(board))
    shift = 0
    t = copy.deepcopy(board)
    tmp = t[3]
    orig_tile = tile
    while 1:
        while (tmp & 0xf) != 0:
            tmp = tmp >> 4
            tile = tile << 4
            shift = shift + 4
            if (shift % 16) == 0:
                tmp = t[3 - (shift >> 4)]
                tile = orig_tile
        if index == 0:
            break
        index = index - 1
        tmp = tmp >> 4
        tile = tile << 4
        shift = shift + 4
        if (shift % 16) == 0:
            tmp = t[3 - (shift >> 4)]
            tile = orig_tile
    t[3 - (shift >> 4)] = t[3 - (shift >> 4)] | tile
    return t

def initial_board():
    shift = unif_random(16) << 2
    board = [0] * 4
    board[3 - (shift >> 4)] = draw_tile() << (shift % 16)
    return insert_tile_rand(board, draw_tile())

def ask_for_move(board):
    print_board(board)
    while 1:
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

    while 1:
        clear_screen()
        move = 0
        while move < 4:
            if execute_move(move, board) != board:
                break
            move = move + 1
        if move == 4:
            break

        current_score = score_board(board) - scorepenalty
        moveno = moveno + 1
        sys.stdout.write('Move #%d, current score=%d(+%d)%s' % (moveno, current_score, current_score - last_score, os.linesep))
        last_score = current_score
        sys.stdout.flush()

        move = get_move(board)
        if move < 0:
            break

        if move == RETRACT:
            if moveno <= 1 or retract_num <= 0:
                moveno = moveno - 1
                continue
            moveno = moveno - 2
            if retract_pos == 0 and retract_num > 0:
                retract_pos = MAX_RETRACT
            retract_pos = retract_pos - 1
            board = retract_vec[retract_pos]
            scorepenalty = scorepenalty - retract_penalty_vec[retract_pos]
            retract_num = retract_pos - 1
            continue

        newboard = execute_move(move, board)
        if newboard == board:
            moveno = moveno - 1
            continue

        tile = draw_tile()
        if tile == 2:
            scorepenalty = scorepenalty + 4
            retract_penalty_vec[retract_pos] = 4
        else:
            retract_penalty_vec[retract_pos] = 0
        retract_vec[retract_pos] = board
        retract_pos = retract_pos + 1
        if retract_pos == MAX_RETRACT:
            retract_pos = 0
        if retract_num < MAX_RETRACT:
            retract_num = retract_num + 1

        board = insert_tile_rand(newboard, tile)

    print_board(board)
    sys.stdout.write('Game over. Your score is %d.%s' % (current_score, os.linesep))
    sys.stdout.flush()


if __name__ == "__main__":
    play_game(ask_for_move)
