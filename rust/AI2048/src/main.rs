#![allow(non_snake_case)]
extern crate clearscreen;
extern crate num_cpus;
extern crate rand;
extern crate rayon;
use rand::Rng;
use rayon::prelude::*;
use std::collections::HashMap;

type BoardT = u64;
type RowT = u16;
type ScoreT = u32;

const ROW_MASK: BoardT = 0xFFFF;
const COL_MASK: BoardT = 0x000F000F000F000F;

const UP: i32 = 0;
const DOWN: i32 = 1;
const LEFT: i32 = 2;
const RIGHT: i32 = 3;

const TABLESIZE: usize = 65536;

type ScoreHeurT = f64;

const SCORE_LOST_PENALTY: ScoreHeurT = 200000.0;
const SCORE_MONOTONICITY_POWER: ScoreHeurT = 4.0;
const SCORE_MONOTONICITY_WEIGHT: ScoreHeurT = 47.0;
const SCORE_SUM_POWER: ScoreHeurT = 3.5;
const SCORE_SUM_WEIGHT: ScoreHeurT = 11.0;
const SCORE_MERGES_WEIGHT: ScoreHeurT = 700.0;
const SCORE_EMPTY_WEIGHT: ScoreHeurT = 270.0;
const CPROB_THRESH_BASE: ScoreHeurT = 0.0001;
const CACHE_DEPTH_LIMIT: u32 = 15;

struct TransTableEntryT {
    depth: u32,
    heuristic: ScoreHeurT,
}

struct EvalState {
    trans_table: HashMap<BoardT, TransTableEntryT>,
    maxdepth: u32,
    curdepth: u32,
    nomoves: u32,
    tablehits: u32,
    cachehits: u32,
    moves_evaled: u32,
    depth_limit: u32,
}

impl EvalState {
    fn new() -> EvalState {
        EvalState {
            trans_table: HashMap::new(),
            maxdepth: 0,
            curdepth: 0,
            nomoves: 0,
            tablehits: 0,
            cachehits: 0,
            moves_evaled: 0,
            depth_limit: 0,
        }
    }
}

struct AI2048 {
    row_left_table: [RowT; TABLESIZE],
    row_right_table: [RowT; TABLESIZE],
    score_table: [ScoreT; TABLESIZE],
    score_heur_table: [ScoreHeurT; TABLESIZE],
}

impl AI2048 {
    fn new() -> AI2048 {
        AI2048 {
            row_left_table: [0; TABLESIZE],
            row_right_table: [0; TABLESIZE],
            score_table: [0; TABLESIZE],
            score_heur_table: [0.0; TABLESIZE],
        }
    }

    fn clear_screen() {
        clearscreen::clear().expect("failed to clear screen");
    }

    fn unif_random(n: u32) -> u32 {
        let mut rng = rand::thread_rng();

        rng.gen_range(0..n)
    }

    fn unpack_col(row: RowT) -> BoardT {
        let tmp: BoardT = row as BoardT;

        (tmp | (tmp << 12) | (tmp << 24) | (tmp << 36)) & COL_MASK
    }

    fn reverse_row(row: RowT) -> RowT {
        (row >> 12) | ((row >> 4) & 0x00F0) | ((row << 4) & 0x0F00) | (row << 12)
    }

    fn print_board(board: BoardT) {
        let mut board = board;
        println!("-----------------------------");
        for _i in 0..4 {
            for _j in 0..4 {
                let power_val = board & 0xf;

                if power_val == 0 {
                    print!("|{ch:>width$}", ch = ' ', width = 6);
                } else {
                    print!("|{num:>width$}", num = 1 << power_val, width = 6);
                }
                board >>= 4;
            }
            println!("|");
        }
        println!("-----------------------------");
    }

    fn transpose(x: BoardT) -> BoardT {
        let a1 = x & 0xF0F00F0FF0F00F0F;
        let a2 = x & 0x0000F0F00000F0F0;
        let a3 = x & 0x0F0F00000F0F0000;
        let a = a1 | (a2 << 12) | (a3 >> 12);
        let b1 = a & 0xFF00FF0000FF00FF;
        let b2 = a & 0x00FF00FF00000000;
        let b3 = a & 0x00000000FF00FF00;

        b1 | (b2 >> 24) | (b3 << 24)
    }

    fn count_empty(x: BoardT) -> u32 {
        let mut x = x;
        x |= (x >> 2) & 0x3333333333333333;
        x |= x >> 1;
        x = !x & 0x1111111111111111;
        x += x >> 32;
        x += x >> 16;
        x += x >> 8;
        x += x >> 4;
        (x & 0xf) as u32
    }

    fn init_tables(&mut self) {
        let mut row: RowT = 0;

        loop {
            let mut line: [RowT; 4] = [
                row & 0xf,
                (row >> 4) & 0xf,
                (row >> 8) & 0xf,
                (row >> 12) & 0xf,
            ];
            let mut score: ScoreT = 0;

            for i in 0..4 {
                let rank: ScoreT = line[i] as ScoreT;

                if rank >= 2 {
                    score += (rank - 1) * (1 << rank);
                }
            }
            self.score_table[row as usize] = score;

            let mut sum: ScoreHeurT = 0.0;
            let mut empty: ScoreT = 0;
            let mut merges: ScoreT = 0;
            let mut prev: ScoreT = 0;
            let mut counter: ScoreT = 0;

            for i in 0..4 {
                let rank: ScoreT = line[i] as ScoreT;

                sum += (rank as ScoreHeurT).powf(SCORE_SUM_POWER);
                if rank == 0 {
                    empty += 1;
                } else {
                    if prev == rank {
                        counter += 1;
                    } else if counter > 0 {
                        merges += 1 + counter;
                        counter = 0;
                    }
                    prev = rank;
                }
            }
            if counter > 0 {
                merges += 1 + counter;
            }

            let mut monotonicity_left: ScoreHeurT = 0.0;
            let mut monotonicity_right: ScoreHeurT = 0.0;

            for i in 1..4 {
                if line[i - 1] > line[i] {
                    monotonicity_left += (line[i - 1] as ScoreHeurT).powf(SCORE_MONOTONICITY_POWER)
                        - (line[i] as ScoreHeurT).powf(SCORE_MONOTONICITY_POWER);
                } else {
                    monotonicity_right += (line[i] as ScoreHeurT).powf(SCORE_MONOTONICITY_POWER)
                        - (line[i - 1] as ScoreHeurT).powf(SCORE_MONOTONICITY_POWER);
                }
            }

            self.score_heur_table[row as usize] = SCORE_LOST_PENALTY
                + SCORE_EMPTY_WEIGHT * empty as ScoreHeurT
                + SCORE_MERGES_WEIGHT * merges as ScoreHeurT
                - SCORE_MONOTONICITY_WEIGHT * monotonicity_left.min(monotonicity_right)
                - SCORE_SUM_WEIGHT * sum;

            let mut i = 0;
            while i < 3 {
                let mut j = i + 1;
                while j < 4 {
                    if line[j] != 0 {
                        break;
                    }
                    j += 1;
                }
                if j == 4 {
                    break;
                }

                if line[i] == 0 {
                    line[i] = line[j];
                    line[j] = 0;
                    i -= 1;
                } else if line[i] == line[j] {
                    if line[i] != 0xf {
                        line[i] += 1;
                    }
                    line[j] = 0;
                }
                i += 1;
            }

            let result = line[0] | (line[1] << 4) | (line[2] << 8) | (line[3] << 12);

            let rev_row = Self::reverse_row(row);
            let rev_result = Self::reverse_row(result);
            self.row_left_table[row as usize] = row ^ result;
            self.row_right_table[rev_row as usize] = rev_row ^ rev_result;

            if row == 0xFFFF {
                break;
            }
            row += 1;
        }
    }

    fn execute_move(&self, mut board: BoardT, move_: i32) -> BoardT {
        let mut ret = board;

        if move_ == UP {
            board = Self::transpose(board);
            ret ^= Self::unpack_col(self.row_left_table[(board & ROW_MASK) as usize]);
            ret ^= Self::unpack_col(self.row_left_table[((board >> 16) & ROW_MASK) as usize]) << 4;
            ret ^= Self::unpack_col(self.row_left_table[((board >> 32) & ROW_MASK) as usize]) << 8;
            ret ^= Self::unpack_col(self.row_left_table[((board >> 48) & ROW_MASK) as usize]) << 12;
        } else if move_ == DOWN {
            board = Self::transpose(board);
            ret ^= Self::unpack_col(self.row_right_table[(board & ROW_MASK) as usize]);
            ret ^= Self::unpack_col(self.row_right_table[((board >> 16) & ROW_MASK) as usize]) << 4;
            ret ^= Self::unpack_col(self.row_right_table[((board >> 32) & ROW_MASK) as usize]) << 8;
            ret ^=
                Self::unpack_col(self.row_right_table[((board >> 48) & ROW_MASK) as usize]) << 12;
        } else if move_ == LEFT {
            ret ^= (self.row_left_table[(board & ROW_MASK) as usize]) as BoardT;
            ret ^= ((self.row_left_table[((board >> 16) & ROW_MASK) as usize]) as BoardT) << 16;
            ret ^= ((self.row_left_table[((board >> 32) & ROW_MASK) as usize]) as BoardT) << 32;
            ret ^= ((self.row_left_table[((board >> 48) & ROW_MASK) as usize]) as BoardT) << 48;
        } else if move_ == RIGHT {
            ret ^= (self.row_right_table[(board & ROW_MASK) as usize]) as BoardT;
            ret ^= ((self.row_right_table[((board >> 16) & ROW_MASK) as usize]) as BoardT) << 16;
            ret ^= ((self.row_right_table[((board >> 32) & ROW_MASK) as usize]) as BoardT) << 32;
            ret ^= ((self.row_right_table[((board >> 48) & ROW_MASK) as usize]) as BoardT) << 48;
        }
        ret
    }

    fn score_helper(&self, board: BoardT) -> ScoreT {
        self.score_table[(board & ROW_MASK) as usize]
            + self.score_table[((board >> 16) & ROW_MASK) as usize]
            + self.score_table[((board >> 32) & ROW_MASK) as usize]
            + self.score_table[((board >> 48) & ROW_MASK) as usize]
    }

    fn score_heur_helper(&self, board: BoardT) -> ScoreHeurT {
        self.score_heur_table[(board & ROW_MASK) as usize]
            + self.score_heur_table[((board >> 16) & ROW_MASK) as usize]
            + self.score_heur_table[((board >> 32) & ROW_MASK) as usize]
            + self.score_heur_table[((board >> 48) & ROW_MASK) as usize]
    }

    fn score_board(&self, board: BoardT) -> ScoreT {
        Self::score_helper(self, board)
    }

    fn score_heur_board(&self, board: BoardT) -> ScoreHeurT {
        Self::score_heur_helper(self, board) + Self::score_heur_helper(self, Self::transpose(board))
    }

    fn draw_tile() -> RowT {
        if Self::unif_random(10) < 9 {
            1
        } else {
            2
        }
    }

    fn insert_tile_rand(board: BoardT, mut tile: BoardT) -> BoardT {
        let mut index = Self::unif_random(Self::count_empty(board));
        let mut tmp = board;

        loop {
            while (tmp & 0xf) != 0 {
                tmp >>= 4;
                tile <<= 4;
            }
            if index == 0 {
                break;
            }
            index -= 1;
            tmp >>= 4;
            tile <<= 4;
        }
        board | tile
    }

    fn initial_board() -> BoardT {
        let board = ((Self::draw_tile()) << (Self::unif_random(16) << 2)) as BoardT;

        Self::insert_tile_rand(board, Self::draw_tile() as BoardT)
    }

    fn get_depth_limit(mut board: BoardT) -> u32 {
        let mut bitset: u32 = 0;
        let mut max_limit: u32 = 0;
        let mut count: u32 = 0;

        while board != 0 {
            bitset |= 1 << (board & 0xf);
            board >>= 4;
        }

        if bitset <= 2048 {
            return 3;
        } else if bitset <= 2048 + 1024 {
            max_limit = 4;
        } else if bitset <= 4096 {
            max_limit = 5;
        } else if bitset <= 4096 + 2048 {
            max_limit = 6;
        }

        bitset >>= 1;
        while bitset != 0 {
            bitset &= bitset - 1;
            count += 1;
        }
        count -= 2;
        count = count.max(3);
        if max_limit != 0 {
            count = count.min(max_limit);
        }
        count
    }

    fn score_tilechoose_node(
        &self,
        state: &mut EvalState,
        board: BoardT,
        mut cprob: ScoreHeurT,
    ) -> ScoreHeurT {
        if cprob < CPROB_THRESH_BASE || state.curdepth >= state.depth_limit {
            state.maxdepth = state.curdepth.max(state.maxdepth);
            state.tablehits += 1;
            return Self::score_heur_board(self, board);
        }
        if state.curdepth < CACHE_DEPTH_LIMIT {
            if state.trans_table.contains_key(&board) {
                let entry: &TransTableEntryT = state.trans_table.get(&board).unwrap();

                if entry.depth <= state.curdepth {
                    state.cachehits += 1;
                    return entry.heuristic;
                }
            }
        }

        let num_open = Self::count_empty(board);

        cprob /= num_open as ScoreHeurT;

        let mut res: ScoreHeurT = 0.0;
        let mut tmp: BoardT = board;
        let mut tile_2: BoardT = 1;

        while tile_2 != 0 {
            if (tmp & 0xf) == 0 {
                res += Self::score_move_node(self, state, board | tile_2, cprob * 0.9) * 0.9;
                res += Self::score_move_node(self, state, board | (tile_2 << 1), cprob * 0.1) * 0.1;
            }
            tmp >>= 4;
            tile_2 <<= 4;
        }
        res = res / num_open as ScoreHeurT;

        if state.curdepth < CACHE_DEPTH_LIMIT {
            let entry: TransTableEntryT = TransTableEntryT {
                depth: state.curdepth,
                heuristic: res,
            };
            state.trans_table.entry(board).or_insert(entry);
        }

        res
    }

    fn score_move_node(
        &self,
        state: &mut EvalState,
        board: BoardT,
        cprob: ScoreHeurT,
    ) -> ScoreHeurT {
        let mut best: ScoreHeurT = 0.0;

        state.curdepth += 1;
        for move_ in 0..4 {
            let newboard = Self::execute_move(self, board, move_);

            state.moves_evaled += 1;
            if board != newboard {
                let tmp = Self::score_tilechoose_node(self, state, newboard, cprob);
                if best < tmp {
                    best = tmp;
                }
            } else {
                state.nomoves += 1;
            }
        }
        state.curdepth -= 1;

        best
    }

    fn score_toplevel_move(&self, board: BoardT, move_: i32) -> ScoreHeurT {
        let mut state: EvalState = EvalState::new();
        let mut res = 0.0;
        let newboard = Self::execute_move(self, board, move_);

        state.depth_limit = Self::get_depth_limit(board);
        if board != newboard {
            res = Self::score_tilechoose_node(self, &mut state, newboard, 1.0) + 1e-6;
        }

        println!(
           "Move {move_}: result {res}: eval'd {moves_evaled} moves ({nomoves} no moves, {tablehits} table hits, {cachehits} cache hits, {trans_table_size} cache size) (maxdepth={maxdepth})",
           move_=move_, res=res, moves_evaled=state.moves_evaled, nomoves=state.nomoves,
           tablehits=state.tablehits, cachehits=state.cachehits, trans_table_size=state.trans_table.len(),
           maxdepth=state.maxdepth
        );

        res
    }

    fn find_best_move(&self, board: BoardT) -> i32 {
        let mut best: ScoreHeurT = 0.0;
        let mut bestmove: i32 = -1;

        Self::print_board(board);
        println!(
            "Current scores: heur {heur}, actual {actual}",
            heur = Self::score_heur_board(self, board),
            actual = Self::score_board(self, board)
        );

        let res: Vec<_> = (0..4)
            .into_par_iter()
            .map(|move_| Self::score_toplevel_move(self, board, move_))
            .collect();

        for move_ in 0..4 {
            if res[move_] > best {
                best = res[move_];
                bestmove = move_ as i32;
            }
        }

        println!(
            "Selected bestmove: {bestmove}, result: {best}",
            bestmove = bestmove,
            best = best
        );

        bestmove
    }

    fn play_game(&mut self) {
        let mut board = Self::initial_board();
        let mut scorepenalty: i32 = 0;
        let mut last_score: i32 = 0;
        let mut current_score: i32 = 0;
        let mut moveno: i32 = 0;

        Self::init_tables(self);
        rayon::ThreadPoolBuilder::new()
            .num_threads(if num_cpus::get() >= 4 { 4 } else { 0 })
            .build_global()
            .unwrap();
        loop {
            let mut move_: i32 = 0;

            Self::clear_screen();
            while move_ < 4 {
                if Self::execute_move(&self, board, move_) != board {
                    break;
                }
                move_ += 1;
            }
            if move_ == 4 {
                break;
            }

            current_score = Self::score_board(&self, board) as i32 - scorepenalty;
            moveno += 1;
            println!(
                "Move #{moveno}, current score={current_score}(+{increased_score})",
                moveno = moveno,
                current_score = current_score,
                increased_score = current_score - last_score
            );
            last_score = current_score;

            move_ = Self::find_best_move(self, board);
            if move_ < 0 {
                break;
            }

            let newboard = Self::execute_move(&self, board, move_);
            if newboard == board {
                moveno -= 1;
                continue;
            }

            let tile = Self::draw_tile();
            if tile == 2 {
                scorepenalty += 4;
            }

            board = Self::insert_tile_rand(newboard, tile as BoardT);
        }

        Self::print_board(board);
        println!(
            "Game over. Your score is {current_score}.",
            current_score = current_score
        );
    }
}

fn main() {
    let mut obj = AI2048::new();
    obj.play_game();
}
