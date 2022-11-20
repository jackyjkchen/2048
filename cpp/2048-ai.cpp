#if defined(__linux__) || defined(linux) || defined(__unix__) || defined(unix) || defined(__CYGWIN__) || defined(__MACH__)
#ifndef __DJGPP__
#define UNIX_LIKE 1
#endif
#endif

#if defined(__MSDOS__) || defined(_MSDOS) || defined(__DOS__)
#ifndef MSDOS
#define MSDOS 1
#endif
#endif

#include <limits.h>
#if UINT_MAX == 0xFFFFU
#define FASTMODE 0
#define __16BIT__ 1
#endif

#if !defined(FASTMODE) || (defined(FASTMODE) && FASTMODE != 0)
#define FASTMODE 1
#endif

typedef unsigned short row_t;
#ifdef __16BIT__
typedef unsigned long score_t;
#else
typedef unsigned int score_t;
#endif
#if defined(_MSC_VER) || defined(__BORLANDC__) || defined(__WATCOMC__)
typedef unsigned __int64 board_t;
#define W64LIT(x) x##ui64
#else
typedef unsigned long long board_t;
#define W64LIT(x) x##ULL
#endif
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

const board_t ROW_MASK = W64LIT(0xFFFF);
const board_t COL_MASK = W64LIT(0x000F000F000F000F);

enum {
    UP = 0,
    DOWN,
    LEFT,
    RIGHT,
};

#if defined(MULTI_THREAD) && defined(OPENMP_THREAD)
#error "MULTI_THREAD and OPENMP_THREAD cannot be defined at the same time."
#endif
#if defined(MULTI_THREAD)
#include "thread_pool.cpp"
#elif defined(OPENMP_THREAD)
#include <omp.h>
#endif

#if FASTMODE != 0
typedef struct {
    int depth;
    score_heur_t heuristic;
} trans_table_entry_t;

#if defined(max)
#undef max
#endif
#if defined(min)
#undef min
#endif

#if __cplusplus >= 201103L
#include <unordered_map>
typedef std::unordered_map<board_t, trans_table_entry_t> trans_table_t;
#define MAP_HAVE_SECOND 1
#elif defined(_MSC_VER) && _MSC_VER >= 1500
#include <unordered_map>
typedef std::tr1::unordered_map<board_t, trans_table_entry_t> trans_table_t;
#define MAP_HAVE_SECOND 1
#elif defined(__GNUC__) && (__GNUC__ >= 5 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 3) || (__GNUC__ == 4 && __GNUC_MINOR__ == 2 && __GNUC_PATCHLEVEL__ >= 2))
#include <tr1/unordered_map>
typedef std::tr1::unordered_map<board_t, trans_table_entry_t> trans_table_t;
#define MAP_HAVE_SECOND 1
#elif defined(__GNUC__) && __GNUC__ == 2 && __GNUC_MINOR__ < 8
#include <map.h>
typedef map<board_t, trans_table_entry_t, less<board_t> > trans_table_t;
#elif defined(_MSC_VER) && _MSC_VER < 1100
#include <map>
typedef map<board_t, trans_table_entry_t, less<board_t>, allocator<trans_table_entry_t> > trans_table_t;
#elif defined(__WATCOMC__) && __WATCOMC__ < 1200
#include <map>
typedef std::map<board_t, trans_table_entry_t, less<board_t> > trans_table_t;
#define MAP_HAVE_SECOND 1
#else
#include <map>
typedef std::map<board_t, trans_table_entry_t> trans_table_t;
#define MAP_HAVE_SECOND 1
#endif
#endif

#if defined(_MSC_VER) && _MSC_VER >= 1500 && defined(POPCNT)
#include <intrin.h>
#define __builtin_popcount __popcnt
#define __POPCNT__ 1
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

#define _max(a,b) ( ((a)>(b)) ? (a):(b) )
#define _min(a,b) ( ((a)>(b)) ? (b):(a) )

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
#if FASTMODE != 0
const row_t CACHE_DEPTH_LIMIT = 15;
#endif

class Game2048 {
public:
    Game2048() {
        alloc_tables();
    }
    ~Game2048() {
        free_tables();
    }

    void play_game();

    int find_best_move(board_t board);

private:
    inline board_t unpack_col(row_t row) {
        board_t tmp = row;
        return (tmp | (tmp << 12) | (tmp << 24) | (tmp << 36)) & COL_MASK;
    }
    inline row_t reverse_row(row_t row) {
        return (row >> 12) | ((row >> 4) & 0x00F0) | ((row << 4) & 0x0F00) | (row << 12);
    }
    unsigned int unif_random(unsigned int n);
    void print_board(board_t board);
    board_t transpose(board_t x);
    int count_empty(board_t x);

    void init_tables();
    void alloc_tables();
    void free_tables();

    board_t execute_move(board_t board, int move);
    score_t score_helper(board_t board);
    score_heur_t score_heur_helper(board_t board);
    score_t score_board(board_t board);
    score_heur_t score_heur_board(board_t board);

    row_t draw_tile();
    board_t insert_tile_rand(board_t board, board_t tile);
    board_t initial_board();

    struct eval_state {
#if FASTMODE != 0
        trans_table_t trans_table;
#endif
        int maxdepth;
        int curdepth;
        long nomoves;
        long tablehits;
        long cachehits;
        long moves_evaled;
        int depth_limit;

        eval_state() : maxdepth(0), curdepth(0), nomoves(0), tablehits(0), cachehits(0), moves_evaled(0), depth_limit(0) {}
    };
    int get_depth_limit(board_t board);
    score_heur_t score_move_node(eval_state &state, board_t board, score_heur_t cprob);
    score_heur_t score_tilechoose_node(eval_state &state, board_t board, score_heur_t cprob);
    score_heur_t _score_toplevel_move(eval_state &state, board_t board, int move);
    score_heur_t score_toplevel_move(board_t board, int move);

#if defined(MULTI_THREAD)
    typedef struct {
        Game2048 *pthis;
        board_t board;
        int move;
        score_heur_t res;
    } thrd_context;

    static void thrd_worker(void *param);
    static ThreadPool &get_thrd_pool();
#endif

#if FASTMODE != 0
#define TABLESIZE 65536
    row_t *row_left_table;
    row_t *row_right_table;
    score_t *score_table;
    score_heur_t *score_heur_table;
#else
#define TABLESIZE 8192
    row_t *row_table[8];
    score_heur_t *score_heur_table[8];
#endif
};

unsigned int Game2048::unif_random(unsigned int n) {
    static unsigned int seeded = 0;

    if (!seeded) {
        srand((unsigned int)time(NULL));
        seeded = 1;
    }

    return rand() % n;
}

void Game2048::print_board(board_t board) {
    int i = 0, j = 0;

    printf("-----------------------------\n");
    for (i = 0; i < 4; i++) {
        for (j = 0; j < 4; j++) {
            unsigned int power_val = (unsigned int)(board & 0xf);

            if (power_val == 0) {
                printf("|%6c", ' ');
            } else {
                printf("|%6u", 1 << power_val);
            }
            board >>= 4;
        }
        printf("|\n");
    }
    printf("-----------------------------\n");
}

board_t Game2048::transpose(board_t x) {
    board_t a1 = x & W64LIT(0xF0F00F0FF0F00F0F);
    board_t a2 = x & W64LIT(0x0000F0F00000F0F0);
    board_t a3 = x & W64LIT(0x0F0F00000F0F0000);
    board_t a = a1 | (a2 << 12) | (a3 >> 12);
    board_t b1 = a & W64LIT(0xFF00FF0000FF00FF);
    board_t b2 = a & W64LIT(0x00FF00FF00000000);
    board_t b3 = a & W64LIT(0x00000000FF00FF00);

    return b1 | (b2 >> 24) | (b3 << 24);
}

int Game2048::count_empty(board_t x) {
    x |= (x >> 2) & W64LIT(0x3333333333333333);
    x |= (x >> 1);
    x = ~x & W64LIT(0x1111111111111111);
    x += x >> 32;
    x += x >> 16;
    x += x >> 8;
    x += x >> 4;
    return (int)(x & 0xf);
}

void Game2048::init_tables() {
    row_t row = 0, result = 0;
#if FASTMODE != 0
    row_t rev_row = 0, rev_result = 0;
#endif

    do {
        int i = 0, j = 0;
        row_t line[4] = { 0 };

        line[0] = row & 0xf;
        line[1] = (row >> 4) & 0xf;
        line[2] = (row >> 8) & 0xf;
        line[3] = (row >> 12) & 0xf;

#if FASTMODE != 0
        score_t score = 0;
        for (i = 0; i < 4; ++i) {
            score_t rank = line[i];

            if (rank >= 2) {
                score += (rank - 1) * (1 << rank);
            }
        }
        score_table[row] = score;
#endif

        score_heur_t sum = 0.0f;
        score_t empty = 0;
        score_t merges = 0;
        score_t prev = 0;
        score_t counter = 0;

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

        score_heur_t monotonicity_left = 0.0f;
        score_heur_t monotonicity_right = 0.0f;

        for (i = 1; i < 4; ++i) {
            if (line[i - 1] > line[i]) {
                monotonicity_left +=
                    (score_heur_t)(pow((score_heur_t)line[i - 1], SCORE_MONOTONICITY_POWER) - pow((score_heur_t)line[i], SCORE_MONOTONICITY_POWER));
            } else {
                monotonicity_right +=
                    (score_heur_t)(pow((score_heur_t)line[i], SCORE_MONOTONICITY_POWER) - pow((score_heur_t)line[i - 1], SCORE_MONOTONICITY_POWER));
            }
        }

#if FASTMODE != 0
        score_heur_table[row] = (score_heur_t)(SCORE_LOST_PENALTY + SCORE_EMPTY_WEIGHT * empty + SCORE_MERGES_WEIGHT * merges -
            SCORE_MONOTONICITY_WEIGHT * _min(monotonicity_left, monotonicity_right) - SCORE_SUM_WEIGHT * sum);
#else
        score_heur_table[row / TABLESIZE][row % TABLESIZE] = (score_heur_t)(SCORE_LOST_PENALTY + SCORE_EMPTY_WEIGHT * empty + SCORE_MERGES_WEIGHT * merges -
            SCORE_MONOTONICITY_WEIGHT * _min(monotonicity_left, monotonicity_right) - SCORE_SUM_WEIGHT * sum);
#endif

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

        result = line[0] | (line[1] << 4) | (line[2] << 8) | (line[3] << 12);

#if FASTMODE != 0
        rev_row = reverse_row(row);
        rev_result = reverse_row(result);
        row_left_table[row] = row ^ result;
        row_right_table[rev_row] = rev_row ^ rev_result;
#else
        row_table[row / TABLESIZE][row % TABLESIZE] = row ^ result;
#endif
    } while (row++ != 0xFFFF);
}

#if FASTMODE != 0
void Game2048::alloc_tables() {
    row_left_table = (row_t *)malloc(sizeof(row_t) * TABLESIZE);
    row_right_table = (row_t *)malloc(sizeof(row_t) * TABLESIZE);
    score_table = (score_t *)malloc(sizeof(score_t) * TABLESIZE);
    score_heur_table = (score_heur_t *)malloc(sizeof(score_heur_t) * TABLESIZE);
    if (!row_left_table || !row_right_table || !score_table || !score_heur_table) {
        fprintf(stderr, "Not enough memory.");
        fflush(stderr);
        abort();
    }
}

void Game2048::free_tables() {
    free(row_left_table);
    free(row_right_table);
    free(score_table);
    free(score_heur_table);
}

board_t Game2048::execute_move(board_t board, int move) {
    board_t ret = board;

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
        ret ^= (board_t)(row_left_table[board & ROW_MASK]);
        ret ^= (board_t)(row_left_table[(board >> 16) & ROW_MASK]) << 16;
        ret ^= (board_t)(row_left_table[(board >> 32) & ROW_MASK]) << 32;
        ret ^= (board_t)(row_left_table[(board >> 48) & ROW_MASK]) << 48;
    } else if (move == RIGHT) {
        ret ^= (board_t)(row_right_table[board & ROW_MASK]);
        ret ^= (board_t)(row_right_table[(board >> 16) & ROW_MASK]) << 16;
        ret ^= (board_t)(row_right_table[(board >> 32) & ROW_MASK]) << 32;
        ret ^= (board_t)(row_right_table[(board >> 48) & ROW_MASK]) << 48;
    }
    return ret;
}

score_t Game2048::score_helper(board_t board) {
    return score_table[board & ROW_MASK] + score_table[(board >> 16) & ROW_MASK] +
        score_table[(board >> 32) & ROW_MASK] + score_table[(board >> 48) & ROW_MASK];
}

score_heur_t Game2048::score_heur_helper(board_t board) {
    return score_heur_table[board & ROW_MASK] + score_heur_table[(board >> 16) & ROW_MASK] +
        score_heur_table[(board >> 32) & ROW_MASK] + score_heur_table[(board >> 48) & ROW_MASK];
}
#else
void Game2048::alloc_tables() {
    memset(row_table, 0x00, sizeof(row_table));
    memset(score_heur_table, 0x00, sizeof(score_heur_table));
    for (int i = 0; i < 8; ++i) {
        row_table[i] = (row_t *)malloc(sizeof(row_t) * TABLESIZE);
        score_heur_table[i] = (score_heur_t *)malloc(sizeof(score_heur_t) * TABLESIZE);
        if (!row_table[i] || !score_heur_table[i]) {
            fprintf(stderr, "Not enough memory.");
            fflush(stderr);
            abort();
        }
    }
}

void Game2048::free_tables() {
    for (int i = 0; i < 8; ++i) {
        free(row_table[i]);
        free(score_heur_table[i]);
    }
}

board_t Game2048::execute_move(board_t board, int move) {
    board_t ret = board;

    if (move == UP) {
        board = transpose(board);
        for (int i = 0; i < 4; ++i) {
            row_t row = (board >> (i << 4)) & ROW_MASK;
            ret ^= unpack_col(row_table[row / TABLESIZE][row % TABLESIZE]) << (i << 2);
        }
    } else if (move == DOWN) {
        board = transpose(board);
        for (int i = 0; i < 4; ++i) {
            row_t row = reverse_row((board >> (i << 4)) & ROW_MASK);
            ret ^= unpack_col(reverse_row(row_table[row / TABLESIZE][row % TABLESIZE])) << (i << 2);
        }
    } else if (move == LEFT) {
        for (int i = 0; i < 4; ++i) {
            row_t row = (board >> (i << 4)) & ROW_MASK;
            ret ^= (board_t)(row_table[row / TABLESIZE][row % TABLESIZE]) << (i << 4);
        }
    } else if (move == RIGHT) {
        for (int i = 0; i < 4; ++i) {
            row_t row = reverse_row((board >> (i << 4)) & ROW_MASK);
            ret ^= (board_t)(reverse_row(row_table[row / TABLESIZE][row % TABLESIZE])) << (i << 4);
        }
    }
    return ret;
}

score_t Game2048::score_helper(board_t board) {
    score_t score = 0;

    for (int j = 0; j < 4; ++j) {
        row_t row = (row_t)((board >> (j << 4)) & ROW_MASK);
        for (int i = 0; i < 4; ++i) {
            score_t rank = (row >> (i << 2)) & 0xf;
            if (rank >= 2) {
                score += (rank - 1) * (1 << rank);
            }
        }
    }
    return score;
}

score_heur_t Game2048::score_heur_helper(board_t board) {
    score_heur_t score_heur = 0.0f;
    for (int i = 0; i < 4; ++i) {
        row_t row = (board >> (i << 4)) & ROW_MASK;
        score_heur += score_heur_table[row / TABLESIZE][row % TABLESIZE];
    }
    return score_heur;
}
#endif

score_t Game2048::score_board(board_t board) {
    return score_helper(board);
}

score_heur_t Game2048::score_heur_board(board_t board) {
    return score_heur_helper(board) + score_heur_helper(transpose(board));
}

row_t Game2048::draw_tile() {
    return (unif_random(10) < 9) ? 1 : 2;
}

board_t Game2048::insert_tile_rand(board_t board, board_t tile) {
    int index = unif_random(count_empty(board));
    board_t tmp = board;

    while (1) {
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

board_t Game2048::initial_board() {
    board_t board = (board_t)(draw_tile()) << (unif_random(16) << 2);

    return insert_tile_rand(board, draw_tile());
}

#if FASTMODE != 0
int Game2048::get_depth_limit(board_t board) {
    row_t bitset = 0, max_limit = 0;
    int count = 0;

    while (board) {
        bitset |= 1 << (board & 0xf);
        board >>= 4;
    }

    if (bitset <= 2048) {
        return 3;
    } else if (bitset <= 2048 + 1024) {
        max_limit = 4;
    } else if (bitset <= 4096) {
        max_limit = 5;
    } else if (bitset <= 4096 + 2048) {
        max_limit = 6;
    }

    bitset >>= 1;
#ifdef __POPCNT__
    count = (int)(__builtin_popcount(bitset)) - 2;
#else
    while (bitset) {
        bitset &= bitset - 1;
        count++;
    }
    count -= 2;
#endif
    count = _max(count, 3);
    if (max_limit) {
        count = _min(count, max_limit);
    }
    return count;
}
#else
int Game2048::get_depth_limit(board_t board) {
    return 3;
}
#endif

score_heur_t Game2048::score_tilechoose_node(eval_state &state, board_t board, score_heur_t cprob) {
    if (cprob < CPROB_THRESH_BASE || state.curdepth >= state.depth_limit) {
        state.maxdepth = _max(state.curdepth, state.maxdepth);
        state.tablehits++;
        return score_heur_board(board);
    }
#if FASTMODE != 0
    if (state.curdepth < CACHE_DEPTH_LIMIT) {
#if !defined(__WATCOMC__)
        const
#endif
        trans_table_t::iterator &i = state.trans_table.find(board);
        if (i != state.trans_table.end()) {
#ifdef MAP_HAVE_SECOND
            trans_table_entry_t &entry = i->second;
#else
            trans_table_entry_t &entry = state.trans_table[board];
#endif

            if (entry.depth <= state.curdepth) {
                state.cachehits++;
                return entry.heuristic;
            }
        }
    }
#endif

    int num_open = count_empty(board);

    cprob /= num_open;

    score_heur_t res = 0.0f;
    board_t tmp = board;
    board_t tile_2 = 1;

    while (tile_2) {
        if ((tmp & 0xf) == 0) {
            res += score_move_node(state, board | tile_2, cprob * 0.9f) * 0.9f;
            res += score_move_node(state, board | (tile_2 << 1), cprob * 0.1f) * 0.1f;
        }
        tmp >>= 4;
        tile_2 <<= 4;
    }
    res = res / num_open;

#if FASTMODE != 0
    if (state.curdepth < CACHE_DEPTH_LIMIT) {
        trans_table_entry_t entry = { state.curdepth, res };
        state.trans_table[board] = entry;
    }
#endif

    return res;
}

score_heur_t Game2048::score_move_node(eval_state &state, board_t board, score_heur_t cprob) {
    score_heur_t best = 0.0f;

    state.curdepth++;
    for (int move = 0; move < 4; ++move) {
        board_t newboard = execute_move(board, move);

        state.moves_evaled++;
        if (board != newboard) {
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

    if (board == newboard)
        return 0.0f;

    return score_tilechoose_node(state, newboard, 1.0f) + 1e-6f;
}

score_heur_t Game2048::score_toplevel_move(board_t board, int move) {
    eval_state state;

    state.depth_limit = get_depth_limit(board);

    score_heur_t res = _score_toplevel_move(state, board, move);

#if FASTMODE != 0
    printf("Move %d: result %f: eval'd %ld moves (%ld no moves, %ld table hits, %ld cache hits, %ld cache size) (maxdepth=%d)\n", move, res,
           state.moves_evaled, state.nomoves, state.tablehits, state.cachehits, (long)state.trans_table.size(), state.maxdepth);
#else
    printf("Move %d: result %f: eval'd %ld moves (%ld no moves, %ld table hits, %ld cache hits, %ld cache size) (maxdepth=%d)\n", move, res,
           state.moves_evaled, state.nomoves, state.tablehits, state.cachehits, 0L, state.maxdepth);
#endif

    return res;
}

#if defined(MULTI_THREAD)
void Game2048::thrd_worker(void *param) {
    thrd_context *pcontext = (thrd_context *)param;
    pcontext->res = pcontext->pthis->score_toplevel_move(pcontext->board, pcontext->move);
}

ThreadPool &Game2048::get_thrd_pool() {
    static ThreadPool thrd_pool(ThreadPool::get_cpu_num() >= 4 ? 4 : 0);
    return thrd_pool;
}
#endif

int Game2048::find_best_move(board_t board) {
    int move = 0;
    score_heur_t best = 0.0f;
    int bestmove = -1;

    print_board(board);
    printf("Current scores: heur %ld, actual %ld\n", (long)score_heur_board(board), (long)score_board(board));

#if defined(MULTI_THREAD)
    ThreadPool &thrd_pool = get_thrd_pool();
    thrd_context context[4];
    for (move = 0; move < 4; move++) {
        context[move].pthis = this;
        context[move].board = board;
        context[move].move = move;
        context[move].res = 0.0f;
        thrd_pool.add_task(thrd_worker, &context[move]);
    }
    thrd_pool.wait_all_task();
    for (move = 0; move < 4; move++) {
        if (context[move].res > best) {
            best = context[move].res;
            bestmove = move;
        }
    }
#else
    score_heur_t res[4] = { 0.0f };
#if defined(OPENMP_THREAD)
#pragma omp parallel for
#endif
    for (move = 0; move < 4; move++) {
        res[move] = score_toplevel_move(board, move);
    }

    for (move = 0; move < 4; move++) {
        if (res[move] > best) {
            best = res[move];
            bestmove = move;
        }
    }
#endif
    printf("Selected bestmove: %d, result: %f\n", bestmove, best);

    return bestmove;
}

void Game2048::play_game() {
    board_t board = initial_board();
    int scorepenalty = 0;
    long last_score = 0, current_score = 0, moveno = 0;

#if defined(MULTI_THREAD)
    ThreadPool &thrd_pool = get_thrd_pool();
    if (!thrd_pool.init()) {
        fprintf(stderr, "Init thread pool failed.");
        fflush(stderr);
        abort();
    }
#endif
    init_tables();
    while (1) {
        int move;
        row_t tile;
        board_t newboard;

        clear_screen();
        for (move = 0; move < 4; move++) {
            if (execute_move(board, move) != board)
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
        if (newboard == board) {
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
