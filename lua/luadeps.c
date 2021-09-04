#include <stdio.h>
#include <stdlib.h>

#include <lauxlib.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <conio.h>
#elif defined(__linux__) || defined(__unix__) || defined(__CYGWIN__) || defined(__MACH__)
#include <unistd.h>
#include <termios.h>
#endif

int c_clear_screen(lua_State *L) {
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
#elif defined(__linux__) || defined(__unix__) || defined(__CYGWIN__) || defined(__MACH__)
    printf("\033[2J\033[H");
#endif
    return 1;
}

#if defined(_WIN32)

int c_term_init(lua_State *L) {
    return 1;
}

int c_term_clear(lua_State *L) {
    return 1;
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

int c_term_init(lua_State *L) {
    _term_set(1);
    return 1;
}

int c_term_clear(lua_State *L) {
    _term_set(0);
    return 1;
}

#endif

int c_getch(lua_State *L) {
    int ret = 0;

#if defined(_WIN32)
    ret = _getch();
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
    {"c_term_init", c_term_init},
    {"c_term_clear", c_term_clear},
    {"c_getch", c_getch},
    {NULL, NULL}
};

#if defined(_WIN32)
#define DLLEXPORT __declspec(dllexport)
#else
#define DLLEXPORT
#endif
DLLEXPORT int luaopen_luadeps(lua_State *L) {
    luaL_newlib(L, luadeps);
    return 1;
}
