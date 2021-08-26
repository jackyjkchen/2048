# 2048

* 2048.c

通常的ISO C90跨平台实现，非严格C90内容仅为64位整数

使用FASTMODE预处理，可启用快速查表法，会增加512KiB的常驻内存开销（意味着dos平台下必须使用dos扩展）

已测试编译器和平台：
```
gcc 2.0+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp)
clang 3.0+ (linux, macos, freebsd, win32)
visual c++ 2.0+ (win32)
openwatcom c++ 1.9 (win32, win386, dos32 pmode, dos4gw)
borland c++ 5.5 (win32)
```

注1：VC++ 2.0使用release版编译会报错，VC自己的bug

注2：gcc低版本需要大量补丁用于支持现代化系统，[参见](https://github.com/jackyjkchen/legacy-gcc)


不使用FASTMODE预处理，代码和数据段可控制在64KiB以内，额外支持：
```
openwatcom c++ 1.9 (dos16 exe, dos16 com, win16)
```


* 2048-16b.c

不使用64位整数的严格ISO C90实现

使用FASTMODE预处理，可启用快速查表法，会增加512KiB的常驻内存开销（意味着dos平台下必须使用dos扩展）

已测试编译器和平台：
```
gcc 2.0+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp)
clang 3.0+ (linux, macos, freebsd, win32)
visual c++ 2.0+ (win32)
openwatcom c++ 1.9 (win32, win386, dos32 pmode, dos4gw)
borland c++ 5.5 (win32)
```

不使用FASTMODE预处理，代码和数据段可控制在64KiB以内，额外支持：
```
openwatcom c++ 1.9 (dos16 exe, dos16 com, win16)
borland c++ 3.1 (dos16 exe, dos16 com, win16)
turbo c++ 1.01/3.0 (dos16 exe, dos16 com)
turbo c 1.5/2.01 (dos16 exe, dos16 com)
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

python实现，使用查表法（相当于2048.c + FASTMODE）。支持python2.4+，python3.0+，支持各种Posix变体和Win32。

已测试python版本和平台
```
python 2.4-2.7 (linux, win32, freebsd, macos)
python 3.0+ (linux, win32, freebsd, macos)
```


* 2048.pas

现代pascal实现，使用uint64+查表法（相当于2048.c + FASTMODE）。用于free pascal、delphi等现代化pascal编译器。

已测试编译器和平台
```
free pascal 2.6.4/3.0.4/3.2.2 (linux, win32, freebsd, macos)
```


* 2048-16b.pas

不使用uint64的pascal实现，且不使用查表法（相当于2048-16b.c且不使用FASTMODE）。用于turbo pascal 7.x。

已测试编译器和平台
```
free pascal 2.6.4/3.0.4/3.2.2 (linux, win32, freebsd, macos)
turbo pascal 7.1 (dos16 exe)
```


* 2048-old.pas

不使用uint64、break、continue、uses strings的pascal实现，且不使用查表法（相当于2048-16b.c且不使用FASTMODE）。用于turbo pascal 6以下等旧版pascal编译器。

已测试编译器和平台
```
free pascal 2.6.4/3.0.4/3.2.2 (linux, win32, freebsd, macos)
turbo pascal 4.0/5.5/6.0/7.1 (dos16 exe)
```


* 2048.F03

现代fortran2003实现，与2048.c一样使用FSASTMODE预处理判定是否使用快速查表法。

已测试编译器和平台
```
gcc-4.3+ (linux, win32, freebsd, macos)
```

注1：gfortran不感知_WIN32等C语言预处理器，WIN32平台要在命令行显式指定-D_WIN32。

