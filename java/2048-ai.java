import java.util.Random;
import java.util.HashMap;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.Callable;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;

class Class2048
{
    Random rand = new Random();
    final long ROW_MASK = 0xFFFFL;
    final long COL_MASK = 0x000F000F000F000FL;
    final int TABLESIZE = 65536;
    int[] row_left_table = new int[TABLESIZE];
    int[] row_right_table = new int[TABLESIZE];
    double[] score_table = new double[TABLESIZE];
    double[] heur_score_table = new double[TABLESIZE];

    final int UP = 0;
    final int DOWN = 1;
    final int LEFT = 2;
    final int RIGHT = 3;
    final int RETRACT = 4;

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
        return ((row >> 12) | ((row >> 4) & 0x00F0) | ((row << 4) & 0x0F00) | (row << 12)) & 0xFFFF;
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
        int row = 0, rev_row = 0;
        int result = 0, rev_result = 0;
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

            heur_score_table[row] = SCORE_LOST_PENALTY + SCORE_EMPTY_WEIGHT * empty + SCORE_MERGES_WEIGHT * merges -
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
            rev_result = reverse_row(result);
            rev_row = reverse_row(row);

            row_left_table[row] = row ^ result;
            row_right_table[rev_row] = rev_row ^ rev_result;
        } while (row++ != TABLESIZE - 1);
    }

    long execute_move_col(long board, int[] table) {
        long ret = board;
        long t = transpose(board);

        ret ^= unpack_col(table[(int)(t & ROW_MASK)]);
        ret ^= unpack_col(table[(int)((t >> 16) & ROW_MASK)]) << 4;
        ret ^= unpack_col(table[(int)((t >> 32) & ROW_MASK)]) << 8;
        ret ^= unpack_col(table[(int)((t >> 48) & ROW_MASK)]) << 12;
        return ret;
    }

    long execute_move_row(long board, int[] table) {
        long ret = board;

        ret ^= (long)(table[(int)(board & ROW_MASK)]) & ROW_MASK;
        ret ^= ((long)(table[(int)((board >> 16) & ROW_MASK)]) & ROW_MASK) << 16;
        ret ^= ((long)(table[(int)((board >> 32) & ROW_MASK)]) & ROW_MASK) << 32;
        ret ^= ((long)(table[(int)((board >> 48) & ROW_MASK)]) & ROW_MASK) << 48;
        return ret;
    }

    long execute_move(int move, long board) {
        switch (move) {
            case UP:
                return execute_move_col(board, row_left_table);
            case DOWN:
                return execute_move_col(board, row_right_table);
            case LEFT:
                return execute_move_row(board, row_left_table);
            case RIGHT:
                return execute_move_row(board, row_right_table);
            default:
                return 0xFFFFFFFFFFFFFFFFL;
        }
    }
    
    int count_distinct_tiles(long board)
    {
        int bitset = 0;
        while (board != 0) {
            bitset |= 1 << (board & 0xf);
            board /= 16;
        }

        bitset >>= 1;
        int count = 0;
        while (bitset != 0) {
            bitset &= bitset - 1;
            count++;
        }
        return count;
    }

    double score_helper(long board, double[] table) {
        return table[(int)(board & ROW_MASK)] + table[(int)((board >> 16) & ROW_MASK)] +
            table[(int)((board >> 32) & ROW_MASK)] + table[(int)((board >> 48) & ROW_MASK)];
    }

    int score_board(long board) {
        return (int)score_helper(board,  score_table);
    }

    double score_heur_board(long board) {
        return score_helper(board, heur_score_table) + score_helper(transpose(board), heur_score_table);
    }

    double score_tilechoose_node(eval_state state, long board, double cprob) {
        if (cprob < CPROB_THRESH_BASE || state.curdepth >= state.depth_limit) {
            state.maxdepth = Math.max(state.curdepth, state.maxdepth);
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
            tmp >>= 4;
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
            long newboard = execute_move(move, board);
            state.moves_evaled++;

            if (board != newboard)
                best = Math.max(best, score_tilechoose_node(state, newboard, cprob));
        }
        state.curdepth--;

        return best;
    }

    double _score_toplevel_move(eval_state state, long board, int move) {
        long newboard = execute_move(move, board);

        if (board == newboard)
            return 0.0f;

        return score_tilechoose_node(state, newboard, 1.0f) + 0.000001f;
    }

    double score_toplevel_move(long board, int move) {
        double res = 0.0f;
        eval_state state = new eval_state();

        state.depth_limit = Math.max(3, count_distinct_tiles(board) - 2);

        res = _score_toplevel_move(state, board, move);

        System.out.printf("Move %d: result %f: eval'd %d moves (%d cache hits, %d cache size) (maxdepth=%d)\n", move, res,
               state.moves_evaled, state.cachehits, state.trans_table.size(), state.maxdepth);

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

    void play_game() {
        long board = initial_board();
        int scorepenalty = 0;
        int last_score = 0, current_score = 0, moveno = 0;

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
            System.out.printf("Move #%d, current score=%d(+%d)\n", ++moveno, current_score, current_score - last_score);
            last_score = current_score;

            move = find_best_move(board);
            if (move < 0)
                break;

            newboard = execute_move(move, board);
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
    }

    public static void main(String[] args) {
        Class2048 class_2048 = new Class2048();
        class_2048.init_tables();
        class_2048.play_game();
        class_2048.thrd_pool.shutdown();
    }
}
