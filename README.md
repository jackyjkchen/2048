# 项目背景

2048这个游戏复杂性恰到好处，他几乎是全算法+标准输出组成，但是为了更好的游戏体验，又得实现无回显输入和清屏两个系统相关通常不在大多数语言标准库中的功能。

而且跨平台部分的算法，分支、循环、数学运算、逻辑运算、位运算、数组查表等都有，涵盖了一门结构化编程语言大多数基本特性，实现过程中我们还测出并修复了多个老编译器的bug，比如[gcc 2.0-2.2生成错误的移位代码](https://github.com/jackyjkchen/legacy-gcc/commit/03651dd3439f7b2df3a6205a85e7f28b9a86283b)。

AI实现需要关联容器做cache以提升性能，考验编译器标准库能力，且算法天然支持四路并发（四路数据无关，不需要锁），考验并发能力。

综上，它非常适合作为跨平台跨编译器测试。

本项目中所有实现的手工版本2048，其输出的格式完全一致（精确到字节），其输入游戏体验完全一致。

本项目中所有实现的AI版本2048，其输出格式完全一致。不同编译器和平台浮点精度可能有差异。多线程版本输出可能有预期内的乱序。


# C&C++

## c/2048.c

通常的ISO C90跨平台实现，非严格C90内容仅为64位整数。

使用FASTMODE预处理（默认），可启用查表法，会增加384KiB的常驻内存开销。

已测试编译器和平台：
```
gcc 2.0+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp)
clang 3.0+ (linux, macos, freebsd, win32)
msvc 2.0+ (win32)
icc 8.1+ (win32, linux)
openwatcom c++ 1.9 (win32, dos32)
watcom c++ 11.0 (win32, dos32)
borland c++ 5.5 (win32)
visualage c++ 3.5 (win32)
tcc 0.9.27 (linux, win32)
pcc 1.1.0 (linux, freebsd)
lcc 4.0 (win32)
dmc 8.57 (win32)
```

* gcc 3.1以下版本需要大量补丁用于支持现代化系统和修复一些bug，[参见](https://github.com/jackyjkchen/legacy-gcc)。

* msvc 2.x都不能使用优化，否则编译器直接crash，包括最新的2.2。其他版本msvc测试的都是补丁打满的版本。

* openwatcom c++ 1.9的dos32扩展，已测试CauseWay、DOS/4GW、DOS32/A、PMODE/W可用，其余不可用，后面涉及openwatcom的dos32目标均以此为准。

* watcom c++ 11.0的dos32扩展，已测试DOS/4GW可用，其余不可用。后面涉及watcom 11.0的dos32目标均以此为准。

* pcc在较新版本的glibc上，需要使用-D__GNUC__=4 -D__GNUC_MINOR__=2将自己模拟成gcc 4.2。

* dmc不能使用优化，其64位整数运算优化有bug，产生错误代码。

* win64、windows for arm等均为win32的不同硬件架构，不单独说明，类似的linux、bsd等也不针对特定硬件架构，默认跨平台。

使用FASTMODE=0预处理，代码和数据段可控制在64KiB以内，额外支持：
```
openwatcom c++ 1.9 (dos16)
watcom c++ 11.0 (dos16)
```

## c/2048-16b.c

不使用64位整数的严格ISO C90实现，用于兼容一些老编译器，由于目标是老编译器，因此去掉了查表法部分的代码。

已测试编译器和平台：
```
gcc 2.0+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp)
clang 3.0+ (linux, macos, freebsd, win32)
msvc 2.0+ (win32)
icc 8.1+ (win32, linux)
openwatcom c++ 1.9 (win32, dos32, dos16)
watcom c++ 11.0 (win32, dos32, dos16)
borland c++ 5.5 (win32)
visualage c++ 3.5 (win32)
tcc 0.9.27 (linux, win32)
pcc 1.1.0 (linux, freebsd)
lcc 4.0 (win32)
dmc 8.57 (win32)
msvc 1.52 (dos16)
msc 5.1/6.0/7.0 (dos16)
quickc 2.01/2.51 (dos16)
borland c++ 2.0/3.1 (dos16)
turbo c++ 1.01/3.0 (dos16)
turbo c 1.5/2.01 (dos16)
power c 2.2.2 (dos16)
```

* 因该版本不使用64位整数，msvc 2.x和dmc 8.57可以开启优化。

* msc 5.1不能使用QC IDE上的优化选项，命令行中/Os /Ot /Ox /O都可以使用。

* quickc 1.0语法兼容msc 5.1，但是编译直接crash，原因尚不清楚，不列入兼容列表。


## c/2048_kr.c

在c/2048-16b.c基础上改用K&R格式。

因为大部分现代编译器仍然支持K&R格式，能编译c/2048-16b.c的编译器应该也能编译c/2048_kr.c，因此只列出新增编译器支持：

```
msc 3.0/4.0 (dos16)
```

* msc 3.0产出的程序无法在Windows 2000以上系统运行。

* msc 2.0或以下版本支持的C格式是某种C方言，既不是ANSI C也不是K&R C，因此无法兼容。


## cpp/2048-ai.cpp + cpp/thread_pool.cpp + cpp/thread_pool.h

AI版本，ISO C++98实现，可选支持多线程（预处理MULTI_THREAD或OPENMP_THREAD）。

由于使用std::map且动态增长内存（可能超过1MiB），因此不支持dos16，无论是否启用FASTMODE预处理（默认启用，增加640KiB内存占用），编译器和平台支持均一致。

不启用MULTI_THREAD时（默认），无须依赖thread_pool.cpp，已测试编译器和平台：
```
gcc 2.6.3+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp)
clang 3.0+ (linux, macos, freebsd, win32)
msvc 4.2+ (win32)
icc 8.1+ (win32, linux)
openwatcom c++ 1.9 (win32, dos32)
watcom c++ 11.0 (win32, dos32)
borland c++ 5.5 (win32)
dmc 8.57 (win32)
```

* msvc 5.0必须应用SP3，否则优化选项会生成错误代码或者编译失败，其他版本msvc也都测试的是补丁打满的版本。

* watcom c++ 11.0未包含STL，需要使用[经过修改的STLport-4.5.3](http://assa.4ip.ru/watcom/stlport.html)，下文多线程场景一样。其他只要有内置STL的编译器尽量使用内置STL而非STLport。

* dmc不能使用优化，其64位整数运算优化有bug，产生错误代码。

* libg++-2.6.x中的STL非常原始，问题很多，默认是不会安装stl头文件的，legacy-gcc的libg++-2.6.2[调整](https://github.com/jackyjkchen/legacy-gcc/commit/354b366f60bb37359adbcb7307ab70039b5a3829#diff-ef832efd837dd21850a4ae1c9b95e0e353ce653288d1de797d24a5178f130031)后会安装，但不在默认搜索路径。编译示例：
```
g++-2.6.3 -I/usr/lib/gcc-lib/i686-legacy-linux-gnu/2.6.3/include/g++/stl -O2 cpp/2048-ai.cpp -lstdc++ -lm -o 2048
```


本实现支持多线程，由预处理MULTI_THREAD控制，编译示例如下，以gcc为例：
```
g++ -DMULTI_THREAD -O2 cpp/2048-ai.cpp cpp/thread_pool.cpp -pthread -o 2048
```

多线程版本依赖操作系统原生线程，因此dos等都不支持，已测试编译器和平台：
```
gcc 2.7.2+ (linux, freebsd, macos, mingw, mingw-w64, cygwin)
clang 3.0+ (linux, macos, freebsd, win32)
msvc 4.2+ (win32)
icc 8.1+ (win32, linux)
openwatcom c++ 1.9 (win32)
watcom c++ 11.0 (win32, dos32)
borland c++ 5.5 (win32)
```

* gcc 2.7.2需要使用[经过修改的STLPort-3.12.2](https://github.com/jackyjkchen/legacy-gcc/blob/master/dev-libs/stlport/files/3.12.2/00_stlport-3.12.2.patch)，在legacy-gcc中已提供，否则libg++-2.7.x的STL在多线程场景下会coredump，编译示例：
```
g++-2.7.2 -DMULTI_THREAD -O2 -I/usr/lib/gcc-lib/i686-legacy-linux-gnu/2.7.2.3/include/stlport/ cpp/2048-ai.cpp cpp/thread_pool.cpp -pthread -o 2048
```

本实现亦支持OpenMP多线程，由预处理OPENMP_THREAD控制，编译示例如下，以gcc为例：
```
g++ -DOPENMP_THREAD -O2 -fopenmp cpp/2048-ai.cpp -o 2048
```

OpenMP多线程不依赖thread_pool.cpp，但编译器和平台更为受限，已测试编译器和平台：

```
gcc 4.2+ (linux, freebsd, macos)
clang 3.5+ (linux, freebsd，macos)
msvc 8.0+ (win32)
icc 8.1+ (win32, linux)
```



# C#

## csharp/2048.cs

C#实现，查表法。需要.net framework 2.0+。

已测试编译器和平台：
```
visual studio 2005+ (win32)
mono 1.1.1+ (linux, freebsd, macos)
```


## csharp/2048-old.cs + csharp/csdeps.c

C# 1.0实现，查表法，兼容.net framework 1.0/1.1。由于.net 1.0/1.1缺少System.Console.ReadKey()和System.Console.Clear()，因此由csharp/csdeps.c提供跨平台实现

已测试编译器和平台：
```
visual studio 2002+ (win32)
mono 1.0+ (linux, freebsd, macos)
```

编译运行命令行示例：
```
gcc -O2 -fPIC -shared csharp/csdeps.c -o libcsdeps.so
mcs csharp/2048-old.cs  -out:2048-old.exe
mono 2048-old.exe
```


## csharp/2048-ai.cs

C# AI实现，查表法 + Dictionary + 多线程。需要.net framework 2.0+。

已测试编译器和平台：
```
visual studio 2005+ (win32)
mono 1.1.1+ (linux, freebsd, macos)
```



# VB.net

## vbdotnet/2048.vb

VB.net实现，查表法。需要.net framework 2.0+。

已测试编译器和平台：
```
visual studio 2005+ (win32)
mono 1.2.3+ (linux, freebsd, macos)
```


## vbdotnet/2048-old.vb

VB.net 1.0实现，查表法。兼容.net framework 1.0/1.1，仅支持Win32。

已测试编译器和平台：
```
visual studio 2002+ (win32)
```


## vbdotnet/2048-ai.vb

VB.net AI实现，查表法 + Dictionary + 多线程。需要.net framework 2.0+。

已测试编译器和平台：
```
visual studio 2005+ (win32)
mono 1.2.3+ (linux, freebsd, macos)
```



# Go

## go/2048.go + go/godeps.c

Go实现，查表法，由于Go标准库不支持无回显输入和清除屏幕两个系统相关功能，由go/godeps.c提供。

已测试编译器和平台：
```
go 1.4+ (linux, win32, freebsd, macos)
gccgo 5+ (linux, freebsd, macos)
```

编译命令行示例：
```
cd go
gcc -std=c90 -O2 -c godeps.c -o godeps.o
ar rc libgodeps.a godeps.o
go build 2048.go
```


## go/2048-ai.go + go/godeps.c

Go AI实现，查表法 + map + goroutine并发，由于Go标准库不支持清除屏幕，由go/godeps.c提供。

编译器和平台支持同上。



# Java

## java/2048.java + java/javadeps.c

Java实现，查表法，由于Java标准库不支持无回显输入和清除屏幕两个系统相关功能，由JNI方式——java/javadeps.c实现。

已测试Java版本和平台：
```
jdk 1.5+ (linux, win32, freebsd, macos)
```

编译运行命令行示例：
```
cd java
gcc -I/opt/openjdk-bin-8.292_p10/include/ -I/opt/openjdk-bin-8.292_p10/include/linux/ -std=c90 -fPIC -O2 -shared javadeps.c -o libjavadeps.so 
javac 2048.java
java -Djava.library.path=. Class2048
```


## java/2048-old.java + java/javadeps.c

兼容Java 1.0的实现，其余同上。

已测试Java版本和平台：
```
jdk 1.1+ (linux, win32)
```


## java/2048-ai.java + java/javadeps.c

Java AI实现，查表法 + HashMap + 多线程，由于Java标准库不支持清除屏幕，由JNI方式——java/javadeps.c实现。

已测试Java版本和平台：
```
jdk 1.5+ (linux, win32, freebsd, macos)
```



# Pascal

## pascal/2048.pas

现代Pascal实现，使用uint64，由预处理FASTMODE决定是否使用查表法（默认）。

已测试编译器和平台：
```
free pascal 2.2+ (linux, win32, freebsd, macos, dos32)
```


## pascal/2048-16b.pas

不使用uint64的Pascal实现，且不使用查表法。

已测试编译器和平台：
```
free pascal 2.2+ (linux, win32, freebsd, macos, dos32)
turbo pascal 7.1 (dos16)
```


## pascal/2048-old.pas

不使用uint64、break、continue、uses strings的Pascal实现，且不使用查表法。

已测试编译器和平台：
```
free pascal 2.2+ (linux, win32, freebsd, macos, dos32)
turbo pascal 4.0/5.5/6.0/7.1 (dos16)
```

* turbo pascal 3.0或以下版本不支持uses，因此无法兼容。


## pascal/2048-ai.pas

Pascal AI实现，查表法 + TDictionary，由预处理MULTI_THREAD决定是否使用多线程（默认不启用）。

已测试编译器和平台：
```
free pascal 3.2+ (linux, win32, freebsd, macos, dos32)
```

使用多线程的编译命令行示例：
```
fpc -dMULTI_THREAD -O2 pascal/2048-ai.pas
```



# Fortran

## fortran/2048.F03

现代Fortran2003实现，使用FASTMODE预处理判定是否使用查表法（默认）。

已测试编译器和平台：
```
gcc 4.3+ (linux, mingw, mingw-w64, cygwin, freebsd, macos)
```

* gfortran不感知_WIN32等C语言预处理器，WIN32平台要在命令行显式指定-D_WIN32。



## fortran/2048.F90 + fortran/f90deps.c

现代Fortran90实现，使用FASTMODE预处理判定是否使用查表法（默认）。由于f90没有提供iso_c_binding，所以系统相关功能（无回显输入，清除屏幕），由fortran/f90deps.c提供。

已测试编译器和平台：
```
gcc 4.0+ (linux, mingw, mingw-w64, cygwin, freebsd, macos)
```

编译命令行示例：
```
gcc -std=c90 -O2 -c fortran/f90deps.c -o f90deps.o
gfortran -std=f95 -O2 fortran/2048.F90 f90deps.o -o 2048
```


## (fortran/2048f.f or fortran/2048s.f) + fortran/f77deps.c

传统Fortran77实现，固定模式源码格式，2048f.f使用查表法，2048s.f不使用，由于f77没有提供iso_c_binding，所以系统相关功能（无回显输入，清除屏幕），由fortran/f77deps.c提供。

已测试编译器和平台：
```
g77 2.91.66-3.4.6 (linux, mingw, cygwin, freebsd)
gfortran 4.0+ (linux, mingw, mingw-w64, cygwin, freebsd)
```

编译命令行示例：
```
gcc-3.4.6 -O2 -c fortran/f77deps.c -o f77deps.o
g77-3.4.6 -O2 fortran/2048f.f f77deps.o -o 2048
```

使用-std=gnu，也可使用gfortran编译器：
```
gcc -std=c90 -O2 -c fortran/f90deps.c -o f90deps.o
gfortran -std=gnu -O2 fortran/2048f.f f90deps.o -o 2048
```



# Python

## python/2048.py

Python实现，由于脚本语言初始化大数组较慢，因此不使用查表法。

已测试Python版本和平台：
```
python 2.4+ (linux, win32, freebsd, macos)
python 3.0+ (linux, win32, freebsd, macos)
pypy/pypy3 all (linux, win32, macos)
```

## python/2048-tab.py

Python实现，使用查表法，在低配置设备上启动较慢，但执行较快。

Python版本和平台支持同上。


## python/2048-ai.py

Python AI实现，查表法 + 原生dict cache，建议使用pypy速度较快。

Python版本和平台支持同上。



# Lua

## lua/2048.lua + lua/luadeps.c

Lua 5.3+实现，依赖Lua 5.3或以上版本提供的原生64位整数运算支持，由于原生Lua对操作系统判定和无回显输入不支持，相关功能由lua/luadeps.c提供。由于脚本语言初始化大数组较慢，因此不使用查表法。

已测试Lua版本和平台：
```
lua-5.3+ (linux, win32, freebsd, macos)
```

编译运行命令行示例：
```
gcc -std=c99 -I/usr/include/lua5.4 -shared -fPIC -O2 lua/luadeps.c  -o luadeps.so
./lua/2048.lua
```


## lua/2048-tab.lua + lua/luadeps.c

Lua 5.3+实现，依赖Lua 5.3或以上版本提供的原生64位整数运算支持，由于原生Lua对操作系统判定和无回显输入不支持，相关功能由lua/luadeps.c提供。使用查表法，低配置设备上启动较慢，但执行较快。

Lua版本和平台支持同上。


## lua/2048-ai.lua + lua/luadeps.c

AI实现。查表法 + 原生table cache，依赖Lua 5.3或以上版本提供的原生64位整数运算支持，由于原生Lua对操作系统判定和无回显输入不支持，相关功能由lua/luadeps.c提供。

Lua版本和平台支持同上。



# Perl

## perl/2048.pl

Perl实现，由于脚本语言初始化大数组较慢，因此不使用查表法。依赖Term::ReadKey和Term::ANSIScreen两个CPAN模块。

已测试Perl版本和平台：
```
perl 5.8+ (linux, win32, freebsd, macos)
```


# Shell

## shell/2048.sh

Bash实现，仅能用于Posix兼容系统（依赖tty设备），由于bash数组性能很差，因此使用非查表实现。

测试Shell和平台：
```
bash 3.1+ (linux, freebsd, macos)
```

* 声称兼容bash语法的zsh不支持64位无符号整数，因此无法运行。


## shell/2048-16b.sh

Bash实现，不使用64位整数运算，仅能用于Posix兼容系统（依赖tty设备），由于bash数组性能很差，因此使用非查表实现。

测试Shell和平台：
```
bash 3.1+ (linux, freebsd, macos)
```

* 不支持悔棋

