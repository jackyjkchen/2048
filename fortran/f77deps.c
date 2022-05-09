#include "f90deps.c"

DLLEXPORT unsigned int c_rand__(void) {
    return c_rand_();
}

DLLEXPORT void c_clear_screen__(void) {
    c_clear_screen_();
}

DLLEXPORT int c_getch__(void) {
    return c_getch_();
}

DLLEXPORT void c_print_move_score__(int *moveno, int *current_score, int *last_score) {
    c_print_move_score_(moveno, current_score, last_score);
}

DLLEXPORT void c_print_final_score__(int *final_score) {
    c_print_final_score_(final_score);
}
