import java.util.Random;
import java.util.HashMap;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.Callable;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;

class Game2048
{
    Random rand = new Random();
    final long ROW_MASK = 0xFFFFL;
    final long COL_MASK = 0x000F000F000F000FL;
    final int TABLESIZE = 65536;
    int[] row_left_table = new int[TABLESIZE];
    int[] row_right_table = new int[TABLESIZE];
    int[] score_table = new int[TABLESIZE];
    double[] score_heur_table = new double[TABLESIZE];

    final int UP = 0;
    final int DOWN = 1;
    final int LEFT = 2;
    final int RIGHT = 3;

    class trans_table_entry_t
    {
        public int depth;
        public double heuristic;
        public trans_table_entry_t(int depth, double heuristic)
        {
            this.depth = depth;
            this.heuristic = heuristic;
        }
    }
    class eval_state
    {
        public HashMap<Long, trans_table_entry_t> trans_table = new HashMap<>();
        public int maxdepth;
        public int curdepth;
        public int nomoves;
        public int tablehits;
        public int cachehits;
        public int moves_evaled;
        public int depth_limit;
    }

    final double SCORE_LOST_PENALTY = 200000.0f;
    final double SCORE_MONOTONICITY_POWER = 4.0f;
    final double SCORE_MONOTONICITY_WEIGHT = 47.0f;
    final double SCORE_SUM_POWER = 3.5f;
    final double SCORE_SUM_WEIGHT = 11.0f;
    final double SCORE_MERGES_WEIGHT = 700.0f;
    final double SCORE_EMPTY_WEIGHT = 270.0f;
    final double CPROB_THRESH_BASE = 0.0001f;
    final int CACHE_DEPTH_LIMIT = 15;
    
    final int cpu_num = Runtime.getRuntime().availableProcessors();
    ExecutorService thrd_pool = Executors.newFixedThreadPool(cpu_num >= 4 ? 4 : cpu_num);

    int unif_random(int n) {
        return rand.nextInt(n);
    }

    static {
        System.loadLibrary("javadeps");
    }

    private native void clear_screen();

    long unpack_col(int row) {
        long tmp = row & 0xFFFF;
        return (tmp | (tmp << 12) | (tmp << 24) | (tmp << 36)) & COL_MASK;
    }

    int reverse_row(int row) {
        row &= 0xFFFF;
        return ((row >>> 12) | ((row >>> 4) & 0x00F0) | ((row << 4) & 0x0F00) | (row << 12)) & 0xFFFF;
    }

    void print_board(long board) {
        System.out.println("-----------------------------");
        for (int i = 0; i < 4; i++) {
            for (int j = 0; j < 4; j++) {
                int power_val = (int)(board & 0xf);
                if (power_val == 0) {
                    System.out.printf("|%6c", ' ');
                } else {
                    System.out.printf("|%6d", 1 << power_val);
                }
                board >>>= 4;
            }
            System.out.println("|");
        }
        System.out.println("-----------------------------");
    }

    long transpose(long x) {
        long a1 = x & 0xF0F00F0FF0F00F0FL;
        long a2 = x & 0x0000F0F00000F0F0L;
        long a3 = x & 0x0F0F00000F0F0000L;
        long a = a1 | (a2 << 12) | (a3 >>> 12);
        long b1 = a & 0xFF00FF0000FF00FFL;
        long b2 = a & 0x00FF00FF00000000L;
        long b3 = a & 0x00000000FF00FF00L;

        return b1 | (b2 >>> 24) | (b3 << 24);
    }

    int count_empty(long x) {
        x |= (x >>> 2) & 0x3333333333333333L;
        x |= (x >>> 1);
        x = ~x & 0x1111111111111111L;
        x += x >>> 32;
        x += x >>> 16;
        x += x >>> 8;
        x += x >>> 4;
        return (int)(x & 0xf);
    }

    void init_tables() {
        int row = 0, result = 0;
        int rev_row = 0, rev_result = 0;
        int[] line = new int[4];

        do {
            int i = 0, j = 0;
            int score = 0;
            line[0] = row & 0xf;
            line[1] = (row >>> 4) & 0xf;
            line[2] = (row >>> 8) & 0xf;
            line[3] = (row >>> 12) & 0xf;

            for (i = 0; i < 4; ++i) {
                int rank = line[i];
                if (rank >= 2) {
                    score += (int)((rank - 1) * (1 << rank));
                }
            }
            score_table[row] = score;
            
            double sum = 0.0f;
            int empty = 0;
            int merges = 0;
            int prev = 0;
            int counter = 0;

            for (i = 0; i < 4; ++i) {
                int rank = line[i];

                sum += Math.pow(rank, SCORE_SUM_POWER);
                if (rank == 0) {
                    empty++;
                } else {
                    if (prev == rank) {
                        counter++;
                    } else if (counter > 0) {
                        merges += 1 + counter;
                        counter = 0;
                    }
                    prev = rank;
                }
            }
            if (counter > 0) {
                merges += 1 + counter;
            }

            double monotonicity_left = 0.0f;
            double monotonicity_right = 0.0f;

            for (i = 1; i < 4; ++i) {
                if (line[i - 1] > line[i]) {
                    monotonicity_left +=
                        Math.pow(line[i - 1], SCORE_MONOTONICITY_POWER) - Math.pow(line[i], SCORE_MONOTONICITY_POWER);
                } else {
                    monotonicity_right +=
                        Math.pow(line[i], SCORE_MONOTONICITY_POWER) - Math.pow(line[i - 1], SCORE_MONOTONICITY_POWER);
                }
            }

            score_heur_table[row] = SCORE_LOST_PENALTY + SCORE_EMPTY_WEIGHT * empty + SCORE_MERGES_WEIGHT * merges -
                SCORE_MONOTONICITY_WEIGHT * Math.min(monotonicity_left, monotonicity_right) - SCORE_SUM_WEIGHT * sum;

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

            rev_row = reverse_row(row);
            rev_result = reverse_row(result);
            row_left_table[row] = row ^ result;
            row_right_table[rev_row] = rev_row ^ rev_result;
        } while (row++ != 0xFFFF);
    }

    long execute_move(long board, int move) {
        long ret = board;

        if (move == UP) {
            board = transpose(board);
            ret ^= unpack_col(row_left_table[(int)(board & ROW_MASK)]);
            ret ^= unpack_col(row_left_table[(int)((board >>> 16) & ROW_MASK)]) << 4;
            ret ^= unpack_col(row_left_table[(int)((board >>> 32) & ROW_MASK)]) << 8;
            ret ^= unpack_col(row_left_table[(int)((board >>> 48) & ROW_MASK)]) << 12;
        } else if (move == DOWN) {
            board = transpose(board);
            ret ^= unpack_col(row_right_table[(int)(board & ROW_MASK)]);
            ret ^= unpack_col(row_right_table[(int)((board >>> 16) & ROW_MASK)]) << 4;
            ret ^= unpack_col(row_right_table[(int)((board >>> 32) & ROW_MASK)]) << 8;
            ret ^= unpack_col(row_right_table[(int)((board >>> 48) & ROW_MASK)]) << 12;
        } else if (move == LEFT) {
            ret ^= (long)(row_left_table[(int)(board & ROW_MASK)]);
            ret ^= (long)(row_left_table[(int)((board >>> 16) & ROW_MASK)]) << 16;
            ret ^= (long)(row_left_table[(int)((board >>> 32) & ROW_MASK)]) << 32;
            ret ^= (long)(row_left_table[(int)((board >>> 48) & ROW_MASK)]) << 48;
        } else if (move == RIGHT) {
            ret ^= (long)(row_right_table[(int)(board & ROW_MASK)]);
            ret ^= (long)(row_right_table[(int)((board >>> 16) & ROW_MASK)]) << 16;
            ret ^= (long)(row_right_table[(int)((board >>> 32) & ROW_MASK)]) << 32;
            ret ^= (long)(row_right_table[(int)((board >>> 48) & ROW_MASK)]) << 48;
        }
        return ret;
    }

    int score_helper(long board) {
        return score_table[(int)(board & ROW_MASK)] + score_table[(int)((board >>> 16) & ROW_MASK)] +
            score_table[(int)((board >>> 32) & ROW_MASK)] + score_table[(int)((board >>> 48) & ROW_MASK)];
    }

    double score_heur_helper(long board) {
        return score_heur_table[(int)(board & ROW_MASK)] + score_heur_table[(int)((board >>> 16) & ROW_MASK)] +
            score_heur_table[(int)((board >>> 32) & ROW_MASK)] + score_heur_table[(int)((board >>> 48) & ROW_MASK)];
    }

    int score_board(long board) {
        return score_helper(board);
    }

    double score_heur_board(long board) {
        return score_heur_helper(board) + score_heur_helper(transpose(board));
    }

    long draw_tile() {
        return (long)((unif_random(10) < 9) ? 1 : 2);
    }

    long insert_tile_rand(long board, long tile) {
        int index = unif_random(count_empty(board));
        long tmp = board;

        while (true) {
            while ((tmp & 0xf) != 0) {
                tmp >>>= 4;
                tile <<= 4;
            }
            if (index == 0)
                break;
            --index;
            tmp >>>= 4;
            tile <<= 4;
        }
        return board | tile;
    }

    long initial_board() {
        long board = (long)(draw_tile()) << (unif_random(16) << 2);

        return insert_tile_rand(board, draw_tile());
    }

    int get_depth_limit(long board)
    {
        int bitset = 0, max_limit = 3, count = 0;

        while (board != 0) {
            bitset |= 1 << (board & 0xf);
            board >>>= 4;
        }

        if (bitset <= 2048) {
            return max_limit;
        } else if (bitset <= 2048 + 1024) {
            max_limit = 4;
        } else if (bitset <= 4096) {
            max_limit = 5;
        } else if (bitset <= 4096 + 2048) {
            max_limit = 6;
        } else if (bitset <= 8192) {
            max_limit = 7;
        } else {
            max_limit = 8;
        }

        bitset >>>= 1;
        while (bitset != 0) {
            bitset &= bitset - 1;
            count++;
        }
        count -= 2;
        count = Math.max(count, 3);
        count = Math.min(count, max_limit);
        return count;
    }

    double score_tilechoose_node(eval_state state, long board, double cprob) {
        if (cprob < CPROB_THRESH_BASE || state.curdepth >= state.depth_limit) {
            state.maxdepth = Math.max(state.curdepth, state.maxdepth);
            state.tablehits++;
            return score_heur_board(board);
        }
        if (state.curdepth < CACHE_DEPTH_LIMIT) {
            if (state.trans_table.containsKey(board)) {
                trans_table_entry_t entry = state.trans_table.get(board);

                if (entry.depth <= state.curdepth) {
                    state.cachehits++;
                    return entry.heuristic;
                }
            }
        }

        int num_open = count_empty(board);

        cprob /= num_open;

        double res = 0.0f;
        long tmp = board;
        long tile_2 = 1;

        while (tile_2 != 0) {
            if ((tmp & 0xf) == 0) {
                res += score_move_node(state, board | tile_2, cprob * 0.9f) * 0.9f;
                res += score_move_node(state, board | (tile_2 << 1), cprob * 0.1f) * 0.1f;
            }
            tmp >>>= 4;
            tile_2 <<= 4;
        }
        res = res / num_open;

        if (state.curdepth < CACHE_DEPTH_LIMIT) {
            trans_table_entry_t entry = new trans_table_entry_t(state.curdepth, res);
            state.trans_table.put(board, entry);
        }

        return res;
    }

    double score_move_node(eval_state state, long board, double cprob) {
        double best = 0.0f;

        state.curdepth++;
        for (int move = 0; move < 4; ++move) {
            long newboard = execute_move(board, move);
            state.moves_evaled++;

            if (board != newboard) {
                double tmp = score_tilechoose_node(state, newboard, cprob);
                if (best < tmp) {
                    best = tmp;
                }
            } else {
                state.nomoves++;
            }
        }
        state.curdepth--;

        return best;
    }

    double score_toplevel_move(long board, int move) {
        double res = 0.0f;
        eval_state state = new eval_state();
        long newboard = execute_move(board, move);

        state.depth_limit = get_depth_limit(board);

        if (board != newboard)
            res = score_tilechoose_node(state, newboard, 1.0f) + 0.000001f;

        System.out.printf("Move %d: result %f: eval'd %d moves (%d no moves, %d table hits, %d cache hits, %d cache size) (maxdepth=%d)\n", move, res,
               state.moves_evaled, state.nomoves, state.tablehits, state.cachehits, state.trans_table.size(), state.maxdepth);

        return res;
    }

    class callback implements Callable<Double> {
        long board;
        int move;

        public callback(long board, int move) {
            this.board = board;
            this.move = move;
        }

        @Override
        public Double call() throws Exception {
            return score_toplevel_move(this.board, this.move);
        }
    }

    int find_best_move(long board) {
        double best = 0.0f;
        int bestmove = -1;

        print_board(board);
        System.out.printf("Current scores: heur %d, actual %d\n", (int)score_heur_board(board), (int)score_board(board));

        HashMap<Integer, Future<Double>> futures = new HashMap<>();
        for (int move = 0; move < 4; move++) {
            futures.put(move, thrd_pool.submit(new callback(board, move)));
        }

        try {
            for (int move = 0; move < 4; move++) {
                if (futures.get(move).get(Long.MAX_VALUE, TimeUnit.NANOSECONDS).doubleValue() > best) {
                    best = futures.get(move).get().doubleValue();
                    bestmove = move;
                }
            }
        } catch (final Exception e) {
            System.out.println(e);
            System.exit(-1);
        }

        System.out.printf("Selected bestmove: %d, result: %f\n", bestmove, best);

        return bestmove;
    }

    void play_game() {
        long board = initial_board();
        int scorepenalty = 0;
        int last_score = 0, current_score = 0, moveno = 0;

        init_tables();
        while (true) {
            int move = 0;
            long tile = 0;
            long newboard;

            clear_screen();
            for (move = 0; move < 4; move++) {
                if (execute_move(board, move) != board)
                    break;
            }
            if (move == 4)
                break;

            current_score = (int)(score_board(board) - scorepenalty);
            System.out.printf("Move #%d, current score=%d(+%d)\n", ++moveno, current_score, current_score - last_score);
            last_score = current_score;

            move = find_best_move(board);
            if (move < 0)
                break;

            newboard = execute_move(board, move);
            if (newboard == board) {
                moveno--;
                continue;
            }

            tile = draw_tile();
            if (tile == 2) {
                scorepenalty += 4;
            }

            board = insert_tile_rand(newboard, tile);
        }

        print_board(board);
        System.out.printf("Game over. Your score is %d.\n", current_score);
        thrd_pool.shutdown();
    }

    public static void main(String[] args) {
        Game2048 game_2048 = new Game2048();
        game_2048.play_game();
    }
}
