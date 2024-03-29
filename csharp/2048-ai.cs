﻿using System;
using System.Collections.Generic;
using System.Threading;

class Game2048
{
    Random rand = new Random();
    const UInt64 ROW_MASK = 0xFFFF;
    const UInt64 COL_MASK = 0x000F000F000F000F;
    const int TABLESIZE = 65536;
    UInt16[] row_left_table = new UInt16[TABLESIZE];
    UInt16[] row_right_table = new UInt16[TABLESIZE];
    UInt32[] score_table = new UInt32[TABLESIZE];
    double[] score_heur_table = new double[TABLESIZE];
    delegate int get_move_func_t(UInt64 board);
    const int UP = 0;
    const int DOWN = 1;
    const int LEFT = 2;
    const int RIGHT = 3;

    struct trans_table_entry_t
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
        public Dictionary<UInt64, trans_table_entry_t> trans_table = new Dictionary<UInt64, trans_table_entry_t>();
        public int maxdepth;
        public int curdepth;
        public int nomoves;
        public int tablehits;
        public int cachehits;
        public int moves_evaled;
        public int depth_limit;
    }

    const double SCORE_LOST_PENALTY = 200000.0f;
    const double SCORE_MONOTONICITY_POWER = 4.0f;
    const double SCORE_MONOTONICITY_WEIGHT = 47.0f;
    const double SCORE_SUM_POWER = 3.5f;
    const double SCORE_SUM_WEIGHT = 11.0f;
    const double SCORE_MERGES_WEIGHT = 700.0f;
    const double SCORE_EMPTY_WEIGHT = 270.0f;
    const double CPROB_THRESH_BASE = 0.0001f;
    const UInt16 CACHE_DEPTH_LIMIT = 15;

    Int32 unif_random(Int32 n)
    {
        return rand.Next(n);
    }

    void clear_screen()
    {
        Console.Clear();
    }

    UInt64 unpack_col(UInt16 row)
    {
        UInt64 tmp = row;
        return (tmp | (tmp << 12) | (tmp << 24) | (tmp << 36)) & COL_MASK;
    }

    UInt16 reverse_row(UInt16 row)
    {
        return (UInt16)((row >> 12) | ((row >> 4) & 0x00F0) | ((row << 4) & 0x0F00) | (row << 12));
    }

    void print_board(UInt64 board)
    {
        Console.WriteLine("-----------------------------");
        for (int i = 0; i < 4; i++)
        {
            for (int j = 0; j < 4; j++)
            {
                int power_val = (int)(board & 0xf);

                if (power_val == 0)
                    Console.Write("|{0,6}", ' ');
                else
                    Console.Write("|{0,6}", 1 << power_val);
                board >>= 4;
            }
            Console.WriteLine("|");
        }
        Console.WriteLine("-----------------------------");
    }

    UInt64 transpose(UInt64 x)
    {
        UInt64 a1 = x & 0xF0F00F0FF0F00F0F;
        UInt64 a2 = x & 0x0000F0F00000F0F0;
        UInt64 a3 = x & 0x0F0F00000F0F0000;
        UInt64 a = a1 | (a2 << 12) | (a3 >> 12);
        UInt64 b1 = a & 0xFF00FF0000FF00FF;
        UInt64 b2 = a & 0x00FF00FF00000000;
        UInt64 b3 = a & 0x00000000FF00FF00;

        return b1 | (b2 >> 24) | (b3 << 24);
    }

    int count_empty(UInt64 x)
    {
        x |= (x >> 2) & 0x3333333333333333;
        x |= (x >> 1);
        x = ~x & 0x1111111111111111;
        x += x >> 32;
        x += x >> 16;
        x += x >> 8;
        x += x >> 4;
        return (int)(x & 0xf);
    }

    void init_tables()
    {
        UInt16 row = 0, result = 0;
        UInt16 rev_row = 0, rev_result = 0;
        UInt16[] line = new UInt16[4];

        do
        {
            int i = 0, j = 0;
            UInt32 score = 0;
            line[0] = (UInt16)(row & 0xf);
            line[1] = (UInt16)((row >> 4) & 0xf);
            line[2] = (UInt16)((row >> 8) & 0xf);
            line[3] = (UInt16)((row >> 12) & 0xf);

            for (i = 0; i < 4; ++i)
            {
                int rank = line[i];

                if (rank >= 2)
                    score += (UInt32)((rank - 1) * (1 << rank));
            }
            score_table[row] = score;

            double sum = 0.0f;
            int empty = 0;
            int merges = 0;
            int prev = 0;
            int counter = 0;

            for (i = 0; i < 4; ++i)
            {
                int rank = line[i];

                sum += Math.Pow(rank, SCORE_SUM_POWER);
                if (rank == 0)
                {
                    empty++;
                }
                else
                {
                    if (prev == rank)
                    {
                        counter++;
                    }
                    else if (counter > 0)
                    {
                        merges += 1 + counter;
                        counter = 0;
                    }
                    prev = rank;
                }
            }
            if (counter > 0)
                merges += 1 + counter;

            double monotonicity_left = 0.0f;
            double monotonicity_right = 0.0f;

            for (i = 1; i < 4; ++i)
            {
                if (line[i - 1] > line[i])
                {
                    monotonicity_left +=
                        Math.Pow(line[i - 1], SCORE_MONOTONICITY_POWER) - Math.Pow(line[i], SCORE_MONOTONICITY_POWER);
                }
                else
                {
                    monotonicity_right +=
                        Math.Pow(line[i], SCORE_MONOTONICITY_POWER) - Math.Pow(line[i - 1], SCORE_MONOTONICITY_POWER);
                }
            }

            score_heur_table[row] = SCORE_LOST_PENALTY + SCORE_EMPTY_WEIGHT * empty + SCORE_MERGES_WEIGHT * merges -
                SCORE_MONOTONICITY_WEIGHT * Math.Min(monotonicity_left, monotonicity_right) - SCORE_SUM_WEIGHT * sum;

            for (i = 0; i < 3; ++i)
            {
                for (j = i + 1; j < 4; ++j)
                {
                    if (line[j] != 0)
                        break;
                }
                if (j == 4)
                    break;

                if (line[i] == 0)
                {
                    line[i] = line[j];
                    line[j] = 0;
                    i--;
                }
                else if (line[i] == line[j])
                {
                    if (line[i] != 0xf)
                        line[i]++;
                    line[j] = 0;
                }
            }
            result = (UInt16)(line[0] | (line[1] << 4) | (line[2] << 8) | (line[3] << 12));

            rev_row = reverse_row(row);
            rev_result = reverse_row(result);
            row_left_table[row] = (UInt16)(row ^ result);
            row_right_table[rev_row] = (UInt16)(rev_row ^ rev_result);
        } while (row++ != 0xFFFF);
    }

    UInt64 execute_move(UInt64 board, int move)
    {
        UInt64 ret = board;

        if (move == UP) {
            board = transpose(board);
            ret ^= unpack_col(row_left_table[board & ROW_MASK]);
            ret ^= unpack_col(row_left_table[(board >> 16) & ROW_MASK]) << 4;
            ret ^= unpack_col(row_left_table[(board >> 32) & ROW_MASK]) << 8;
            ret ^= unpack_col(row_left_table[(board >> 48) & ROW_MASK]) << 12;
        } else if (move == DOWN) {
            board = transpose(board);
            ret ^= unpack_col(row_right_table[board & ROW_MASK]);
            ret ^= unpack_col(row_right_table[(board >> 16) & ROW_MASK]) << 4;
            ret ^= unpack_col(row_right_table[(board >> 32) & ROW_MASK]) << 8;
            ret ^= unpack_col(row_right_table[(board >> 48) & ROW_MASK]) << 12;
        } else if (move == LEFT) {
            ret ^= (UInt64)(row_left_table[board & ROW_MASK]);
            ret ^= (UInt64)(row_left_table[(board >> 16) & ROW_MASK]) << 16;
            ret ^= (UInt64)(row_left_table[(board >> 32) & ROW_MASK]) << 32;
            ret ^= (UInt64)(row_left_table[(board >> 48) & ROW_MASK]) << 48;
        } else if (move == RIGHT) {
            ret ^= (UInt64)(row_right_table[board & ROW_MASK]);
            ret ^= (UInt64)(row_right_table[(board >> 16) & ROW_MASK]) << 16;
            ret ^= (UInt64)(row_right_table[(board >> 32) & ROW_MASK]) << 32;
            ret ^= (UInt64)(row_right_table[(board >> 48) & ROW_MASK]) << 48;
        }
        return ret;
    }

    UInt32 score_helper(UInt64 board)
    {
        return score_table[board & ROW_MASK] + score_table[(board >> 16) & ROW_MASK] +
            score_table[(board >> 32) & ROW_MASK] + score_table[(board >> 48) & ROW_MASK];
    }

    double score_heur_helper(UInt64 board)
    {
        return score_heur_table[board & ROW_MASK] + score_heur_table[(board >> 16) & ROW_MASK] +
            score_heur_table[(board >> 32) & ROW_MASK] + score_heur_table[(board >> 48) & ROW_MASK];
    }

    UInt32 score_board(UInt64 board)
    {
        return score_helper(board);
    }

    double score_heur_board(UInt64 board)
    {
        return score_heur_helper(board) + score_heur_helper(transpose(board));
    }

    UInt64 draw_tile()
    {
        return (UInt64)((unif_random(10) < 9) ? 1 : 2);
    }

    UInt64 insert_tile_rand(UInt64 board, UInt64 tile)
    {
        int index = unif_random(count_empty(board));
        UInt64 tmp = board;

        while (true)
        {
            while ((tmp & 0xf) != 0)
            {
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

    UInt64 initial_board()
    {
        UInt64 board = (UInt64)(draw_tile()) << (unif_random(16) << 2);

        return insert_tile_rand(board, draw_tile());
    }

    int get_depth_limit(UInt64 board)
    {
        UInt16 bitset = 0;
        int max_limit = 3;
        int count = 0;

        while (board != 0)
        {
            bitset |= (UInt16)(1 << (int)(board & 0xf));
            board >>= 4;
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

        bitset >>= 1;
        while (bitset != 0)
        {
            bitset &= (UInt16)(bitset - 1);
            count++;
        }
        count -= 2;
        count = Math.Max(count, 3);
        count = Math.Min(count, max_limit);
        return count;
    }

    double score_tilechoose_node(ref eval_state state, UInt64 board, double cprob)
    {
        if (cprob < CPROB_THRESH_BASE || state.curdepth >= state.depth_limit)
        {
            state.maxdepth = Math.Max(state.curdepth, state.maxdepth);
            state.tablehits++;
            return score_heur_board(board);
        }
        if (state.curdepth < CACHE_DEPTH_LIMIT)
        {
            if (state.trans_table.ContainsKey(board))
            {
                trans_table_entry_t entry = state.trans_table[board];

                if (entry.depth <= state.curdepth)
                {
                    state.cachehits++;
                    return entry.heuristic;
                }
            }
        }

        int num_open = count_empty(board);

        cprob /= num_open;

        double res = 0.0f;
        UInt64 tmp = board;
        UInt64 tile_2 = 1;

        while (tile_2 != 0)
        {
            if ((tmp & 0xf) == 0)
            {
                res += score_move_node(ref state, board | tile_2, cprob * 0.9f) * 0.9f;
                res += score_move_node(ref state, board | (tile_2 << 1), cprob * 0.1f) * 0.1f;
            }
            tmp >>= 4;
            tile_2 <<= 4;
        }
        res = res / num_open;

        if (state.curdepth < CACHE_DEPTH_LIMIT)
        {
            trans_table_entry_t entry = new trans_table_entry_t(state.curdepth, res);
            state.trans_table[board] = entry;
        }

        return res;
    }

    double score_move_node(ref eval_state state, UInt64 board, double cprob)
    {
        double best = 0.0f;

        state.curdepth++;
        for (int move = 0; move < 4; ++move)
        {
            UInt64 newboard = execute_move(board, move);

            state.moves_evaled++;
            if (board != newboard)
            {
                double tmp = score_tilechoose_node(ref state, newboard, cprob);
                if (best < tmp)
                    best = tmp;
            }
            else
            {
                state.nomoves++;
            }
        }
        state.curdepth--;

        return best;
    }

    double score_toplevel_move(UInt64 board, int move)
    {
        double res = 0.0f;
        eval_state state = new eval_state();
        UInt64 newboard = execute_move(board, move);

        state.depth_limit = get_depth_limit(board);

        if (board != newboard)
            res = score_tilechoose_node(ref state, newboard, 1.0f) + 1e-6f;

        Console.WriteLine("Move {0}: result {1}: eval'd {2} moves ({3} no moves, {4} table hits, {5} cache hits, {6} cache size) (maxdepth={7})", move, res,
               state.moves_evaled, state.nomoves, state.tablehits, state.cachehits, state.trans_table.Count, state.maxdepth);

        return res;
    }

    class thrd_context
    {
        public UInt64 board;
        public int move;
        public double res;
        public AutoResetEvent ev = new AutoResetEvent(false);
    }

    void thrd_worker(Object state)
    {
        thrd_context context = (thrd_context)state;
        context.res = score_toplevel_move(context.board, context.move);
        context.ev.Set();
    }

    int find_best_move(UInt64 board)
    {
        double best = 0.0f;
        int bestmove = -1;

        print_board(board);
        Console.WriteLine("Current scores: heur {0}, actual {1}", (UInt32)score_heur_board(board), (UInt32)score_board(board));

        thrd_context[] context = new thrd_context[4];
        for (int move = 0; move < 4; move++)
        {
            context[move] = new thrd_context();
            context[move].board = board;
            context[move].move = move;
            context[move].res = 0.0f;
            ThreadPool.QueueUserWorkItem(thrd_worker, context[move]);
        }
        for (int move = 0; move < 4; move++)
        {
            context[move].ev.WaitOne();
            if (context[move].res > best)
            {
                best = context[move].res;
                bestmove = move;
            }
        }
        Console.WriteLine("Selected bestmove: {0}, result: {1}", bestmove, best);

        return bestmove;
    }

    void play_game(get_move_func_t get_move)
    {
        UInt64 board = initial_board();
        int scorepenalty = 0;
        int last_score = 0, current_score = 0, moveno = 0;

        init_tables();
        while (true)
        {
            int move = 0;
            UInt64 tile = 0;
            UInt64 newboard;

            clear_screen();
            for (move = 0; move < 4; move++)
            {
                if (execute_move(board, move) != board)
                    break;
            }
            if (move == 4)
                break;

            current_score = (int)(score_board(board) - scorepenalty);
            Console.WriteLine("Move #{0}, current score={1}(+{2})", ++moveno, current_score, current_score - last_score);
            last_score = current_score;

            move = get_move(board);
            if (move < 0)
                break;

            newboard = execute_move(board, move);
            if (newboard == board)
            {
                moveno--;
                continue;
            }

            tile = draw_tile();
            if (tile == 2)
                scorepenalty += 4;

            board = insert_tile_rand(newboard, tile);
        }

        print_board(board);
        Console.WriteLine("Game over. Your score is {0}.", current_score);
    }

    static void Main(string[] args)
    {
        Game2048 game_2048 = new Game2048();
        game_2048.play_game(game_2048.find_best_move);
    }
}
