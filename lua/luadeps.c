#include <stdio.h>
#include <stdlib.h>
#include <lauxlib.h>

#if defined(__linux__) || defined(__unix__) || defined(__CYGWIN__) || defined(__MACH__) || defined(unix)
#define UNIX_LIKE 1
#endif

#if defined(__MSDOS__) || defined(_MSDOS) || defined(__DOS__)
#ifndef MSDOS
#define MSDOS 1
#endif
#endif

#if defined(_WIN32) && !defined(__TINYC__)
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
#elif defined(__BORLANDC__) || defined (__TURBOC__) || defined(__DJGPP__) || defined(MSDOS)
#include <conio.h>
#define DLLEXPORT
#endif

int c_clear_screen(lua_State *L) {
#if defined(_WIN32) && !defined(__TINYC__)
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
#elif (defined(_WIN32) && defined(__TINYC__)) || defined(MSDOS)
    system("cls");
#endif
}

#if defined(_MSC_VER) && _MSC_VER >= 700 && defined(__STDC__)
#define _GETCH_USE 1
#elif defined(__WATCOMC__) && __WATCOMC__ < 1100
#define GETCH_USE 1
#endif

int c_getch(lua_State *L) {
    int ret = 0;
#if (defined(_WIN32) && !defined(GETCH_USE)) || defined(_GETCH_USE)
    ret = _getch();
#elif defined(MSDOS) || defined(GETCH_USE)
    ret = getch();
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

    ret = (error == 1 ? (int)c : -1);
#else
    ret = getchar();
#endif
    if (ret < 97 || ret > 122)
        ret = 0;
    lua_pushnumber(L, ret);
    return 1;
}

static const struct luaL_Reg luadeps[] = {
    {"c_clear_screen", c_clear_screen},
    {"c_getch", c_getch},
    {NULL, NULL}
};

DLLEXPORT int luaopen_luadeps(lua_State *L) {
    luaL_newlib(L, luadeps);
    return 1;
}
