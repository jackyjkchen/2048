# 2048

* 2048.c

通常的ISO C90跨平台实现，非严格C90内容仅为64位整数

使用FASTMODE预处理，可启用快速查表法，会增加512KiB的常驻内存开销（意味着dos必须使用dos扩展）

已测试编译器和平台：
```
gcc 2.0+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp)
clang 3.0+ (linux, macos, freebsd, win32)
visual c++ 2.0+ (win32)
openwatcom c++ 1.9 (win32, win386, dos32 pmode, dos4gw)
watcom c++ 11 (win32, win386, dos32 pmode, dos4gw)
borland c++ 5.5 (win32)
```

不使用FASTMODE预处理，代码和数据段可控制在64KiB以内，额外支持：
```
openwatcom c++ 1.9 (dos16 exe, dos16 com, win16)
watcom c++ 11 (dos16 exe, dos16 com, win16)
```


* 2048-16b.c

不使用64位整数的严格ISO C90实现

使用FASTMODE预处理，可启用快速查表法，会增加512KiB的常驻内存开销（意味着dos必须使用dos扩展）

已测试编译器和平台：
```
gcc 2.0+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp)
clang 3.0+ (linux, macos, freebsd, win32)
visual c++ 2.0+ (win32)
openwatcom c++ 1.9 (win32, win386, dos32 pmode, dos4gw)
watcom c++ 11 (win32, win386, dos32 pmode, dos4gw)
borland c++ 5.5 (win32)
```

不使用FASTMODE预处理，代码和数据段可控制在64KiB以内，额外支持：
```
openwatcom c++ 1.9 (dos16 exe, dos16 com, win16)
watcom c++ 11 (dos16 exe, dos16 com, win16)
borland c++ 3.1 (dos16 exe, dos16 com, win16)
turbo c++ 3.0 (dos16 exe, dos16 com)
turbo c 2.0 (dos16 exe, dos16 com)
```


* 2048-ai.cpp

AI实现，ISO C++98实现

由于使用std::map且动态增长内存（可能超过1MiB），因此不支持dos16/win16，无论是否启用FASTMODE预处理（增加768KiB内存占用），编译器和平台支持均一致。

已测试编译器和平台：
```
gcc 2.8+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp)
clang 3.0+ (linux, macos, freebsd, win32)
visual c++ 6.0+ (win32)
openwatcom c++ 1.9 (win32, win386, dos32 pmode, dos4gw)
borland c++ 5.5 (win32)
```


* 2048-sai.c

AI的慢速实现，不使用C++ std::map cache，ISO C90实现，非严格C90内容仅为64位整数

编译器和平台支持与2048.c相同



* 2048.py

python实现，查表法（相当于2048.c + FASTMODE）。已测试支持python2.4+，python3.0+，支持各种Posix变体和Win32。


* 2048.pas

现代pascal实现，查表法（相当于2048.c + FASTMODE）。用于free pascal、delphi等现代化pascal编译器。
