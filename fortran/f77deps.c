#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#if defined(__linux__) || defined(__unix__) || defined(__CYGWIN__) || defined(__MACH__) || defined(unix)
#define UNIX_LIKE 1
#endif

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <conio.h>
#define DLLEXPORT __declspec(dllexport)
#elif defined(UNIX_LIKE)
#include <unistd.h>
#include <termios.h>
#define DLLEXPORT
#endif

DLLEXPORT unsigned int c_rand__() {
    static unsigned int seeded = 0;

    if (!seeded) {
        srand((unsigned int)time(NULL));
        seeded = 1;
    }

    return rand();
}

DLLEXPORT void c_clear_screen__(void) {
#if defined(_WIN32)
#ifdef __TINYC__
    system("cls");
#else
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
#endif
#elif defined(UNIX_LIKE)
    printf("\033[2J\033[H");
#endif
}

#if defined(UNIX_LIKE)
static int posix_getch(void) {
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
}
#endif

DLLEXPORT int c_getch__(void) {
#if defined(_WIN32)
    return _getch();
#elif defined(UNIX_LIKE)
    return posix_getch();
#else
    return getchar();
#endif
}

DLLEXPORT void c_print_move_score__(int *moveno, int *current_score, int *last_score) {
    printf("Move #%d, current score=%d(+%d)\n", *moveno, *current_score, *current_score - *last_score);
}

DLLEXPORT void c_print_final_score__(int *final_score) {
    printf("Game over. Your score is %d.\n", *final_score);
}
