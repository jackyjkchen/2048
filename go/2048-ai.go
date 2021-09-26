package main

/*
extern void clear_screen(void);
#cgo LDFLAGS: -L. -lgodeps
*/
import "C"

import (
	"fmt"
	"math"
	"math/rand"
	"sync"
	"time"
)

type board_t uint64
type row_t uint16

const ROW_MASK board_t = 0xFFFF
const COL_MASK board_t = 0x000F000F000F000F

const (
	UP    = 0
	DOWN  = 1
	LEFT  = 2
	RIGHT = 3
)

type get_move_func_t func(board board_t) int

const TABLESIZE = 65536

var row_table [TABLESIZE]row_t
var score_table [TABLESIZE]uint32
var score_heur_table [TABLESIZE]float64

type trans_table_entry_t struct {
	depth     int
	heuristic float64
}

type eval_state struct {
	trans_table  map[board_t]trans_table_entry_t
	maxdepth     int
	curdepth     int
	nomoves      int
	tablehits    int
	cachehits    int
	moves_evaled int
	depth_limit  int
}

const SCORE_LOST_PENALTY = 200000.0
const SCORE_MONOTONICITY_POWER = 4.0
const SCORE_MONOTONICITY_WEIGHT = 47.0
const SCORE_SUM_POWER = 3.5
const SCORE_SUM_WEIGHT = 11.0
const SCORE_MERGES_WEIGHT = 700.0
const SCORE_EMPTY_WEIGHT = 270.0
const CPROB_THRESH_BASE = 0.0001
const CACHE_DEPTH_LIMIT = 15

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
	var row, result row_t = 0, 0

	for true {
		i := 0
		j := 0
		var line [4]row_t
		var score uint32 = 0

		line[0] = row & 0xf
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

		sum := 0.0
		empty := 0
		merges := 0
		prev := 0
		counter := 0

		for i = 0; i < 4; i++ {
			var rank int = int(line[i])

			sum += math.Pow(float64(rank), SCORE_SUM_POWER)
			if rank == 0 {
				empty++
			} else {
				if prev == rank {
					counter++
				} else if counter > 0 {
					merges += 1 + counter
					counter = 0
				}
				prev = rank
			}
		}
		if counter > 0 {
			merges += 1 + counter
		}

		monotonicity_left := 0.0
		monotonicity_right := 0.0

		for i = 1; i < 4; i++ {
			if line[i-1] > line[i] {
				monotonicity_left +=
					math.Pow(float64(line[i-1]), SCORE_MONOTONICITY_POWER) - math.Pow(float64(line[i]), SCORE_MONOTONICITY_POWER)
			} else {
				monotonicity_right +=
					math.Pow(float64(line[i]), SCORE_MONOTONICITY_POWER) - math.Pow(float64(line[i-1]), SCORE_MONOTONICITY_POWER)
			}
		}

		score_heur_table[row] = SCORE_LOST_PENALTY + SCORE_EMPTY_WEIGHT*float64(empty) + SCORE_MERGES_WEIGHT*float64(merges) -
			SCORE_MONOTONICITY_WEIGHT*math.Min(monotonicity_left, monotonicity_right) - SCORE_SUM_WEIGHT*sum

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

		result = line[0] | (line[1] << 4) | (line[2] << 8) | (line[3] << 12)
		row_table[row] = row ^ result

		if row == TABLESIZE-1 {
			break
		}
		row++
	}
}

func execute_move_col(board board_t, move int) board_t {
	var ret board_t = board
	var t board_t = transpose(board)

	if move == UP {
		ret ^= unpack_col(row_table[t&ROW_MASK])
		ret ^= unpack_col(row_table[(t>>16)&ROW_MASK]) << 4
		ret ^= unpack_col(row_table[(t>>32)&ROW_MASK]) << 8
		ret ^= unpack_col(row_table[(t>>48)&ROW_MASK]) << 12
	} else if move == DOWN {
		ret ^= unpack_col(reverse_row(row_table[reverse_row(row_t(t&ROW_MASK))]))
		ret ^= unpack_col(reverse_row(row_table[reverse_row(row_t((t>>16)&ROW_MASK))])) << 4
		ret ^= unpack_col(reverse_row(row_table[reverse_row(row_t((t>>32)&ROW_MASK))])) << 8
		ret ^= unpack_col(reverse_row(row_table[reverse_row(row_t((t>>48)&ROW_MASK))])) << 12
	}
	return ret
}

func execute_move_row(board board_t, move int) board_t {
	var ret board_t = board

	if move == LEFT {
		ret ^= board_t(row_table[board&ROW_MASK])
		ret ^= board_t(row_table[(board>>16)&ROW_MASK]) << 16
		ret ^= board_t(row_table[(board>>32)&ROW_MASK]) << 32
		ret ^= board_t(row_table[(board>>48)&ROW_MASK]) << 48
	} else if move == RIGHT {
		ret ^= board_t(reverse_row(row_table[reverse_row(row_t(board&ROW_MASK))]))
		ret ^= board_t(reverse_row(row_table[reverse_row(row_t((board>>16)&ROW_MASK))])) << 16
		ret ^= board_t(reverse_row(row_table[reverse_row(row_t((board>>32)&ROW_MASK))])) << 32
		ret ^= board_t(reverse_row(row_table[reverse_row(row_t((board>>48)&ROW_MASK))])) << 48
	}
	return ret
}

func execute_move(move int, board board_t) board_t {
	if move == UP || move == DOWN {
		return execute_move_col(board, move)
	} else if move == LEFT || move == RIGHT {
		return execute_move_row(board, move)
	} else {
		return 0xFFFFFFFFFFFFFFFF
	}
}

func score_helper(board board_t) uint32 {
	return score_table[board&ROW_MASK] + score_table[(board>>16)&ROW_MASK] +
		score_table[(board>>32)&ROW_MASK] + score_table[(board>>48)&ROW_MASK]
}

func score_heur_helper(board board_t) float64 {
	return score_heur_table[board&ROW_MASK] + score_heur_table[(board>>16)&ROW_MASK] +
		score_heur_table[(board>>32)&ROW_MASK] + score_heur_table[(board>>48)&ROW_MASK]
}

func score_board(board board_t) uint32 {
	return score_helper(board)
}

func score_heur_board(board board_t) float64 {
	return score_heur_helper(board) + score_heur_helper(transpose(board))
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

func get_depth_limit(board board_t) int {
	var bitset uint16 = 0
	var max_limit = 0

	for board != 0 {
		bitset |= 1 << (board & 0xf)
		board >>= 4
	}

	if bitset <= 2048 {
		max_limit = 3
	} else if bitset <= 2048+1024 {
		max_limit = 4
	} else if bitset <= 4096 {
		max_limit = 5
	} else if bitset <= 4096+2048 {
		max_limit = 6
	}
	bitset >>= 1
	count := 0
	for bitset != 0 {
		bitset &= bitset - 1
		count++
	}
	count -= 2
	if count < 3 {
		count = 3
	}
	if max_limit != 0 {
		if count > max_limit {
			count = max_limit
		}
	}
	return count
}

func score_tilechoose_node(state *eval_state, board board_t, cprob float64) float64 {
	if cprob < CPROB_THRESH_BASE || state.curdepth >= state.depth_limit {
		if state.curdepth > state.maxdepth {
			state.maxdepth = state.curdepth
		}
		state.tablehits++
		return score_heur_board(board)
	}
	if state.curdepth < CACHE_DEPTH_LIMIT {
		entry, exist := state.trans_table[board]
		if exist {
			if entry.depth <= state.curdepth {
				state.cachehits++
				return entry.heuristic
			}
		}
	}

	num_open := float64(count_empty(board))

	cprob /= num_open

	res := 0.0
	var tmp board_t = board
	var tile_2 board_t = 1

	for tile_2 != 0 {
		if (tmp & 0xf) == 0 {
			res += score_move_node(state, board|tile_2, cprob*0.9) * 0.9
			res += score_move_node(state, board|(tile_2<<1), cprob*0.1) * 0.1
		}
		tmp >>= 4
		tile_2 <<= 4
	}
	res = res / num_open

	if state.curdepth < CACHE_DEPTH_LIMIT {
		entry := trans_table_entry_t{state.curdepth, res}
		state.trans_table[board] = entry
	}

	return res
}

func score_move_node(state *eval_state, board board_t, cprob float64) float64 {
	var best float64 = 0.0

	state.curdepth++
	for move := 0; move < 4; move++ {
		var newboard board_t = execute_move(move, board)

		state.moves_evaled++

		if board != newboard {
			best = math.Max(best, score_tilechoose_node(state, newboard, cprob))
		} else {
			state.nomoves++
		}
	}
	state.curdepth--

	return best
}

func _score_toplevel_move(state *eval_state, board board_t, move int) float64 {
	var newboard board_t = execute_move(move, board)

	if board == newboard {
		return 0.0
	}

	return score_tilechoose_node(state, newboard, 1.0) + 0.000001
}

func score_toplevel_move(board board_t, move int, res *float64, wg *sync.WaitGroup) {
	defer wg.Done()
	var state eval_state

	state.trans_table = make(map[board_t]trans_table_entry_t)
	state.depth_limit = get_depth_limit(board)

	*res = _score_toplevel_move(&state, board, move)

	fmt.Printf("Move %d: result %f: eval'd %d moves (%d no moves, %d table hits, %d cache hits, %d cache size) (maxdepth=%d)\n", move, *res,
		state.moves_evaled, state.nomoves, state.tablehits, state.cachehits, len(state.trans_table), state.maxdepth)
}

func find_best_move(board board_t) int {
	best := 0.0
	bestmove := -1

	print_board(board)
	fmt.Printf("Current scores: heur %d, actual %d\n", uint32(score_heur_board(board)), uint32(score_board(board)))

	var wg sync.WaitGroup
	wg.Add(4)
	res := [4]float64{}
	for move := 0; move < 4; move++ {
		go score_toplevel_move(board, move, &res[move], &wg)
	}
	wg.Wait()

	for move := 0; move < 4; move++ {
		if res[move] > best {
			best = res[move]
			bestmove = move
		}
	}
	fmt.Printf("Selected bestmove: %d, result: %f\n", bestmove, best)

	return bestmove
}

func play_game(get_move get_move_func_t) {
	var board board_t = initial_board()
	var scorepenalty int32 = 0
	var current_score int32 = 0
	var last_score int32 = 0
	moveno := 0

	init_tables()
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

		newboard = execute_move(move, board)
		if newboard == board {
			moveno--
			continue
		}

		tile = draw_tile()
		if tile == 2 {
			scorepenalty += 4
		}

		board = insert_tile_rand(newboard, tile)
	}

	print_board(board)
	fmt.Printf("Game over. Your score is %d.\n", current_score)
}

func main() {
	play_game(find_best_move)
}
