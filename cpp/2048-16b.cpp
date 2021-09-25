#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if !defined(FASTMODE) || (defined(FASTMODE) && FASTMODE != 0)
#define FASTMODE 1
#endif

#if defined(__linux__) || defined(__unix__) || defined(__CYGWIN__) || defined(__MACH__) || defined(unix)
#define UNIX_LIKE 1
#endif

#if defined(__MSDOS__) || defined(_MSDOS) || defined(__DOS__)
#ifndef MSDOS
#define MSDOS 1
#endif
#endif

typedef unsigned char uint8;
typedef unsigned short uint16;
#ifdef _M_I86
typedef unsigned long uint32;
#else
typedef unsigned int uint32;
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
    if (!FillConsoleOutputCharacter(hStdOut, (TCHAR) ' ', cellCount, homeCoords, &count))
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

typedef struct {
    uint16 r0;
    uint16 r1;
    uint16 r2;
    uint16 r3;
} board_t;
typedef uint16 row_t;

enum {
    UP = 0,
    DOWN,
    LEFT,
    RIGHT,
    RETRACT
};

class Game2048 {
public:
    void play_game();

private:
    board_t unpack_col(row_t row);
    row_t reverse_row(row_t row);
    unsigned int unif_random(unsigned int n);
    void print_board(board_t board);
    board_t transpose(board_t x);
    int count_empty(board_t x);

    row_t execute_move_helper(row_t row);
    board_t execute_move_col(board_t board, int move);
    board_t execute_move_row(board_t board, int move);
    uint32 score_helper(board_t board);
    board_t execute_move(int move, board_t board);
    uint32 score_board(board_t board);

    uint16 draw_tile();
    board_t insert_tile_rand(board_t board, uint16 tile);
    board_t initial_board();

    int ask_for_move(board_t board);
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
    uint16 *t = (uint16 *)&board;

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
    uint16 a1_0 = x.r0 & 0xF0F0;
    uint16 a1_1 = x.r1 & 0x0F0F;
    uint16 a1_2 = x.r2 & 0xF0F0;
    uint16 a1_3 = x.r3 & 0x0F0F;
    uint16 a2_1 = x.r1 & 0xF0F0;
    uint16 a2_3 = x.r3 & 0xF0F0;
    uint16 a3_0 = x.r0 & 0x0F0F;
    uint16 a3_2 = x.r2 & 0x0F0F;
    uint16 r0 = a1_0 | (a2_1 >> 4);
    uint16 r1 = a1_1 | (a3_0 << 4);
    uint16 r2 = a1_2 | (a2_3 >> 4);
    uint16 r3 = a1_3 | (a3_2 << 4);
    uint16 b1_0 = r0 & 0xFF00;
    uint16 b1_1 = r1 & 0xFF00;
    uint16 b1_2 = r2 & 0x00FF;
    uint16 b1_3 = r3 & 0x00FF;
    uint16 b2_0 = r0 & 0x00FF;
    uint16 b2_1 = r1 & 0x00FF;
    uint16 b3_2 = r2 & 0xFF00;
    uint16 b3_3 = r3 & 0xFF00;

    x.r0 = b1_0 | (b3_2 >> 8);
    x.r1 = b1_1 | (b3_3 >> 8);
    x.r2 = b1_2 | (b2_0 << 8);
    x.r3 = b1_3 | (b2_1 << 8);
    return x;
}

int Game2048::count_empty(board_t board) {
    uint16 sum = 0, x = 0;

    for (int i = 0; i < 4; i++) {
        x = ((uint16 *)&board)[i];
        x |= (x >> 2) & 0x3333;
        x |= (x >> 1);
        x = ~x & 0x1111;
        x += x >> 8;
        x += x >> 4;
        sum += x;
    }
    return sum & 0xf;
}

row_t Game2048::execute_move_helper(row_t row) {
    int i = 0, j = 0;
    uint8 line[4];

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

board_t Game2048::execute_move_col(board_t board, int move) {
    board_t ret, tran, tmp;
    uint16 *t = (uint16 *)&tran;

    ret = board;
    tran = transpose(board);
    for (int i = 0; i < 4; ++i) {
        row_t row = t[3 - i];

        if (move == UP) {
            tmp = unpack_col(row ^ execute_move_helper(row));
        } else if (move == DOWN) {
            tmp = unpack_col(row ^ reverse_row(execute_move_helper(reverse_row(row))));
        }
        ret.r0 ^= tmp.r0 << (i << 2);
        ret.r1 ^= tmp.r1 << (i << 2);
        ret.r2 ^= tmp.r2 << (i << 2);
        ret.r3 ^= tmp.r3 << (i << 2);
    }
    return ret;
}

board_t Game2048::execute_move_row(board_t board, int move) {
    board_t ret;
    uint16 *t = (uint16 *)&ret;

    ret = board;
    for (int i = 0; i < 4; ++i) {
        row_t row = t[3 - i];

        if (move == LEFT) {
            t[3 - i] ^= row ^ execute_move_helper(row);
        } else if (move == RIGHT) {
            t[3 - i] ^= row ^ reverse_row(execute_move_helper(reverse_row(row)));
        }
    }
    return ret;
}

uint32 Game2048::score_helper(board_t board) {
    uint32 score = 0;

    for (int j = 0; j < 4; ++j) {
        uint16 row = ((uint16 *)&board)[3 - j];

        for (int i = 0; i < 4; ++i) {
            int rank = (row >> (i << 2)) & 0xf;

            if (rank >= 2) {
                score += (rank - 1) * (1 << rank);
            }
        }
    }
    return score;
}

board_t Game2048::execute_move(int move, board_t board) {
    board_t invalid;

    switch (move) {
    case UP:
    case DOWN:
        return execute_move_col(board, move);
    case LEFT:
    case RIGHT:
        return execute_move_row(board, move);
    default:
        memset(&invalid, 0xFF, sizeof(board_t));
        return invalid;
    }
}

uint32 Game2048::score_board(board_t board) {
    return score_helper(board);
}

uint16 Game2048::draw_tile() {
    return (unif_random(10) < 9) ? 1 : 2;
}

board_t Game2048::insert_tile_rand(board_t board, uint16 tile) {
    int index = unif_random(count_empty(board));
    int shift = 0;
    uint16 *t = (uint16 *)&board;
    uint16 tmp = t[3];
    uint16 orig_tile = tile;

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

board_t Game2048::initial_board() {
    board_t board;
    uint16 shift = unif_random(16) << 2;
    uint16 *t = (uint16 *)&board;

    memset(&board, 0x00, sizeof(board_t));
    t[3 - (shift >> 4)] = draw_tile() << (shift % 16);
    return insert_tile_rand(board, draw_tile());
}

int Game2048::ask_for_move(board_t board) {
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

void Game2048::play_game() {
    board_t board, tmp;
    int scorepenalty = 0;
    long last_score = 0, current_score = 0, moveno = 0;
    const int MAX_RETRACT = 64;
    board_t retract_vec[MAX_RETRACT];
    uint8 retract_penalty_vec[MAX_RETRACT];
    int retract_pos = 0, retract_num = 0;

    board = initial_board();
    memset(retract_vec, 0x00, MAX_RETRACT * sizeof(board_t));
    memset(retract_penalty_vec, 0x00, MAX_RETRACT * sizeof(uint8));
    while (1) {
        int move = 0;
        uint16 tile = 0;
        board_t newboard;

        clear_screen();
        for (move = 0; move < 4; move++) {
            tmp = execute_move(move, board);
            if (memcmp(&tmp, &board, sizeof(board_t)) != 0)
                break;
        }
        if (move == 4)
            break;

        current_score = score_board(board) - scorepenalty;
        printf("Move #%ld, current score=%ld(+%ld)\n", ++moveno, current_score, current_score - last_score);
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
        if (memcmp(&newboard, &board, sizeof(board_t)) == 0) {
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
    Game2048 obj_2048;
    obj_2048.play_game();
    return 0;
}