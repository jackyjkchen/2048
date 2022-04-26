#! /bin/sh
VERSION_CONTROL=none indent -i4 -l120 -nut -br -ce -brf -brs -cdw -bad -bap -as -nbc -npsl -nbfda -nbfde -nbs -ncs -npcs -nss -nprs -T row_t -T board_t -T score_t -T score_heur_t -T HANDLE -T DWORD -T COORD -T TCHAR -T eval_state -T lua_State -T JNIEXPORT -T JNICALL -T JNIEnv -T jchar -T jobject  "$@"
