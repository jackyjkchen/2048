#ifndef __ARCH_H__
#define __ARCH_H__

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
#define __16BIT__ 1
#endif

#if defined(__TINYC__)
#define NOT_USE_WIN32_SDK 1
#endif

#if defined(_WIN32) && !defined(NOT_USE_WIN32_SDK)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <conio.h>
#define DLLEXPORT __declspec(dllexport)
#elif defined(UNIX_LIKE)
#include <unistd.h>
#include <termios.h>
#define DLLEXPORT
#elif defined(__WATCOMC__)
#include <graph.h>
#define DLLEXPORT
#elif defined(__BORLANDC__) || defined (__TURBOC__) || defined(__DJGPP__) || defined(MSDOS) || defined(__CC65__)
#include <conio.h>
#define DLLEXPORT
#endif

#if defined(_MSC_VER) && _MSC_VER >= 700 && defined(__STDC__)
#define _GETCH_USE 1
#elif defined(__WATCOMC__) && __WATCOMC__ < 1100
#define GETCH_USE 1
#endif

#if defined(__MINGW64__) || defined(__MINGW32__)
#undef __USE_MINGW_ANSI_STDIO
#define __USE_MINGW_ANSI_STDIO 0
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

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
#ifndef USE_SYSTEM_CLEAR
    printf("\033[2J\033[H");
#else
    int ret = system("clear");
	(void)ret;
#endif
#elif defined(__WATCOMC__)
    _clearscreen(_GCLEARSCREEN);
#elif defined(__BORLANDC__) || defined (__TURBOC__) || defined(__DJGPP__) || defined(__CC65__)
    clrscr();
#elif (defined(_WIN32) && defined(NOT_USE_WIN32_SDK)) || (defined(MSDOS) && !defined(__BCC__))
    system("cls");
#endif
}

#ifndef AI_SOURCE
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
#elif defined(__CC65__)
    return cgetc();
#else
    return getchar();
#endif
}
#endif

typedef unsigned short row_t;
#ifdef __16BIT__
typedef unsigned long score_t;
#else
typedef unsigned int score_t;
#endif

#ifdef SUPPORT_64BIT
#if defined(_MSC_VER) || defined(__BORLANDC__) || defined(__WATCOMC__)
typedef unsigned __int64 board_t;
#define W64LIT(x) x##ui64
#else
typedef unsigned long long board_t;
#define W64LIT(x) x##ULL
#endif
static const board_t ROW_MASK = W64LIT(0xFFFF);
static const board_t COL_MASK = W64LIT(0x000F000F000F000F);
#else
typedef struct {
    row_t r0;
    row_t r1;
    row_t r2;
    row_t r3;
} board_t;
#endif

typedef float score_heur_t;

#ifdef AI_SOURCE
#ifndef __16BIT__
#if defined(_MSC_VER) && _MSC_VER >= 1500
#include <intrin.h>
#define popcount __popcnt
#elif defined(__GNUC__) && (__GNUC__ >= 4 || (__GNUC__ == 3 && __GNUC_MINOR__ >= 4))
#define popcount __builtin_popcount
#else
static int popcount(unsigned int bitset) {
    int count = 0;
    while (bitset) {
        bitset &= bitset - 1;
        count++;
    }
    return count;
}
#endif
#endif
#endif

#define _max(a,b) ( ((a)>(b)) ? (a):(b) )
#define _min(a,b) ( ((a)>(b)) ? (b):(a) )

#if !defined(ENABLE_CACHE)
#if defined(_MSC_VER) && _MSC_VER < 600
#define ENABLE_CACHE 0
#else
#define ENABLE_CACHE 1
#endif
#endif

#endif
