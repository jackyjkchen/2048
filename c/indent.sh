#! /bin/sh
indent -i4 -l120 -nut -br -ce -brf -brs -cdw -bad -bap -as -nbc -npsl -nbfda -nbfde -nbs -ncs -npcs -nss -nprs -T uint8 -T uint16 -T uint32 -T uint64 -T row_t -T board_t -T HANDLE -T DWORD -T COORD -T eval_state -T term_state -T lua_State "$@"
