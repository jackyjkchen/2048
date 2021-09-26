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

typedef unsigned char uint8;
typedef unsigned short uint16;

#ifdef _M_I86
typedef unsigned long uint32;
#else
typedef unsigned int uint32;
#endif
#if defined(_MSC_VER) || defined(__BORLANDC__) || defined(__WATCOMC__)
typedef unsigned __int64 uint64;

#define W64LIT(x) x##ui64
#else
typedef unsigned long long uint64;

#define W64LIT(x) x##ULL
#endif

#if defined(__TINYC__)
#define NOT_USE_WIN32_SDK 1
#endif

#if defined(_WIN32) && !defined(NOT_USE_WIN32_SDK)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <conio.h>
#elif defined(UNIX_LIKE)
#include <unistd.h>
#include <termios.h>
#elif defined(__WATCOMC__)
#include <graph.h>
#elif defined(__BORLANDC__) || defined (__TURBOC__) || defined(__DJGPP__) || defined(MSDOS)
#include <conio.h>
#endif

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

#if defined(_MSC_VER) && _MSC_VER >= 700 && defined(__STDC__)
#define _GETCH_USE 1
#elif defined(__WATCOMC__) && __WATCOMC__ < 1100
#define GETCH_USE 1
#endif

static int get_ch(void) {
#if (defined(_WIN32) && !defined(GETCH_USE)) || defined(_GETCH_USE)
    return _getch();
#elif defined(MSDOS) || defined(GETCH_USE)
    return getch();
#elif defined(UNIX_LIKE)
    struct termios old_termios, new_termios;
    int error;
    char c;

    fflush(stdout);
    tcgetattr(0, &old_termios);
    new_termios = old_termios;
    new_termios.c_lflag &= ~ICANON;
#ifdef TERMIOSECHO
    new_termios.c_lflag |= ECHO;
#else
    new_termios.c_lflag &= ~ECHO;
#endif
#ifdef TERMIOSFLUSH
#define OPTIONAL_ACTIONS TCSAFLUSH
#else
#define OPTIONAL_ACTIONS TCSANOW
#endif
    new_termios.c_cc[VMIN] = 1;
    new_termios.c_cc[VTIME] = 1;
    error = tcsetattr(0, OPTIONAL_ACTIONS, &new_termios);
    if (0 == error) {
        error = read(0, &c, 1);
    }
    error += tcsetattr(0, OPTIONAL_ACTIONS, &old_termios);

    return (error == 1 ? (int)c : -1);
#else
    return getchar();
#endif
}

typedef uint64 board_t;
typedef uint16 row_t;

static const board_t ROW_MASK = W64LIT(0xFFFF);
static const board_t COL_MASK = W64LIT(0x000F000F000F000F);

enum {
    UP = 0,
    DOWN,
    LEFT,
    RIGHT,
    RETRACT
};

typedef int (*get_move_func_t)(board_t);

#if defined(__MINGW64__) || defined(__MINGW32__)
#undef __USE_MINGW_ANSI_STDIO
#define __USE_MINGW_ANSI_STDIO 0
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static unsigned int unif_random(unsigned int n) {
    static unsigned int seeded = 0;

    if (!seeded) {
        srand((unsigned int)time(NULL));
        seeded = 1;
    }

    return rand() % n;
}

static board_t unpack_col(row_t row) {
    board_t tmp = row;

    return (tmp | (tmp << 12) | (tmp << 24) | (tmp << 36)) & COL_MASK;
}

static row_t reverse_row(row_t row) {
    return (row >> 12) | ((row >> 4) & 0x00F0) | ((row << 4) & 0x0F00) | (row << 12);
}

static void print_board(board_t board) {
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

static board_t transpose(board_t x) {
    board_t a1 = x & W64LIT(0xF0F00F0FF0F00F0F);
    board_t a2 = x & W64LIT(0x0000F0F00000F0F0);
    board_t a3 = x & W64LIT(0x0F0F00000F0F0000);
    board_t a = a1 | (a2 << 12) | (a3 >> 12);
    board_t b1 = a & W64LIT(0xFF00FF0000FF00FF);
    board_t b2 = a & W64LIT(0x00FF00FF00000000);
    board_t b3 = a & W64LIT(0x00000000FF00FF00);

    return b1 | (b2 >> 24) | (b3 << 24);
}

static int count_empty(board_t x) {
    x |= (x >> 2) & W64LIT(0x3333333333333333);
    x |= (x >> 1);
    x = ~x & W64LIT(0x1111111111111111);
    x += x >> 32;
    x += x >> 16;
    x += x >> 8;
    x += x >> 4;
    return (int)(x & 0xf);
}

#if FASTMODE != 0
#define TABLESIZE 65536
static row_t row_table[TABLESIZE];
static uint32 score_table[TABLESIZE];

static void init_tables(void) {
    row_t row = 0, result = 0;

    do {
        int i = 0, j = 0;
        uint8 line[4] = { 0 };
        uint32 score = 0;

        line[0] = row & 0xf;
        line[1] = (row >> 4) & 0xf;
        line[2] = (row >> 8) & 0xf;
        line[3] = (row >> 12) & 0xf;

        for (i = 0; i < 4; ++i) {
            uint32 rank = line[i];

            if (rank >= 2) {
                score += (rank - 1) * (1 << rank);
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
            } else if (line[i] == line[j]) {
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

static board_t execute_move_col(board_t board, int move) {
    board_t ret = board;
    board_t t = transpose(board);

    if (move == UP) {
        ret ^= unpack_col(row_table[t & ROW_MASK]);
        ret ^= unpack_col(row_table[(t >> 16) & ROW_MASK]) << 4;
        ret ^= unpack_col(row_table[(t >> 32) & ROW_MASK]) << 8;
        ret ^= unpack_col(row_table[(t >> 48) & ROW_MASK]) << 12;
    } else if (move == DOWN) {
        ret ^= unpack_col(reverse_row(row_table[reverse_row(t & ROW_MASK)]));
        ret ^= unpack_col(reverse_row(row_table[reverse_row((t >> 16) & ROW_MASK)])) << 4;
        ret ^= unpack_col(reverse_row(row_table[reverse_row((t >> 32) & ROW_MASK)])) << 8;
        ret ^= unpack_col(reverse_row(row_table[reverse_row((t >> 48) & ROW_MASK)])) << 12;
    }
    return ret;
}

static board_t execute_move_row(board_t board, int move) {
    board_t ret = board;

    if (move == LEFT) {
        ret ^= (board_t)(row_table[board & ROW_MASK]);
        ret ^= (board_t)(row_table[(board >> 16) & ROW_MASK]) << 16;
        ret ^= (board_t)(row_table[(board >> 32) & ROW_MASK]) << 32;
        ret ^= (board_t)(row_table[(board >> 48) & ROW_MASK]) << 48;
    } else if (move == RIGHT) {
        ret ^= (board_t)(reverse_row(row_table[reverse_row(board & ROW_MASK)]));
        ret ^= (board_t)(reverse_row(row_table[reverse_row((board >> 16) & ROW_MASK)])) << 16;
        ret ^= (board_t)(reverse_row(row_table[reverse_row((board >> 32) & ROW_MASK)])) << 32;
        ret ^= (board_t)(reverse_row(row_table[reverse_row((board >> 48) & ROW_MASK)])) << 48;
    }
    return ret;
}

static uint32 score_helper(board_t board) {
    return score_table[board & ROW_MASK] + score_table[(board >> 16) & ROW_MASK] +
        score_table[(board >> 32) & ROW_MASK] + score_table[(board >> 48) & ROW_MASK];
}
#else
static row_t execute_move_helper(row_t row) {
    int i = 0, j = 0;
    uint8 line[4] = { 0 };

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

static board_t execute_move_col(board_t board, int move) {
    board_t ret = board;
    board_t t = transpose(board);
    int i = 0;

    for (i = 0; i < 4; ++i) {
        row_t row = (row_t)((t >> (i << 4)) & ROW_MASK);

        if (move == UP) {
            ret ^= unpack_col(row ^ execute_move_helper(row)) << (i << 2);
        } else if (move == DOWN) {
            ret ^= unpack_col(row ^ reverse_row(execute_move_helper(reverse_row(row)))) << (i << 2);
        }
    }
    return ret;
}

static board_t execute_move_row(board_t board, int move) {
    board_t ret = board;
    int i = 0;

    for (i = 0; i < 4; ++i) {
        row_t row = (row_t)((board >> (i << 4)) & ROW_MASK);

        if (move == LEFT) {
            ret ^= (board_t)(row ^ execute_move_helper(row)) << (i << 4);
        } else if (move == RIGHT) {
            ret ^= (board_t)(row ^ reverse_row(execute_move_helper(reverse_row(row)))) << (i << 4);
        }
    }
    return ret;
}

static uint32 score_helper(board_t board) {
    int i = 0, j = 0;
    uint32 score = 0;

    for (j = 0; j < 4; ++j) {
        row_t row = (row_t)((board >> (j << 4)) & ROW_MASK);

        for (i = 0; i < 4; ++i) {
            uint32 rank = (row >> (i << 2)) & 0xf;

            if (rank >= 2) {
                score += (rank - 1) * (1 << rank);
            }
        }
    }
    return score;
}
#endif

static board_t execute_move(int move, board_t board) {
    switch (move) {
    case UP:
    case DOWN:
        return execute_move_col(board, move);
    case LEFT:
    case RIGHT:
        return execute_move_row(board, move);
    default:
        return ~W64LIT(0);
    }
}

static uint32 score_board(board_t board) {
    return score_helper(board);
}

static uint16 draw_tile(void) {
    return (unif_random(10) < 9) ? 1 : 2;
}

static board_t insert_tile_rand(board_t board, board_t tile) {
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

static board_t initial_board(void) {
    board_t board = (board_t)(draw_tile()) << (unif_random(16) << 2);

    return insert_tile_rand(board, draw_tile());
}

int ask_for_move(board_t board) {
    print_board(board);

    while (1) {
        const char *allmoves = "wsadkjhl", *pos = 0;
        char movechar = get_ch();

        if (movechar == 'q') {
            return -1;
        } else if (movechar == 'r') {
            return RETRACT;
        }
        pos = strchr(allmoves, movechar);
        if (pos) {
            return (pos - allmoves) % 4;
        }
    }
}

#define MAX_RETRACT 64
void play_game(get_move_func_t get_move) {
    board_t board = initial_board();
    int scorepenalty = 0;
    long last_score = 0, current_score = 0, moveno = 0;
    board_t retract_vec[MAX_RETRACT] = { 0 };
    uint8 retract_penalty_vec[MAX_RETRACT] = { 0 };
    int retract_pos = 0, retract_num = 0;

#if FASTMODE != 0
    init_tables();
#endif
    while (1) {
        int move = 0;
        uint16 tile = 0;
        board_t newboard;

        clear_screen();
        for (move = 0; move < 4; move++) {
            if (execute_move(move, board) != board)
                break;
        }
        if (move == 4)
            break;

        current_score = score_board(board) - scorepenalty;
        printf("Move #%ld, current score=%ld(+%ld)\n", ++moveno, current_score, current_score - last_score);
        last_score = current_score;

        move = get_move(board);
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
    printf("Game over. Your score is %ld.\n", current_score);
}

int main() {
    play_game(ask_for_move);
    return 0;
}
