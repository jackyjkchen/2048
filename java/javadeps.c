#define SUPPORT_64BIT 1
#define USE_SYSTEM_CLEAR 1
#include "arch.h"
#include <jni.h>

JNIEXPORT void JNICALL Java_Game2048_clear_1screen(JNIEnv *env, jobject obj) {
    clear_screen();
}

JNIEXPORT jchar JNICALL Java_Game2048_get_1ch(JNIEnv *env, jobject obj) {
    return get_ch();
}
