#![allow(non_snake_case)]
extern crate clearscreen;
extern crate getch;
extern crate rand;
use rand::Rng;

type BoardT = u64;
type RowT = u16;
type ScoreT = u32;

const ROW_MASK: BoardT = 0xFFFF;
const COL_MASK: BoardT = 0x000F000F000F000F;

const UP: i32 = 0;
const DOWN: i32 = 1;
const LEFT: i32 = 2;
const RIGHT: i32 = 3;
const RETRACT: i32 = 4;

const TABLESIZE: usize = 65536;

struct Game2048 {
    row_table: [RowT; TABLESIZE],
    score_table: [ScoreT; TABLESIZE],
}

impl Game2048 {
    fn new() -> Game2048 {
        Game2048 {
            row_table: [0; TABLESIZE],
            score_table: [0; TABLESIZE],
        }
    }

    fn get_ch() -> u8 {
        getch::Getch::new().getch().unwrap()
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
            self.row_table[row as usize] = row ^ result;

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
            ret ^= Self::unpack_col(self.row_table[(board & ROW_MASK) as usize]);
            ret ^= Self::unpack_col(self.row_table[((board >> 16) & ROW_MASK) as usize]) << 4;
            ret ^= Self::unpack_col(self.row_table[((board >> 32) & ROW_MASK) as usize]) << 8;
            ret ^= Self::unpack_col(self.row_table[((board >> 48) & ROW_MASK) as usize]) << 12;
        } else if move_ == DOWN {
            board = Self::transpose(board);
            ret ^= Self::unpack_col(Self::reverse_row(
                self.row_table[Self::reverse_row((board & ROW_MASK) as RowT) as usize],
            ));
            ret ^= Self::unpack_col(Self::reverse_row(
                self.row_table[Self::reverse_row(((board >> 16) & ROW_MASK) as RowT) as usize],
            )) << 4;
            ret ^= Self::unpack_col(Self::reverse_row(
                self.row_table[Self::reverse_row(((board >> 32) & ROW_MASK) as RowT) as usize],
            )) << 8;
            ret ^= Self::unpack_col(Self::reverse_row(
                self.row_table[Self::reverse_row(((board >> 48) & ROW_MASK) as RowT) as usize],
            )) << 12;
        } else if move_ == LEFT {
            ret ^= (self.row_table[(board & ROW_MASK) as usize]) as BoardT;
            ret ^= ((self.row_table[((board >> 16) & ROW_MASK) as usize]) as BoardT) << 16;
            ret ^= ((self.row_table[((board >> 32) & ROW_MASK) as usize]) as BoardT) << 32;
            ret ^= ((self.row_table[((board >> 48) & ROW_MASK) as usize]) as BoardT) << 48;
        } else if move_ == RIGHT {
            ret ^= (Self::reverse_row(
                self.row_table[Self::reverse_row((board & ROW_MASK) as RowT) as usize],
            )) as BoardT;
            ret ^= ((Self::reverse_row(
                self.row_table[Self::reverse_row(((board >> 16) & ROW_MASK) as RowT) as usize],
            )) as BoardT)
                << 16;
            ret ^= ((Self::reverse_row(
                self.row_table[Self::reverse_row(((board >> 32) & ROW_MASK) as RowT) as usize],
            )) as BoardT)
                << 32;
            ret ^= ((Self::reverse_row(
                self.row_table[Self::reverse_row(((board >> 48) & ROW_MASK) as RowT) as usize],
            )) as BoardT)
                << 48;
        }
        ret
    }

    fn score_helper(&self, board: BoardT) -> ScoreT {
        self.score_table[(board & ROW_MASK) as usize]
            + self.score_table[((board >> 16) & ROW_MASK) as usize]
            + self.score_table[((board >> 32) & ROW_MASK) as usize]
            + self.score_table[((board >> 48) & ROW_MASK) as usize]
    }

    fn score_board(&self, board: BoardT) -> ScoreT {
        Self::score_helper(self, board)
    }

    fn draw_tile() -> RowT {
        let ret;
        if Self::unif_random(10) < 9 {
            ret = 1;
        } else {
            ret = 2;
        }
        ret
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

    fn _find_move(allmoves: &[u8; 9], movechar: u8) -> i32 {
        let mut pos: i32 = 0;
        loop {
            let pos_char = allmoves[pos as usize];
            if pos_char == movechar {
                break;
            } else if pos_char == 0x00 {
                pos = -1;
                break;
            }
            pos += 1;
        }
        pos
    }

    fn ask_for_move(board: BoardT) -> i32 {
        Self::print_board(board);
        let ret: i32;

        loop {
            // wsadkjhl\0
            let allmoves: [u8; 9] = [0x77, 0x73, 0x61, 0x64, 0x6b, 0x6a, 0x68, 0x6c, 0x00];
            let movechar = Self::get_ch();

            // 0x71='q', 0x72='r'
            if movechar == 0x71 {
                ret = -1;
                break;
            } else if movechar == 0x72 {
                ret = RETRACT;
                break;
            }
            let pos = Self::_find_move(&allmoves, movechar);
            if pos >= 0 {
                ret = pos % 4;
                break;
            }
        }
        ret
    }

    fn play_game(&mut self) {
        let mut board = Self::initial_board();
        let mut scorepenalty: i32 = 0;
        let mut last_score: i32 = 0;
        let mut current_score: i32 = 0;
        let mut moveno: i32 = 0;
        const MAX_RETRACT: usize = 64;
        let mut retract_vec: [BoardT; MAX_RETRACT] = [0; MAX_RETRACT];
        let mut retract_penalty_vec: [RowT; MAX_RETRACT] = [0; MAX_RETRACT];
        let mut retract_pos: i32 = 0;
        let mut retract_num: i32 = 0;

        Self::init_tables(self);
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

            move_ = Self::ask_for_move(board);
            if move_ < 0 {
                break;
            }

            if move_ == RETRACT {
                if moveno <= 1 || retract_num <= 0 {
                    moveno -= 1;
                    continue;
                }
                moveno -= 2;
                if retract_pos == 0 && retract_num > 0 {
                    retract_pos = MAX_RETRACT as i32;
                }
                retract_pos -= 1;
                board = retract_vec[retract_pos as usize];
                scorepenalty -= retract_penalty_vec[retract_pos as usize] as i32;
                retract_num -= 1;
                continue;
            }

            let newboard = Self::execute_move(&self, board, move_);
            if newboard == board {
                moveno -= 1;
                continue;
            }

            let tile = Self::draw_tile();
            if tile == 2 {
                scorepenalty += 4;
                retract_penalty_vec[retract_pos as usize] = 4;
            } else {
                retract_penalty_vec[retract_pos as usize] = 0;
            }
            retract_vec[retract_pos as usize] = board;
            retract_pos += 1;
            if retract_pos == MAX_RETRACT as i32 {
                retract_pos = 0;
            }
            if retract_num < MAX_RETRACT as i32 {
                retract_num += 1;
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
    let mut obj = Game2048::new();
    obj.play_game();
}
