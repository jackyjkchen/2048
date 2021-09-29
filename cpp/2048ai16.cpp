#if defined(__linux__) || defined(__unix__) || defined(__CYGWIN__) || defined(__MACH__) || defined(unix)
#define UNIX_LIKE 1
#endif

#if defined(__MSDOS__) || defined(_MSDOS) || defined(__DOS__)
#ifndef MSDOS
#define MSDOS 1
#endif
#ifdef _M_I86
#define FASTMODE 0
#endif
#endif

#if !defined(FASTMODE) || (defined(FASTMODE) && FASTMODE != 0)
#define FASTMODE 1
#endif

typedef unsigned short row_t;

#ifdef _M_I86
typedef unsigned long score_t;
#else
typedef unsigned int score_t;
#endif
typedef struct {
    row_t r0;
    row_t r1;
    row_t r2;
    row_t r3;
} board_t;
typedef float score_heur_t;

#if defined(__TINYC__)
#define NOT_USE_WIN32_SDK 1
#endif

#if defined(_WIN32) && !defined(NOT_USE_WIN32_SDK)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#elif defined(__WATCOMC__)
#include <graph.h>
#elif defined(__BORLANDC__) || defined (__TURBOC__) || defined(__DJGPP__)
#include <conio.h>
#endif

enum {
    UP = 0,
    DOWN,
    LEFT,
    RIGHT,
};

#if defined(max)
#undef max
#endif
#if defined(min)
#undef min
#endif

#if defined(__MINGW64__) || defined(__MINGW32__)
#undef __USE_MINGW_ANSI_STDIO
#define __USE_MINGW_ANSI_STDIO 0
#endif
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <time.h>

#define max(a,b) ( ((a)>(b)) ? (a):(b) )
#define min(a,b) ( ((a)>(b)) ? (b):(a) )

static void clear_screen(void) {
#if defined(_WIN32) && !defined(NOT_USE_WIN32_SDK)
    HANDLE hStdOut;
    DWORD count;
    DWORD cellCount;
    COORD homeCoords = { 0, 0 };
    static CONSOLE_SCREEN_BUFFER_INFO csbi;
    static int full_clear = 1;

    hStdOut = GetStdHandle(STD_OUTPUT_HANDLE);
    if (hStdOut == INVALID_HANDLE_VALUE)
        return;
    if (full_clear == 1) {
        if (!GetConsoleScreenBufferInfo(hStdOut, &csbi))
            return;
        cellCount = csbi.dwSize.X * csbi.dwSize.Y;
        if (cellCount >= 8192)
            full_clear = 0;
    } else {
        cellCount = 8192;
    }
    if (!FillConsoleOutputCharacter(hStdOut, (TCHAR)' ', cellCount, homeCoords, &count))
        return;
    if (full_clear && !FillConsoleOutputAttribute(hStdOut, csbi.wAttributes, cellCount, homeCoords, &count))
        return;
    SetConsoleCursorPosition(hStdOut, homeCoords);
#elif defined(UNIX_LIKE)
    printf("\033[2J\033[H");
#elif defined(__WATCOMC__)
    _clearscreen(_GCLEARSCREEN);
#elif defined(__BORLANDC__) || defined (__TURBOC__) || defined(__DJGPP__)
    clrscr();
#elif (defined(_WIN32) && defined(NOT_USE_WIN32_SDK)) || defined(MSDOS)
    system("cls");
#endif
}

const score_heur_t SCORE_LOST_PENALTY = 200000.0f;
const score_heur_t SCORE_MONOTONICITY_POWER = 4.0f;
const score_heur_t SCORE_MONOTONICITY_WEIGHT = 47.0f;
const score_heur_t SCORE_SUM_POWER = 3.5f;
const score_heur_t SCORE_SUM_WEIGHT = 11.0f;
const score_heur_t SCORE_MERGES_WEIGHT = 700.0f;
const score_heur_t SCORE_EMPTY_WEIGHT = 270.0f;
const score_heur_t CPROB_THRESH_BASE = 0.0001f;

class Game2048 {
public:
    Game2048() {
        alloc_tables();
    }   
    ~Game2048() {
        free_tables();
    }   

    void play_game();

private:
    board_t unpack_col(row_t row);
    row_t reverse_row(row_t row);
    unsigned int unif_random(unsigned int n); 
    void print_board(board_t board);
    board_t transpose(board_t x); 
    int count_empty(board_t x); 

    void init_tables();
    void alloc_tables();
    void free_tables();

    row_t execute_move_helper(row_t row);
    board_t execute_move(board_t board, int move);
    score_t score_helper(board_t board);
    score_heur_t score_heur_helper(board_t board);
    score_t score_board(board_t board);
    score_heur_t score_heur_board(board_t board);

    row_t draw_tile();
    board_t insert_tile_rand(board_t board, row_t tile);
    board_t initial_board();

    struct eval_state {
        int maxdepth;
        int curdepth;
        long nomoves;
        long tablehits;
        long cachehits;
        long moves_evaled;
        int depth_limit;

        eval_state() : maxdepth(0), curdepth(0), nomoves(0), tablehits(0), cachehits(0), moves_evaled(0), depth_limit(0) {}
    };  
    score_heur_t score_move_node(eval_state &state, board_t board, score_heur_t cprob);
    score_heur_t score_tilechoose_node(eval_state &state, board_t board, score_heur_t cprob);
    score_heur_t _score_toplevel_move(eval_state &state, board_t board, int move);
    score_heur_t score_toplevel_move(board_t board, int move);

    int find_best_move(board_t board);

#define TABLESIZE 8192
    score_heur_t* score_heur_table[8];
};

unsigned int Game2048::unif_random(unsigned int n) {
    static unsigned int seeded = 0;

    if (!seeded) {
        srand((unsigned int)time(NULL));
        seeded = 1;
    }

    return rand() % n;
}

board_t Game2048::unpack_col(row_t row) {
    board_t board;

    board.r0 = (row & 0xF000) >> 12;
    board.r1 = (row & 0x0F00) >> 8;
    board.r2 = (row & 0x00F0) >> 4;
    board.r3 = row & 0x000F;
    return board;
}

row_t Game2048::reverse_row(row_t row) {
    return (row >> 12) | ((row >> 4) & 0x00F0) | ((row << 4) & 0x0F00) | (row << 12);
}

void Game2048::print_board(board_t board) {
    row_t *t = (row_t *)&board;

    printf("-----------------------------\n");
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            unsigned int power_val = (unsigned int)((t[3 - i]) & 0xf);

            if (power_val == 0) {
                printf("|%6c", ' ');
            } else {
                printf("|%6u", 1 << power_val);
            }
            t[3 - i] >>= 4;
        }
        printf("|\n");
    }
    printf("-----------------------------\n");
}

board_t Game2048::transpose(board_t x) {
    row_t a1_0 = x.r0 & 0xF0F0;
    row_t a1_1 = x.r1 & 0x0F0F;
    row_t a1_2 = x.r2 & 0xF0F0;
    row_t a1_3 = x.r3 & 0x0F0F;
    row_t a2_1 = x.r1 & 0xF0F0;
    row_t a2_3 = x.r3 & 0xF0F0;
    row_t a3_0 = x.r0 & 0x0F0F;
    row_t a3_2 = x.r2 & 0x0F0F;
    row_t r0 = a1_0 | (a2_1 >> 4);
    row_t r1 = a1_1 | (a3_0 << 4);
    row_t r2 = a1_2 | (a2_3 >> 4);
    row_t r3 = a1_3 | (a3_2 << 4);
    row_t b1_0 = r0 & 0xFF00;
    row_t b1_1 = r1 & 0xFF00;
    row_t b1_2 = r2 & 0x00FF;
    row_t b1_3 = r3 & 0x00FF;
    row_t b2_0 = r0 & 0x00FF;
    row_t b2_1 = r1 & 0x00FF;
    row_t b3_2 = r2 & 0xFF00;
    row_t b3_3 = r3 & 0xFF00;

    x.r0 = b1_0 | (b3_2 >> 8);
    x.r1 = b1_1 | (b3_3 >> 8);
    x.r2 = b1_2 | (b2_0 << 8);
    x.r3 = b1_3 | (b2_1 << 8);
    return x;
}

int Game2048::count_empty(board_t board) {
    row_t sum = 0, x = 0, i = 0;

    for (i = 0; i < 4; i++) {
        x = ((row_t *)&board)[i];
        x |= (x >> 2) & 0x3333;
        x |= (x >> 1);
        x = ~x & 0x1111;
        x += x >> 8;
        x += x >> 4;
        sum += x;
    }
    return sum & 0xf;
}

void Game2048::init_tables(void) {
    row_t row = 0;

    do {
        int i = 0, j = 0;
        row_t line[4] = { 0 };
        score_t rank = 0;

        score_heur_t sum = 0.0f;
        score_t empty = 0;
        score_t merges = 0;
        score_t prev = 0;
        score_t counter = 0;
        score_heur_t monotonicity_left = 0.0f;
        score_heur_t monotonicity_right = 0.0f;

        line[0] = row & 0xf;
        line[1] = (row >> 4) & 0xf;
        line[2] = (row >> 8) & 0xf;
        line[3] = (row >> 12) & 0xf;

        for (i = 0; i < 4; ++i) {
            score_t rank = line[i];

            sum += (score_heur_t)pow((score_heur_t)rank, SCORE_SUM_POWER);
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

        for (i = 1; i < 4; ++i) {
            if (line[i - 1] > line[i]) {
                monotonicity_left +=
                    (score_heur_t)(pow((score_heur_t)line[i - 1], SCORE_MONOTONICITY_POWER) -
                                   pow((score_heur_t)line[i], SCORE_MONOTONICITY_POWER));
            } else {
                monotonicity_right +=
                    (score_heur_t)(pow((score_heur_t)line[i], SCORE_MONOTONICITY_POWER) -
                                   pow((score_heur_t)line[i - 1], SCORE_MONOTONICITY_POWER));
            }
        }

        score_heur_table[row / TABLESIZE][row % TABLESIZE] =
            (score_heur_t)(SCORE_LOST_PENALTY +
                           SCORE_EMPTY_WEIGHT * empty +
                           SCORE_MERGES_WEIGHT * merges -
                           SCORE_MONOTONICITY_WEIGHT *
                           min(monotonicity_left, monotonicity_right) - SCORE_SUM_WEIGHT * sum);
    } while (row++ != 0xFFFF);
}

void Game2048::alloc_tables(void) {
    memset(score_heur_table, 0x00, sizeof(score_heur_table));
    for (int i = 0; i < 8; ++i) {
        score_heur_table[i] = (score_heur_t *)malloc(sizeof(score_heur_t) * TABLESIZE);
        if (!score_heur_table[i]) {
            fprintf(stderr, "Not enough memory.");
            fflush(stderr);
            abort();
        }
    }
}

void Game2048::free_tables(void) {
    for (int i = 0; i < 8; ++i) {
        free(score_heur_table[i]);
    }
}

row_t Game2048::execute_move_helper(row_t row) {
    int i = 0, j = 0;
    row_t line[4];

    line[0] = row & 0xf;
    line[1] = (row >> 4) & 0xf;
    line[2] = (row >> 8) & 0xf;
    line[3] = (row >> 12) & 0xf;

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
        } else if (line[i] == line[j]) {
            if (line[i] != 0xf) {
                line[i]++;
            }
            line[j] = 0;
        }
    }

    return line[0] | (line[1] << 4) | (line[2] << 8) | (line[3] << 12);
}

score_t Game2048::score_helper(board_t board) {
    score_t score = 0, rank = 0;
    row_t row = 0;

    for (int j = 0; j < 4; ++j) {
        row = ((row_t *)&board)[3 - j];
        for (int i = 0; i < 4; ++i) {
            rank = (row >> (i << 2)) & 0xf;
            if (rank >= 2) {
                score += (rank - 1) * (1 << rank);
            }
        }
    }
    return score;
}

board_t Game2048::execute_move(board_t board, int move) {
    board_t ret, tran, tmp;
    row_t *t = (row_t *)&ret;
    row_t row;

    ret = board;
    if (move == UP || move == DOWN) {
        tran = transpose(board);
        t = (row_t *)&tran;
    }
    for (int i = 0; i < 4; ++i) {
        row = t[3 - i];
        if (move == UP) {
            tmp = unpack_col(row ^ execute_move_helper(row));
        } else if (move == DOWN) {
            tmp = unpack_col(row ^ reverse_row(execute_move_helper(reverse_row(row))));
        } else if (move == LEFT) {
            t[3 - i] ^= row ^ execute_move_helper(row);
        } else if (move == RIGHT) {
            t[3 - i] ^= row ^ reverse_row(execute_move_helper(reverse_row(row)));
        }
        if (move == UP || move == DOWN) {
            ret.r0 ^= tmp.r0 << (i << 2);
            ret.r1 ^= tmp.r1 << (i << 2);
            ret.r2 ^= tmp.r2 << (i << 2);
            ret.r3 ^= tmp.r3 << (i << 2);
        }
    }
    return ret;
}

score_heur_t Game2048::score_heur_helper(board_t board) {
    score_heur_t score_heur = 0.0f;
    row_t row = 0;

    for (int i = 0; i < 4; ++i) {
        row = ((row_t *)&board)[3 - i];
        score_heur += score_heur_table[row / TABLESIZE][row % TABLESIZE];
    }
    return score_heur;
}

score_t Game2048::score_board(board_t board) {
    return score_helper(board);
}

score_heur_t Game2048::score_heur_board(board_t board) {
    return score_heur_helper(board) + score_heur_helper(transpose(board));
}

row_t Game2048::draw_tile(void) {
    return (unif_random(10) < 9) ? 1 : 2;
}

board_t Game2048::insert_tile_rand(board_t board, row_t tile) {
    int index = unif_random(count_empty(board));
    int shift = 0;
    row_t *t = (row_t *)&board;
    row_t tmp = t[3];
    row_t orig_tile = tile;

    while (1) {
        while ((tmp & 0xf) != 0) {
            tmp >>= 4;
            tile <<= 4;
            shift += 4;
            if ((shift % 16) == 0) {
                tmp = t[3 - (shift >> 4)];
                tile = orig_tile;
            }
        }
        if (index == 0)
            break;
        --index;
        tmp >>= 4;
        tile <<= 4;
        shift += 4;
        if ((shift % 16) == 0) {
            tmp = t[3 - (shift >> 4)];
            tile = orig_tile;
        }
    }
    t[3 - (shift >> 4)] |= tile;
    return board;
}

board_t Game2048::initial_board(void) {
    board_t board;
    row_t shift = unif_random(16) << 2;
    row_t *t = (row_t *)&board;

    memset(&board, 0x00, sizeof(board_t));
    t[3 - (shift >> 4)] = draw_tile() << (shift % 16);
    return insert_tile_rand(board, draw_tile());
}

static board_t board_bitor(board_t *i1, board_t *i2, int i2_lshift) {
    board_t ret;
    ret.r0 = i1->r0 | (i2->r0 << i2_lshift);
    ret.r1 = i1->r1 | (i2->r1 << i2_lshift);
    ret.r2 = i1->r2 | (i2->r2 << i2_lshift);
    ret.r3 = i1->r3 | (i2->r3 << i2_lshift);
    return ret;
}

score_heur_t Game2048::score_tilechoose_node(eval_state &state, board_t board, score_heur_t cprob) {
    int num_open = 0;
    score_heur_t res = 0.0f;
    board_t tmp;
    board_t tile_2;
    row_t *t1 = (row_t *)&tmp;
    row_t *t2 = (row_t *)&tile_2;

    if (cprob < CPROB_THRESH_BASE || state.curdepth >= state.depth_limit) {
        state.maxdepth = max(state.curdepth, state.maxdepth);
        state.tablehits++;
        return score_heur_board(board);
    }

    num_open = count_empty(board);
    cprob /= num_open;

    tmp = board;
    for (int i = 0; i < 4; ++i) {
        t2[3 - i] = 1;
        while (t2[3 - i]) {
            if ((t1[3 - i] & 0xf) == 0) {
                res += score_move_node(state, board_bitor(&board, &tile_2, 0), cprob * 0.9f) * 0.9f;
                res += score_move_node(state, board_bitor(&board, &tile_2, 1), cprob * 0.1f) * 0.1f;
            }
            t1[3 - i] >>= 4;
            t2[3 - i] <<= 4;
        }
    }
    res = res / num_open;

    return res;
}

score_heur_t Game2048::score_move_node(eval_state &state, board_t board, score_heur_t cprob) {
    score_heur_t best = 0.0f;

    state.curdepth++;
    for (int move = 0; move < 4; ++move) {
        board_t newboard = execute_move(board, move);

        state.moves_evaled++;
        if (memcmp(&newboard, &board, sizeof(board_t)) != 0) {
            score_heur_t tmp = score_tilechoose_node(state, newboard, cprob);

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

score_heur_t Game2048::_score_toplevel_move(eval_state &state, board_t board, int move) {
    board_t newboard = execute_move(board, move);

    if (memcmp(&newboard, &board, sizeof(board_t)) == 0)
        return 0.0f;

    return score_tilechoose_node(state, newboard, 1.0f) + 1e-6f;
}

score_heur_t Game2048::score_toplevel_move(board_t board, int move) {
    eval_state state;
    score_heur_t res = 0.0;

    memset(&state, 0x00, sizeof(eval_state));
    state.depth_limit = 3;
    res = _score_toplevel_move(state, board, move);

    printf
        ("Move %d: result %f: eval'd %ld moves (%ld no moves, %ld table hits, %ld cache hits, %ld cache size) (maxdepth=%d)\n",
         move, res, state.moves_evaled, state.nomoves, state.tablehits, state.cachehits, 0L, state.maxdepth);

    return res;
}

int Game2048::find_best_move(board_t board) {
    int move = 0;
    score_heur_t best = 0.0f;
    int bestmove = -1;
    score_heur_t res[4] = { 0.0f };

    print_board(board);
    printf("Current scores: heur %ld, actual %ld\n", (long)score_heur_board(board), (long)score_board(board));

    for (move = 0; move < 4; move++) {
        res[move] = score_toplevel_move(board, move);
    }

    for (move = 0; move < 4; move++) {
        if (res[move] > best) {
            best = res[move];
            bestmove = move;
        }
    }
    printf("Selected bestmove: %d, result: %f\n", bestmove, best);

    return bestmove;
}

void Game2048::play_game() {
    board_t board = initial_board();
    int scorepenalty = 0;
    long last_score = 0, current_score = 0, moveno = 0;

    init_tables();
    while (1) {
        int move;
        row_t tile;
        board_t newboard;

        clear_screen();
        for (move = 0; move < 4; move++) {
            newboard = execute_move(board, move);
            if (memcmp(&newboard, &board, sizeof(board_t)) != 0)
                break;
        }
        if (move == 4)
            break;

        current_score = score_board(board) - scorepenalty;
        printf("Move #%ld, current score=%ld(+%ld)\n", ++moveno, current_score, current_score - last_score);
        last_score = current_score;

        move = find_best_move(board);
        if (move < 0)
            break;

        newboard = execute_move(board, move);
        if (memcmp(&newboard, &board, sizeof(board_t)) == 0) {
            moveno--;
            continue;
        }

        tile = draw_tile();
        if (tile == 2)
            scorepenalty += 4;
        board = insert_tile_rand(newboard, tile);
    }

    print_board(board);
    printf("Game over. Your score is %ld.\n", current_score);
}

int main() {
    Game2048 obj_2048;
    obj_2048.play_game();
    return 0;
}
