#include <jni.h>

#ifdef __cplusplus
extern "C" {
#endif

#include <stdio.h>
#include <stdlib.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <conio.h>
#elif defined(__linux__) || defined(__unix__) || defined(__CYGWIN__) || defined(__MACH__)
#include <unistd.h>
#include <termios.h>
#endif

JNIEXPORT void JNICALL Java_Class2048_clear_1screen(JNIEnv *env, jobject obj) {
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
    system("clear");
#endif
}

#if defined(_WIN32)

JNIEXPORT void JNICALL Java_Class2048_term_1init(JNIEnv *env, jobject obj) {
}

JNIEXPORT void JNICALL Java_Class2048_term_1clear(JNIEnv *env, jobject obj) {
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

JNIEXPORT void JNICALL Java_Class2048_term_1init(JNIEnv *env, jobject obj) {
    _term_set(1);
}

JNIEXPORT void JNICALL Java_Class2048_term_1clear(JNIEnv *env, jobject obj) {
    _term_set(0);
}

#endif

JNIEXPORT jchar JNICALL Java_Class2048_get_1ch(JNIEnv *env, jobject obj) {
#if defined(_WIN32)
    return _getch();
#else
    return getchar();
#endif
}

#ifdef __cplusplus
}
#endif