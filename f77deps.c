#include <stdio.h>
#include <stdlib.h>
#include <time.h>


#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <conio.h>
#elif defined(__linux__) || defined(__unix__) || defined(__CYGWIN__) || defined(__MACH__)
#include <unistd.h>
#include <termios.h>
#endif

unsigned int c_rand__() {
    static unsigned int seeded = 0;

    if (!seeded) {
        srand((unsigned int)time(NULL));
        seeded = 1;
    }

    return rand();
}

void c_clear_screen__(void) {
#if defined(_WIN32)
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
#elif defined(__linux__) || defined(__unix__) || defined(__CYGWIN__) || defined(__MACH__)
    printf("\033[2J\033[H");
#endif
}

#if defined(_WIN32)

void c_term_init__(void) {
}

void c_term_clear__(void) {
}

#elif defined(__linux__) || defined(__unix__)|| defined(__CYGWIN__) || defined(__MACH__)
typedef struct {
    struct termios oldt, newt;
} term_state;


static void _term_set(int mode) {
    static term_state s;

    if (mode == 1) {
        tcgetattr(STDIN_FILENO, &s.oldt);
        s.newt = s.oldt;
        s.newt.c_lflag &= ~(ICANON | ECHO);
        tcsetattr(STDIN_FILENO, TCSANOW, &s.newt);
    } else {
        tcsetattr(STDIN_FILENO, TCSANOW, &s.oldt);
    }
}

void c_term_init__(void) {
    _term_set(1);
}

void c_term_clear__(void) {
    _term_set(0);
}

#endif

int c_getch__(void) {
#if defined(_WIN32)
    return _getch();
#else
    return getchar();
#endif
}

void c_print_move_score__(int *moveno, int *current_score, int *last_score) {
    printf("Move #%d, current score=%d(+%d)\n", *moveno, *current_score, *current_score - *last_score);
}

void c_print_final_score__(int *final_score) {
    printf("Game over. Your score is %d.\n", *final_score);
}
