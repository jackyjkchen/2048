using System;

class Class2048
{
    Random rand = new Random();
    const UInt64 ROW_MASK = 0xFFFF;
    const UInt64 COL_MASK = 0x000F000F000F000F;
    const int TABLESIZE = 65536;
    UInt16[] row_left_table = new UInt16[TABLESIZE];
    UInt16[] row_right_table = new UInt16[TABLESIZE];
    UInt32[] score_table = new UInt32[TABLESIZE];
    delegate int get_move_func_t(UInt64 board);

    const int UP = 0;
    const int DOWN = 1;
    const int LEFT = 2;
    const int RIGHT = 3;
    const int RETRACT = 4;

    Int32 unif_random(Int32 n)
    {
        return rand.Next(n);
    }

    void clear_screen()
    {
        Console.Clear();
    }

    char get_ch()
    {
        return Console.ReadKey(true).KeyChar;
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
                {
                    Console.Write(String.Format("|{0,6}", ' '));
                }
                else
                {
                    Console.Write(String.Format("|{0,6}", 1 << power_val));
                }
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
        UInt16 row = 0, rev_row = 0;
        UInt16 result = 0, rev_result = 0;
        UInt16[] line = new UInt16[4];

        do
        {
            int i = 0, j = 0;
            UInt32 score = 0;
            line[0] = (UInt16)((row >> 0) & 0xf);
            line[1] = (UInt16)((row >> 4) & 0xf);
            line[2] = (UInt16)((row >> 8) & 0xf);
            line[3] = (UInt16)((row >> 12) & 0xf);

            for (i = 0; i < 4; ++i)
            {
                int rank = line[i];
                if (rank >= 2)
                {
                    score += (UInt32)((rank - 1) * (1 << rank));
                }
            }
            score_table[row] = score;

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
                    {
                        line[i]++;
                    }
                    line[j] = 0;
                }
            }

            result = (UInt16)((line[0] << 0) | (line[1] << 4) | (line[2] << 8) | (line[3] << 12));
            rev_result = reverse_row(result);
            rev_row = reverse_row(row);

            row_left_table[row] = (UInt16)(row ^ result);
            row_right_table[rev_row] = (UInt16)(rev_row ^ rev_result);
        } while (row++ != TABLESIZE - 1);
    }

    UInt64 execute_move_col(UInt64 board, ref UInt16[] table)
    {
        UInt64 ret = board;
        UInt64 t = transpose(board);

        ret ^= unpack_col(table[(t >> 0) & ROW_MASK]) << 0;
        ret ^= unpack_col(table[(t >> 16) & ROW_MASK]) << 4;
        ret ^= unpack_col(table[(t >> 32) & ROW_MASK]) << 8;
        ret ^= unpack_col(table[(t >> 48) & ROW_MASK]) << 12;
        return ret;
    }

    UInt64 execute_move_row(UInt64 board, ref UInt16[] table)
    {
        UInt64 ret = board;

        ret ^= (UInt64)(table[(board >> 0) & ROW_MASK]) << 0;
        ret ^= (UInt64)(table[(board >> 16) & ROW_MASK]) << 16;
        ret ^= (UInt64)(table[(board >> 32) & ROW_MASK]) << 32;
        ret ^= (UInt64)(table[(board >> 48) & ROW_MASK]) << 48;
        return ret;
    }

    UInt64 execute_move(int move, UInt64 board)
    {
        switch (move)
        {
            case UP:
                return execute_move_col(board, ref row_left_table);
            case DOWN:
                return execute_move_col(board, ref row_right_table);
            case LEFT:
                return execute_move_row(board, ref row_left_table);
            case RIGHT:
                return execute_move_row(board, ref row_right_table);
            default:
                return 0xFFFFFFFFFFFFFFFF;
        }
    }

    UInt32 score_helper(UInt64 board, ref UInt32[] table)
    {
        return table[(board >> 0) & ROW_MASK] + table[(board >> 16) & ROW_MASK] +
            table[(board >> 32) & ROW_MASK] + table[(board >> 48) & ROW_MASK];
    }

    UInt32 score_board(UInt64 board)
    {
        return score_helper(board, ref score_table);
    }

    int ask_for_move(UInt64 board)
    {
        print_board(board);

        while (true)
        {
            const string allmoves = "wsadkjhl";
            int pos = 0;
            char movechar = get_ch();

            if (movechar == 'q')
            {
                return -1;
            }
            if (movechar == 'r')
            {
                return RETRACT;
            }
            pos = allmoves.IndexOf(movechar);
            if (pos != -1)
            {
                return pos % 4;
            }
        }
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

    void play_game(get_move_func_t get_move)
    {
        UInt64 board = initial_board();
        int scorepenalty = 0;
        int last_score = 0, current_score = 0, moveno = 0;
        const int MAX_RETRACT = 64;
        UInt64[] retract_vec = new UInt64[MAX_RETRACT];
        UInt16[] retract_penalty_vec = new UInt16[MAX_RETRACT];
        int retract_pos = 0, retract_num = 0;

        while (true)
        {
            int move = 0;
            UInt64 tile = 0;
            UInt64 newboard;

            clear_screen();
            for (move = 0; move < 4; move++)
            {
                if (execute_move(move, board) != board)
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

            if (move == RETRACT)
            {
                if (moveno <= 1 || retract_num <= 0)
                {
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
            if (newboard == board)
            {
                moveno--;
                continue;
            }

            tile = draw_tile();
            if (tile == 2)
            {
                scorepenalty += 4;
                retract_penalty_vec[retract_pos] = 4;
            }
            else
            {
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
        Console.WriteLine("Game over. Your score is {0}.", current_score);
    }

    static void Main(string[] args)
    {
        Class2048 class_2048 = new Class2048();
        class_2048.init_tables();
        class_2048.play_game(class_2048.ask_for_move);
    }
}
