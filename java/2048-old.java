import java.util.Random;

class Game2048
{
    Random rand = new Random();
    final long ROW_MASK = 0xFFFFL;
    final long COL_MASK = 0x000F000F000F000FL;
    final int TABLESIZE = 65536;
    int[] row_table = new int[TABLESIZE];
    int[] score_table = new int[TABLESIZE];

    final int UP = 0;
    final int DOWN = 1;
    final int LEFT = 2;
    final int RIGHT = 3;
    final int RETRACT = 4;

    int unif_random(int n) {
        return Math.abs(rand.nextInt() % n);
    }

    static {
        System.loadLibrary("javadeps");
    }

    private native void clear_screen();

    private native char get_ch();

    long unpack_col(int row) {
        long tmp = row & 0xFFFF;
        return (tmp | (tmp << 12) | (tmp << 24) | (tmp << 36)) & COL_MASK;
    }

    int reverse_row(int row) {
        row &= 0xFFFF;
        return ((row >> 12) | ((row >> 4) & 0x00F0) | ((row << 4) & 0x0F00) | (row << 12)) & 0xFFFF;
    }

    void print_board(long board) {
        System.out.println("-----------------------------");
        String pad = "      ";
        for (int i = 0; i < 4; i++) {
            for (int j = 0; j < 4; j++) {
                int power_val = (int)(board & 0xf);
                if (power_val == 0) {
                    System.out.print("|      ");
                } else {
                    String value = Integer.toString(1 << power_val);
                    String padded = (pad.substring(0, pad.length() - value.length())) + value;
                    System.out.print("|" + padded);
                }
                board >>= 4;
            }
            System.out.println("|");
        }
        System.out.println("-----------------------------");
    }

    long transpose(long x) {
        long a1 = x & 0xF0F00F0FF0F00F0FL;
        long a2 = x & 0x0000F0F00000F0F0L;
        long a3 = x & 0x0F0F00000F0F0000L;
        long a = a1 | (a2 << 12) | (a3 >> 12);
        long b1 = a & 0xFF00FF0000FF00FFL;
        long b2 = a & 0x00FF00FF00000000L;
        long b3 = a & 0x00000000FF00FF00L;

        return b1 | (b2 >> 24) | (b3 << 24);
    }

    int count_empty(long x) {
        x |= (x >> 2) & 0x3333333333333333L;
        x |= (x >> 1);
        x = ~x & 0x1111111111111111L;
        x += x >> 32;
        x += x >> 16;
        x += x >> 8;
        x += x >> 4;
        return (int)(x & 0xf);
    }

    void init_tables() {
        int row = 0, result = 0;
        int[] line = new int[4];

        do {
            int i = 0, j = 0;
            int score = 0;
            line[0] = row & 0xf;
            line[1] = (row >> 4) & 0xf;
            line[2] = (row >> 8) & 0xf;
            line[3] = (row >> 12) & 0xf;

            for (i = 0; i < 4; ++i) {
                int rank = line[i];
                if (rank >= 2) {
                    score += (int)((rank - 1) * (1 << rank));
                }
            }
            score_table[row] = score;

            for (i = 0; i < 3; ++i) {
                for (j = i + 1; j < 4; ++j) {
                    if (line[j] != 0)
                        break;
                }
                if (j == 4)
                    break;

                if (line[i] == 0) {
                    line[i] = line[j];
                    line[j] = 0;
                    i--;
                }
                else if (line[i] == line[j]) {
                    if (line[i] != 0xf) {
                        line[i]++;
                    }
                    line[j] = 0;
                }
            }

            result = line[0] | (line[1] << 4) | (line[2] << 8) | (line[3] << 12);
            row_table[row] = row ^ result;
        } while (row++ != 0xFFFF);
    }

    long execute_move_col(long board, int move) {
        long ret = board;
        long t = transpose(board);

        if (move == UP) {
            ret ^= unpack_col(row_table[(int)(t & ROW_MASK)]);
            ret ^= unpack_col(row_table[(int)((t >> 16) & ROW_MASK)]) << 4;
            ret ^= unpack_col(row_table[(int)((t >> 32) & ROW_MASK)]) << 8;
            ret ^= unpack_col(row_table[(int)((t >> 48) & ROW_MASK)]) << 12;
        } else if (move == DOWN) {
            ret ^= unpack_col(reverse_row(row_table[reverse_row((int)(t & ROW_MASK))]));
            ret ^= unpack_col(reverse_row(row_table[reverse_row((int)((t >> 16) & ROW_MASK))])) << 4;
            ret ^= unpack_col(reverse_row(row_table[reverse_row((int)((t >> 32) & ROW_MASK))])) << 8;
            ret ^= unpack_col(reverse_row(row_table[reverse_row((int)((t >> 48) & ROW_MASK))])) << 12;
        }
        return ret;
    }

    long execute_move_row(long board, int move) {
        long ret = board;

        if (move == LEFT) {
            ret ^= (long)(row_table[(int)(board & ROW_MASK)]);
            ret ^= (long)(row_table[(int)((board >> 16) & ROW_MASK)]) << 16;
            ret ^= (long)(row_table[(int)((board >> 32) & ROW_MASK)]) << 32;
            ret ^= (long)(row_table[(int)((board >> 48) & ROW_MASK)]) << 48;
        } else if (move == RIGHT) {
            ret ^= (long)(reverse_row(row_table[reverse_row((int)(board & ROW_MASK))]));
            ret ^= (long)(reverse_row(row_table[reverse_row((int)((board >> 16) & ROW_MASK))])) << 16;
            ret ^= (long)(reverse_row(row_table[reverse_row((int)((board >> 32) & ROW_MASK))])) << 32;
            ret ^= (long)(reverse_row(row_table[reverse_row((int)((board >> 48) & ROW_MASK))])) << 48;
        }
        return ret;
    }

    long execute_move(int move, long board) {
        switch (move) {
            case UP:
            case DOWN:
                return execute_move_col(board, move);
            case LEFT:
            case RIGHT:
                return execute_move_row(board, move);
            default:
                return 0xFFFFFFFFFFFFFFFFL;
        }
    }

    int score_helper(long board) {
        return score_table[(int)(board & ROW_MASK)] + score_table[(int)((board >> 16) & ROW_MASK)] +
            score_table[(int)((board >> 32) & ROW_MASK)] + score_table[(int)((board >> 48) & ROW_MASK)];
    }

    int score_board(long board) {
        return score_helper(board);
    }

    long draw_tile() {
        return (long)((unif_random(10) < 9) ? 1 : 2);
    }

    long insert_tile_rand(long board, long tile) {
        int index = unif_random(count_empty(board));
        long tmp = board;

        while (true) {
            while ((tmp & 0xf) != 0) {
                tmp >>= 4;
                tile <<= 4;
            }
            if (index == 0)
                break;
            --index;
            tmp >>= 4;
            tile <<= 4;
        }
        return board | tile;
    }

    long initial_board() {
        long board = (long)(draw_tile()) << (unif_random(16) << 2);

        return insert_tile_rand(board, draw_tile());
    }

    int ask_for_move(long board) {
        print_board(board);

        while (true) {
            final String allmoves = "wsadkjhl";
            int pos = 0;
            char movechar = get_ch();

            if (movechar == 'q') {
                return -1;
            } else if (movechar == 'r') {
                return RETRACT;
            }
            pos = allmoves.indexOf(movechar);
            if (pos != -1) {
                return pos % 4;
            }
        }
    }

    void play_game() {
        long board = initial_board();
        int scorepenalty = 0;
        int last_score = 0, current_score = 0, moveno = 0;
        final int MAX_RETRACT = 64;
        long[] retract_vec = new long[MAX_RETRACT];
        int[] retract_penalty_vec = new int[MAX_RETRACT];
        int retract_pos = 0, retract_num = 0;

        init_tables();
        while (true) {
            int move = 0;
            long tile = 0;
            long newboard;

            clear_screen();
            for (move = 0; move < 4; move++) {
                if (execute_move(move, board) != board)
                    break;
            }
            if (move == 4)
                break;

            current_score = (int)(score_board(board) - scorepenalty);
            System.out.println("Move #" + (++moveno) + ", current score=" + current_score + "(+" + (current_score - last_score) + ")");
            last_score = current_score;

            move = ask_for_move(board);
            if (move < 0)
                break;

            if (move == RETRACT) {
                if (moveno <= 1 || retract_num <= 0) {
                    moveno--;
                    continue;
                }
                moveno -= 2;
                if (retract_pos == 0 && retract_num > 0)
                    retract_pos = MAX_RETRACT;
                board = retract_vec[--retract_pos];
                scorepenalty -= retract_penalty_vec[retract_pos];
                retract_num--;
                continue;
            }

            newboard = execute_move(move, board);
            if (newboard == board) {
                moveno--;
                continue;
            }

            tile = draw_tile();
            if (tile == 2) {
                scorepenalty += 4;
                retract_penalty_vec[retract_pos] = 4;
            } else {
                retract_penalty_vec[retract_pos] = 0;
            }
            retract_vec[retract_pos++] = board;
            if (retract_pos == MAX_RETRACT)
                retract_pos = 0;
            if (retract_num < MAX_RETRACT)
                retract_num++;

            board = insert_tile_rand(newboard, tile);
        }

        print_board(board);
        System.out.println("Game over. Your score is " + current_score +  ".");
    }

    public static void main(String[] args) {
        Game2048 game_2048 = new Game2048();
        game_2048.play_game();
    }
}
