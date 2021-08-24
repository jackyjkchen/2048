#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if defined(__MSDOS__) || defined(_MSDOS)
#ifndef MSDOS
#define MSDOS
#endif
#endif

#if defined(_Windows)
#ifndef __WINDOWS__
#define __WINDOWS__
#endif
#endif

typedef unsigned char       uint8;
typedef unsigned short      uint16;
#ifdef _M_I86
typedef unsigned long       uint32;
#else
typedef unsigned int        uint32;
#endif

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <conio.h>
#elif defined(MSDOS) || defined(__WINDOWS__)
#include <conio.h>
#elif defined(_POSIX_SOURCE) || defined(_POSIX_VERSION) || defined(__CYGWIN__) || defined(__MACH__)
#include <unistd.h>
#include <termios.h>
#endif

static unsigned int unif_random(unsigned int n) {
    static unsigned int seeded = 0;

    if(!seeded) {
        srand((unsigned int)time(NULL));
        seeded = 1;
    }

    return rand() % n;
}

#if defined(_WIN32)
static void clear_screen(void)
{
  HANDLE                     hStdOut;
  DWORD                      count;
  DWORD                      cellCount;
  COORD                      homeCoords = { 0, 0 };

  static CONSOLE_SCREEN_BUFFER_INFO csbi;
  static int                        full_clear = 1; 

  hStdOut = GetStdHandle( STD_OUTPUT_HANDLE );
  if (hStdOut == INVALID_HANDLE_VALUE) return;

  /* Get the number of cells in the current buffer */
  if (full_clear == 1) {
      if (!GetConsoleScreenBufferInfo( hStdOut, &csbi )) return;
      cellCount = csbi.dwSize.X *csbi.dwSize.Y;
      if (cellCount >= 8192)
          full_clear = 0;
  }
  else {
      cellCount = 8192;
  }

  /* Fill the entire buffer with spaces */
  if (!FillConsoleOutputCharacter(
    hStdOut,
    (TCHAR) ' ',
    cellCount,
    homeCoords,
    &count
    )) return;

  /* Fill the entire buffer with the current colors and attributes */
  if (full_clear && !FillConsoleOutputAttribute(
    hStdOut,
    csbi.wAttributes,
    cellCount,
    homeCoords,
    &count
    )) return;

  /* Move the cursor home */
  SetConsoleCursorPosition( hStdOut, homeCoords );
}
#elif defined(__BORLANDC__) || defined (__TURBOC__) || defined(__DJGPP__)
#define clear_screen() clrscr()
#elif defined(MSDOS)
#if defined(__WATCOMC__)
#include <graph.h>
#define clear_screen()  _clearscreen(_GCLEARSCREEN);
#else
#define clear_screen()  system("cls");
#endif
#elif defined(_POSIX_SOURCE) || defined(_POSIX_VERSION) || defined(__CYGWIN__) || defined(__MACH__)
#define clear_screen()  printf("\033[2J\033[H");
#else
#define clear_screen()
#endif

#if defined(_WIN32) || defined(MSDOS) || defined(__WINDOWS__)
#elif defined(_POSIX_SOURCE) || defined(_POSIX_VERSION) || defined(__CYGWIN__) || defined(__MACH__)
typedef struct
{
    struct termios oldt, newt;
} term_state;
#endif

#if defined(_WIN32) || defined(MSDOS) || defined(__WINDOWS__)
#elif defined(_POSIX_SOURCE) || defined(_POSIX_VERSION) || defined(__CYGWIN__) || defined(__MACH__)
static void term_init(term_state *s)
{
    tcgetattr(STDIN_FILENO, &s->oldt);
    s->newt = s->oldt;
    s->newt.c_lflag &= ~(ICANON | ECHO);
    tcsetattr(STDIN_FILENO, TCSANOW, &s->newt);
}
#endif

#if defined(_WIN32) || defined(MSDOS) || defined(__WINDOWS__)
#elif defined(_POSIX_SOURCE) || defined(_POSIX_VERSION) || defined(__CYGWIN__) || defined(__MACH__)
static void term_clear(term_state *s)
{
    tcsetattr(STDIN_FILENO, TCSANOW, &s->oldt);
}
#endif

static int get_ch(void)
{
#if defined(_WIN32) || defined(MSDOS) || defined(__WINDOWS__)
#if defined(_MSC_VER) && _MSC_VER >= 1200
    return _getch();
#else
    return getch();
#endif
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

typedef int (*get_move_func_t)(board_t);

static board_t unpack_col(row_t row) {
    board_t tmp;
    tmp.r0 = (row & 0xF000) >> 12;
    tmp.r1 = (row & 0x0F00) >>  8;
    tmp.r2 = (row & 0x00F0) >>  4;
    tmp.r3 = (row & 0x000F) >>  0;
    return tmp;
}

static row_t reverse_row(row_t row) {
    return (row >> 12) | ((row >> 4) & 0x00F0)  | ((row << 4) & 0x0F00) | (row << 12);
}

static void print_board(board_t board) {
    int i,j;
    uint16 *t = (uint16 *)&board;
    printf("-----------------------------\n");
    for(i=0; i<4; i++) {
        for(j=0; j<4; j++) {
            unsigned int power_val = (unsigned int)((t[3-i]) & 0xf);
            if (power_val == 0) {
                printf("|%6c", ' ');
            } else {
                printf("|%6u", 1 << power_val);
            }
            t[3-i] >>= 4;
        }
        printf("|\n");
    }
    printf("-----------------------------\n");
}

/* Transpose rows/columns in a board:
   0123       048c
   4567  -->  159d
   89ab       26ae
   cdef       37bf
*/
static board_t transpose(board_t x)
{
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

static int count_empty(board_t board)
{
    uint16 sum = 0, x = 0, i = 0;
    for(i=0; i<4; i++) {
        x = ((uint16 *)&board)[i];
        x |= (x >> 2) & 0x3333;
        x |= (x >> 1);
        x = ~x & 0x1111;
        x += x >>  8;
        x += x >>  4;
        sum += x;
    }
    return sum & 0xf;
}

/* We can perform state lookups one row at a time by using arrays with 65536 entries. */

/* Move tables. Each row or compressed column is mapped to (oldrow^newrow) assuming row/col 0.
 *
 * Thus, the value is 0 if there is no move, and otherwise equals a value that can easily be
 * xor'ed into the current board state to update the board. */
#ifdef FASTMODE
#define TABLESIZE 65536
static row_t row_left_table[TABLESIZE];
static row_t row_right_table[TABLESIZE];
static uint32 score_table[TABLESIZE];
#endif

#ifdef FASTMODE
static void init_tables(void) {
    row_t row = 0, rev_row = 0;
    row_t result = 0, rev_result = 0;

    do {
        int i = 0, j = 0;
        uint8 line[4] = {0};
        uint32 score = 0;

        line[0] = (row >>  0) & 0xf;
        line[1] = (row >>  4) & 0xf;
        line[2] = (row >>  8) & 0xf;
        line[3] = (row >> 12) & 0xf;

        for (i = 0; i < 4; ++i) {
            int rank = line[i];
            if (rank >= 2) {
                score += (rank - 1) * (1 << rank);
            }
        }
        score_table[row] = score;

        for (i = 0; i < 3; ++i) {
            for (j = i + 1; j < 4; ++j) {
                if (line[j] != 0) break;
            }
            if (j == 4) break;

            if (line[i] == 0) {
                line[i] = line[j];
                line[j] = 0;
                i--;
            } else if (line[i] == line[j]) {
                if(line[i] != 0xf) {
                    /* Pretend that 32768 + 32768 = 32768 (representational limit). */
                    line[i]++;
                }
                line[j] = 0;
            }
        }

        result = (line[0] <<  0) |
                 (line[1] <<  4) |
                 (line[2] <<  8) |
                 (line[3] << 12);
        rev_result = reverse_row(result);
        rev_row = reverse_row(row);

        row_left_table [    row] =     row ^     result;
        row_right_table[rev_row] = rev_row ^ rev_result;
    } while (row++ != 65535);
}
#endif

#ifdef FASTMODE
static board_t execute_move_col(board_t board, row_t *table) {
    board_t ret = board, tmp;
    board_t tran = transpose(board);
    uint16 *t = (uint16 *)&tran;
    tmp = unpack_col(table[t[3]]);
    ret.r0 ^= tmp.r0;
    ret.r1 ^= tmp.r1;
    ret.r2 ^= tmp.r2;
    ret.r3 ^= tmp.r3;
    tmp = unpack_col(table[t[2]]);
    ret.r0 ^= tmp.r0 << 4;
    ret.r1 ^= tmp.r1 << 4;
    ret.r2 ^= tmp.r2 << 4;
    ret.r3 ^= tmp.r3 << 4;
    tmp = unpack_col(table[t[1]]);
    ret.r0 ^= tmp.r0 << 8;
    ret.r1 ^= tmp.r1 << 8;
    ret.r2 ^= tmp.r2 << 8;
    ret.r3 ^= tmp.r3 << 8;
    tmp = unpack_col(table[t[0]]);
    ret.r0 ^= tmp.r0 << 12;
    ret.r1 ^= tmp.r1 << 12;
    ret.r2 ^= tmp.r2 << 12;
    ret.r3 ^= tmp.r3 << 12;
    return ret;
}

static board_t execute_move_row(board_t board, row_t *table) {
    board_t ret = board;
    ret.r3 ^= table[ret.r3];
    ret.r2 ^= table[ret.r2];
    ret.r1 ^= table[ret.r1];
    ret.r0 ^= table[ret.r0];
    return ret;
}

#else
static row_t execute_move_helper(row_t row) {
    int i = 0, j = 0;
    uint8 line[4] = {0};

    line[0] = (row >>  0) & 0xf;
    line[1] = (row >>  4) & 0xf;
    line[2] = (row >>  8) & 0xf;
    line[3] = (row >> 12) & 0xf;

    for (i = 0; i < 3; ++i) {
        for (j = i + 1; j < 4; ++j) {
            if (line[j] != 0) break;
        }
        if (j == 4) break;

        if (line[i] == 0) {
            line[i] = line[j];
            line[j] = 0;
            i--;
        } else if (line[i] == line[j]) {
            if(line[i] != 0xf) {
                /* Pretend that 32768 + 32768 = 32768 (representational limit). */
                line[i]++;
            }
            line[j] = 0;
        }
    }

    return (line[0] <<  0) | (line[1] <<  4) | (line[2] <<  8) | (line[3] << 12);
}

static board_t execute_move_col(board_t board, int move) {
    board_t ret = board;
    board_t tran = transpose(board), tmp;
    uint16 *t = (uint16 *)&tran;
    int i = 0;
    for (i = 0; i < 4; ++i) {
        row_t row = t[3-i];
        if (move == UP) {
            tmp = unpack_col(row ^ execute_move_helper(row));
        } else if (move == DOWN) {
            row_t rev_row = reverse_row(row);
            tmp =  unpack_col(row ^ reverse_row(execute_move_helper(rev_row)));
        }
        ret.r0 ^= tmp.r0 << (i << 2);
        ret.r1 ^= tmp.r1 << (i << 2);
        ret.r2 ^= tmp.r2 << (i << 2);
        ret.r3 ^= tmp.r3 << (i << 2);
    }
    return ret;
}

static board_t execute_move_row(board_t board, int move) {
    board_t ret = board;
    uint16 *t = (uint16 *)&ret;
    int i = 0;
    for (i = 0; i < 4; ++i) {
        row_t row = t[3-i];
        if (move == LEFT) {
            t[3-i] ^= row ^ execute_move_helper(row);
        } else if (move == RIGHT) {
            row_t rev_row = reverse_row(row);
            t[3-i] ^= row ^ reverse_row(execute_move_helper(rev_row));
        }
    }
    return ret;
}

#endif

/* Execute a move. */
static board_t execute_move(int move, board_t board) {
    board_t invalid;
    switch(move) {
#ifdef FASTMODE
    case UP:
        return execute_move_col(board, row_left_table);
    case DOWN:
        return execute_move_col(board, row_right_table);
    case LEFT:
        return execute_move_row(board, row_left_table);
    case RIGHT:
        return execute_move_row(board, row_right_table);
#else
    case UP:
    case DOWN:
        return execute_move_col(board, move);
    case LEFT:
    case RIGHT:
        return execute_move_row(board, move);
#endif
    default:
        memset(&invalid, 0xFF, sizeof(board_t));
        return invalid;
    }
}

#ifdef FASTMODE
static uint32 score_helper(board_t board, const uint32 *table) {
    return table[board.r3] +
           table[board.r2] +
           table[board.r1] +
           table[board.r0];
}
#else
static uint32 score_helper(board_t board) {
    int i = 0, j = 0;
    uint8 line[4] = {0};
    uint32 score = 0;
    for (j = 0; j < 4; ++j) {
        uint16 row = ((uint16 *)&board)[3-j];
        line[0] = (row >>  0) & 0xf;
        line[1] = (row >>  4) & 0xf;
        line[2] = (row >>  8) & 0xf;
        line[3] = (row >> 12) & 0xf;
        for (i = 0; i < 4; ++i) {
            uint8 rank = line[i];
            if (rank >= 2) {
                score += (rank - 1) * (1 << rank);
            }
        }
    }
    return score;
}
#endif

static uint32 score_board(board_t board) {
#ifdef FASTMODE
    return score_helper(board, score_table);
#else
    return score_helper(board);
#endif
}

int ask_for_move(board_t board) {
    print_board(board);

    while(1) {
        char movechar;
        const char *allmoves = "wsadkjhl", *pos = 0;

        movechar = get_ch();

        if (movechar == 'q') {
            return -1;
        }
        if (movechar == 'r') {
            return RETRACT;
        }
        pos = strchr(allmoves, movechar);
        if(!pos) {
            continue;
        }

        return (pos - allmoves) % 4;
    }
}

static uint16 draw_tile(void) {
    return (unif_random(10) < 9) ? 1 : 2;
}

static board_t insert_tile_rand(board_t board, uint16 tile) {
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
                tmp = t[3 - (shift>>4)];
                tile = orig_tile;
            }
        }
        if (index == 0) break;
        --index;
        tmp >>= 4;
        tile <<= 4;
        shift += 4;
        if ((shift % 16) == 0) {
            tmp = t[3 - (shift>>4)];
            tile = orig_tile;
        }
    }
    t[3 - (shift>>4)] |= tile;
    return board;
}

static board_t initial_board(void) {
    board_t board;
    uint16 shift = unif_random(16) << 2;
    uint16 *t = (uint16 *)&board;
    memset(&board, 0x00, sizeof(board_t));
    t[3 - (shift>>4)] = draw_tile() << (shift % 16);
    return insert_tile_rand(board, draw_tile());
}

#define MAX_RETRACT 64
void play_game(get_move_func_t get_move) {
    board_t board = initial_board();
    int scorepenalty = 0;
    long last_score = 0, current_score = 0, moveno = 0;
    board_t retract_vec[MAX_RETRACT] = {0};
    uint8 retract_penalty_vec[MAX_RETRACT] = {0};
    int retract_pos = 0, retract_num = 0;

    while(1) {
        int move;
        uint16 tile;
        board_t newboard, tmp;

        clear_screen();
        for(move = 0; move < 4; move++) {
            tmp = execute_move(move, board);
            if(memcmp(&tmp, &board, sizeof(board_t)) != 0)
                break;
        }
        if(move == 4)
            break;

        current_score = score_board(board) - scorepenalty;
        printf("Move #%ld, current score=%ld(+%ld)\n", ++moveno, current_score, current_score - last_score);
        last_score = current_score;

        move = get_move(board);
        if(move < 0)
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
        if(memcmp(&newboard, &board, sizeof(board_t)) == 0) {
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
#if defined(_WIN32) || defined(MSDOS) || defined(__WINDOWS__)
#elif defined(_POSIX_SOURCE) || defined(_POSIX_VERSION) || defined(__CYGWIN__) || defined(__MACH__)
    term_state s;
    term_init(&s);
#endif

#ifdef FASTMODE
    init_tables();
#endif
    play_game(ask_for_move);

#if defined(_WIN32) || defined(MSDOS) || defined(__WINDOWS__)
#elif defined(_POSIX_SOURCE) || defined(_POSIX_VERSION) || defined(__CYGWIN__) || defined(__MACH__)
    term_clear(&s);
#endif
    return 0;
}

