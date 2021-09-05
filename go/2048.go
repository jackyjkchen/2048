package main

/*
extern void clear_screen(void);
extern void term_init(void);
extern void term_clear(void);
extern int get_ch(void);
#cgo LDFLAGS: -L. -lgodeps
*/
import "C"

import (
	"fmt"
	"math/rand"
	"strings"
	"time"
)

type board_t uint64
type row_t uint16

const ROW_MASK board_t = 0xFFFF
const COL_MASK board_t = 0x000F000F000F000F

const (
	UP      = 0
	DOWN    = 1
	LEFT    = 2
	RIGHT   = 3
	RETRACT = 4
)

type get_move_func_t func(board board_t) int

const TABLESIZE = 65536

var row_left_table [TABLESIZE]row_t
var row_right_table [TABLESIZE]row_t
var score_table [TABLESIZE]uint32

var rd = rand.New(rand.NewSource(time.Now().UnixNano()))

func unif_random(n uint32) uint32 {
	return rd.Uint32() % n
}

func unpack_col(row row_t) board_t {
	var tmp board_t = board_t(row)

	return (tmp | (tmp << 12) | (tmp << 24) | (tmp << 36)) & COL_MASK
}

func reverse_row(row row_t) row_t {
	return (row >> 12) | ((row >> 4) & 0x00F0) | ((row << 4) & 0x0F00) | (row << 12)
}

func print_board(board board_t) {
	fmt.Printf("-----------------------------\n")
	for i := 0; i < 4; i++ {
		for j := 0; j < 4; j++ {
			power_val := board & 0xf

			if power_val == 0 {
				fmt.Printf("|%6c", ' ')
			} else {
				fmt.Printf("|%6d", 1<<power_val)
			}
			board >>= 4
		}
		fmt.Printf("|\n")
	}
	fmt.Printf("-----------------------------\n")
}

func transpose(x board_t) board_t {
	a1 := x & 0xF0F00F0FF0F00F0F
	a2 := x & 0x0000F0F00000F0F0
	a3 := x & 0x0F0F00000F0F0000
	a := a1 | (a2 << 12) | (a3 >> 12)
	b1 := a & 0xFF00FF0000FF00FF
	b2 := a & 0x00FF00FF00000000
	b3 := a & 0x00000000FF00FF00

	return b1 | (b2 >> 24) | (b3 << 24)
}

func count_empty(x board_t) uint32 {
	x |= (x >> 2) & 0x3333333333333333
	x |= (x >> 1)
	x = ^x & 0x1111111111111111
	x += x >> 32
	x += x >> 16
	x += x >> 8
	x += x >> 4
	return uint32(x & 0xf)
}

func init_tables() {
	var row, rev_row row_t = 0, 0
	var result, rev_result row_t = 0, 0

	for true {
		i := 0
		j := 0
		var line [4]row_t
		var score uint32 = 0

		line[0] = (row >> 0) & 0xf
		line[1] = (row >> 4) & 0xf
		line[2] = (row >> 8) & 0xf
		line[3] = (row >> 12) & 0xf

		for i = 0; i < 4; i++ {
			var rank uint32 = uint32(line[i])

			if rank >= 2 {
				score += (rank - 1) * (1 << rank)
			}
		}
		score_table[row] = score

		for i = 0; i < 3; i++ {
			for j = i + 1; j < 4; j++ {
				if line[j] != 0 {
					break
				}
			}
			if j == 4 {
				break
			}

			if line[i] == 0 {
				line[i] = line[j]
				line[j] = 0
				i--
			} else if line[i] == line[j] {
				if line[i] != 0xf {
					line[i]++
				}
				line[j] = 0
			}
		}

		result = (line[0] << 0) | (line[1] << 4) | (line[2] << 8) | (line[3] << 12)
		rev_result = reverse_row(result)
		rev_row = reverse_row(row)

		row_left_table[row] = row ^ result
		row_right_table[rev_row] = rev_row ^ rev_result

		if row == TABLESIZE-1 {
			break
		}
		row++
	}
}

func execute_move_col(board board_t, table *[TABLESIZE]row_t) board_t {
	var ret board_t = board
	var t board_t = transpose(board)

	ret ^= unpack_col(table[(t>>0)&ROW_MASK]) << 0
	ret ^= unpack_col(table[(t>>16)&ROW_MASK]) << 4
	ret ^= unpack_col(table[(t>>32)&ROW_MASK]) << 8
	ret ^= unpack_col(table[(t>>48)&ROW_MASK]) << 12
	return ret
}

func execute_move_row(board board_t, table *[TABLESIZE]row_t) board_t {
	var ret board_t = board

	ret ^= board_t(table[(board>>0)&ROW_MASK]) << 0
	ret ^= board_t(table[(board>>16)&ROW_MASK]) << 16
	ret ^= board_t(table[(board>>32)&ROW_MASK]) << 32
	ret ^= board_t(table[(board>>48)&ROW_MASK]) << 48
	return ret
}

func execute_move(move int, board board_t) board_t {
	switch move {
	case UP:
		return execute_move_col(board, &row_left_table)
	case DOWN:
		return execute_move_col(board, &row_right_table)
	case LEFT:
		return execute_move_row(board, &row_left_table)
	case RIGHT:
		return execute_move_row(board, &row_right_table)
	default:
		return 0xFFFFFFFFFFFFFFFF
	}
}

func score_helper(board board_t, table *[TABLESIZE]uint32) uint32 {
	return table[(board>>0)&ROW_MASK] + table[(board>>16)&ROW_MASK] +
		table[(board>>32)&ROW_MASK] + table[(board>>48)&ROW_MASK]
}

func score_board(board board_t) uint32 {
	return score_helper(board, &score_table)
}

func ask_for_move(board board_t) int {
	print_board(board)

	for true {
		allmoves := "wsadkjhl"
		pos := 0
		var movechar rune = rune(C.get_ch())

		if movechar == 'q' {
			return -1
		}
		if movechar == 'r' {
			return RETRACT
		}
		pos = strings.IndexRune(allmoves, movechar)
		if pos != -1 {
			return pos % 4
		}
	}
	return -1
}

func draw_tile() board_t {
	if unif_random(10) < 9 {
		return 1
    }
	return 2
}

func insert_tile_rand(board, tile board_t) board_t {
	index := unif_random(count_empty(board))
	var tmp board_t = board

	for true {
		for (tmp & 0xf) != 0 {
			tmp >>= 4
			tile <<= 4
		}
		if index == 0 {
			break
		}
		index--
		tmp >>= 4
		tile <<= 4
	}
	return board | tile
}

func initial_board() board_t {
	var board board_t = board_t(draw_tile()) << (unif_random(16) << 2)

	return insert_tile_rand(board, draw_tile())
}

func play_game(get_move get_move_func_t) {
	var board board_t = initial_board()
	var scorepenalty int32 = 0
	var current_score int32 = 0
	var last_score int32 = 0
	moveno := 0

	const MAX_RETRACT = 64
	var retract_vec [MAX_RETRACT]board_t
	var retract_penalty_vec [MAX_RETRACT]int32
	retract_pos := 0
	retract_num := 0

	for true {
		move := 0
		var tile board_t = 0
		var newboard board_t = 0

		C.clear_screen()
		for move = 0; move < 4; move++ {
			if execute_move(move, board) != board {
				break
			}
		}
		if move == 4 {
			break
		}

		current_score = int32(score_board(board)) - scorepenalty
		moveno++
		fmt.Printf("Move #%d, current score=%d(+%d)\n", moveno, current_score, current_score-last_score)
		last_score = current_score

		move = get_move(board)
		if move < 0 {
			break
		}

		if move == RETRACT {
			if moveno <= 1 || retract_num <= 0 {
				moveno--
				continue
			}
			moveno -= 2
			if retract_pos == 0 && retract_num > 0 {
				retract_pos = MAX_RETRACT
			}
			retract_pos--
			board = retract_vec[retract_pos]
			scorepenalty -= retract_penalty_vec[retract_pos]
			retract_num--
			continue
		}

		newboard = execute_move(move, board)
		if newboard == board {
			moveno--
			continue
		}

		tile = draw_tile()
		if tile == 2 {
			scorepenalty += 4
			retract_penalty_vec[retract_pos] = 4
		} else {
			retract_penalty_vec[retract_pos] = 0
		}
		retract_vec[retract_pos] = board
		retract_pos++
		if retract_pos == MAX_RETRACT {
			retract_pos = 0
		}
		if retract_num < MAX_RETRACT {
			retract_num++
		}

		board = insert_tile_rand(newboard, tile)
	}

	print_board(board)
	fmt.Printf("Game over. Your score is %d.\n", current_score)
}

func main() {
	C.term_init()
	init_tables()
	play_game(ask_for_move)
	C.term_clear()
}
