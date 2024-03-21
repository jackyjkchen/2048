#define SUPPORT_64BIT 1
#define USE_SYSTEM_CLEAR 1
#include "arch.h"

DLLEXPORT void c_clear_screen(void) {
    clear_screen();
}

DLLEXPORT int c_get_ch(void) {
    return get_ch();
}
