#define SUPPORT_64BIT 1
#include "arch.h"

DLLEXPORT unsigned int c_rand__(void) {
    static unsigned int seeded = 0;

    if (!seeded) {
        srand((unsigned int)time(NULL));
        seeded = 1;
    }

    return rand();
}

DLLEXPORT void c_clear_screen__(void) {
    clear_screen();
}

DLLEXPORT int c_getch__(void) {
    return get_ch();
}

DLLEXPORT void c_print_move_score__(int *moveno, int *current_score, int *last_score) {
    printf("Move #%d, current score=%d(+%d)\n", *moveno, *current_score, *current_score - *last_score);
}

DLLEXPORT void c_print_final_score__(int *final_score) {
    printf("Game over. Your score is %d.\n", *final_score);
}
