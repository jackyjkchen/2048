#define SUPPORT_64BIT 1
#include "arch.h"
#include <lauxlib.h>

static int c_clear_screen(lua_State *L) {
    clear_screen();
	return 1;
}

static int c_getch(lua_State *L) {
    int ret = get_ch();
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
