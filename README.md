# 项目背景

2048这个游戏复杂性恰到好处，他几乎是全算法+标准输出组成，但是为了更好的游戏体验，又得实现无回显输入和清屏两个系统相关通常不在大多数语言标准库中的功能。

而且跨平台部分的算法，分支、循环、数学运算、逻辑运算、位运算、数组查表等都有，涵盖了一门结构化编程语言大多数基本特性，实现过程中我们还测出并修复了多个老编译器的bug，比如[gcc 2.0-2.2生成错误的移位代码](https://github.com/jackyjkchen/legacy-gcc/commit/03651dd3439f7b2df3a6205a85e7f28b9a86283b)。

AI实现需要关联容器、字典或哈希表做cache以提升性能，考验编译器标准库能力，且算法天然支持四路并发（四路数据无关，不需要锁），考验并发能力。

综上，它非常适合作为跨平台跨编译器测试。

本项目中所有实现的手工版本2048，其输出的格式完全一致（精确到字节），其输入游戏体验完全一致。

本项目中所有实现的AI版本2048，其输出格式完全一致。不同编译器和平台浮点精度可能有差异。多线程版本输出可能有预期内的乱序。

为保障AI性能上的基本实用性——

对于脚本语言或16位DOS目标，限定搜索深度上限为3，此时100%能算到2048，但通常只能算到4096-8192，小概率算到16384。

对于标准库中缺乏关联容器、字典或哈希表的编译型语言（如Fortran），限定搜索深度上限为5，此时100%能算到4096，通常能算到8192-16384，小概率算到32768。

对于标准库拥有关联容器、字典或哈希表的编译型语言（如C++、C#、Rust、Go、Java、VB.net、Pascal，C语言使用[https://github.com/Wirtos/cmap](https://github.com/Wirtos/cmap)作为关联容器），不限定算法搜索深度（实际上限为12），此时100%能算到8192，16384概率超过90%，32768概率超过30%。


# C

## c/2048.c

通常的ISO C90跨平台实现，非严格C90内容仅为64位整数。

使用FASTMODE预处理（默认），可启用查表法，会增加384KiB的常驻内存开销。

已测试编译器和平台：
```
gcc 1.42+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp, openbsd, netbsd, dragonflybsd, solaris, openserver, unixware)
clang 3.0+ (linux, macos, freebsd, win32, openbsd, netbsd, dragonflybsd)
msvc 2.0+ (win32)
icc 8.1+ (win32, linux)
aocc 1.0+ (linux)
nvhpc/pgi 20.11/21.7 (linux)
open64 4.2.4/4.5.2.1/5.0 (linux)
openwatcom c++ 1.9 (win32, dos32)
watcom c++ 11.0 (win32, dos32)
borland c++ 5.5 (win32)
visualage c++ 3.5 (win32)
tcc 0.9.27 (linux, win32)
pcc 1.1.0 (linux, freebsd)
lcc 4.0 (win32)
dmc 8.57 (win32)
cc (openserver, unixware)
compcert 3.12 (linux)
```

使用FASTMODE=0预处理（dos16目标下默认FASTMODE=0），代码段和数据段可控制在64KiB以内，额外支持：
```
openwatcom c++ 1.9 (dos16)
watcom c++ 11.0 (dos16)
```

* gcc 3.1以下版本需要大量补丁用于支持现代化系统和修复一些bug，[参见legacy-gcc](https://github.com/jackyjkchen/legacy-gcc)。低版本gcc均在legacy-gcc场景测试。

* msvc 2.x都不能使用优化，否则编译器直接crash，包括最新的2.2。其他版本msvc测试的都是补丁打满的版本。

* open64 4.5.2.1为AMD的二进制发布，open64官方并没有4.5.2.1版本。

* openwatcom c++ 1.9的dos32扩展，已测试CauseWay、DOS/4GW、DOS32/A、PMODE/W可用，其余不可用，后面涉及openwatcom的dos32目标均以此为准。

* watcom c++ 11.0的dos32扩展，已测试DOS/4GW可用，其余不可用。后面涉及watcom 11.0的dos32目标均以此为准。

* pcc在较新版本的glibc上，需要使用-D__GNUC__=4 -D__GNUC_MINOR__=2将自己模拟成gcc 4.2。

* dmc不能使用优化，其64位整数运算优化有bug，产生错误代码。

* win64、windows for arm等均为win32的不同硬件架构，不单独说明，类似的linux、bsd等也不针对特定硬件架构，默认跨平台。


## c/2048-16b.c

不使用64位整数的严格ISO C90实现，用于兼容一些老编译器，不使用查表法用以兼容16位DOS。

除了64位整数外，为了兼容一些老编译器或者嵌入式系统，还有如下修改——
* 不使用struct赋值、传参、返回等部分编译器或平台不一定支持的功能。
* 悔棋步数从64限制为16，适配如6502等平台栈内存不足的问题。

已测试编译器和平台：
```
gcc 1.42+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp, openbsd, netbsd, dragonflybsd, solaris, openserver, unixware)
clang 3.0+ (linux, macos, freebsd, win32, openbsd, netbsd, dragonflybsd)
msvc 2.0+ (win32)
icc 8.1+ (win32, linux)
aocc 1.0+ (linux)
nvhpc/pgi 20.11/21.7 (linux)
open64 4.2.4/4.5.2.1/5.0 (linux)
openwatcom c++ 1.9 (win32, dos32, dos16)
watcom c++ 10.6/11.0 (win32, dos32, dos16)
borland c++ 5.5 (win32)
visualage c++ 3.5 (win32)
tcc 0.9.27 (linux, win32)
pcc 1.1.0 (linux, freebsd)
lcc 4.0 (win32)
dmc 8.57 (win32)
cc (openserver, unixware)
compcert 3.12 (linux)
msvc 1.52 (dos16)
msc 5.1/6.0/7.0 (dos16)
quickc 2.01/2.51 (dos16)
borland c++ 2.0/3.1 (dos16)
turbo c++ 1.01/3.0 (dos16)
turbo c 1.5/2.01 (dos16)
symantec c++ 7.5 (dos16)
power c 2.2.2 (dos16)
dev86 0.16.21 (dos16)
cc65 2.19 (c64, apple2)
```

* 因该版本不使用64位整数，msvc 2.x和dmc 8.57可以开启优化。

* watcom c++ 10.6的dos32扩展，已测试DOS/4GW可用，其余不可用。win32目标需要手动添加-D_WIN32。

* msc 5.1不能使用QC IDE上的优化选项，命令行中/Os /Ot /Ox /O都可以使用。

* quickc 1.0语法兼容msc 5.1，但是编译直接crash，原因尚不清楚，不列入兼容列表。

* symantec c++ 7.5支持win32目标，但产出程序无法运行，原因未知，只列dos16兼容。


## c/2048_kr.c

在c/2048-16b.c基础上改用K&R格式。

因为大部分现代编译器仍然支持K&R格式，能编译c/2048-16b.c的编译器应该也能编译c/2048_kr.c，因此只列出新增编译器支持：

```
msc 3.0/4.0 (dos16)
```

* msc 3.0产出的程序无法在Windows NT系统运行。只能用于DOS、Windows 3.x、Windows 9x、Windows Me。

* msc 2.0或以下版本支持的C格式是某种C方言，既不是ANSI C也不是K&R C，因此无法兼容。


## c/2048-ai.c

ISO C90 AI实现，非严格C90内容仅为64位整数。可选支持OpenMP多线程（预处理OPENMP_THREAD控制）。使用[https://github.com/Wirtos/cmap](https://github.com/Wirtos/cmap)作为cache。

### 单线程

默认启用查表法和cache（预处理FASTMODE=1）。

已测试编译器和平台：
```
gcc 1.42+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp, openbsd, netbsd, dragonflybsd, solaris, openserver, unixware)
clang 3.0+ (linux, macos, freebsd, win32, openbsd, netbsd, dragonflybsd)
msvc 2.0+ (win32)
icc 8.1+ (win32, linux)
aocc 1.0+ (linux)
nvhpc/pgi 20.11/21.7 (linux)
open64 4.2.4/4.5.2.1/5.0 (linux)
openwatcom c++ 1.9 (win32, dos32)
watcom c++ 11.0 (win32, dos32)
borland c++ 5.5 (win32)
visualage c++ 3.5 (win32)
tcc 0.9.27 (linux, win32)
pcc 1.1.0 (linux, freebsd)
lcc 4.0 (win32)
dmc 8.57 (win32)
cc (openserver, unixware)
compcert 3.12 (linux)
```

使用FASTMODE=0预处理（dos16目标下默认FASTMODE=0），不启用cache，查表法采取分表形式（单表小于64KiB，总内存需求384KiB），可支持dos16目标（需要compact或large内存模型），限定搜索深度上限为3，额外支持：
```
openwatcom c++ 1.9 (dos16)
watcom c++ 11.0 (dos16)
```

* 编译器相关comments同c/2048.c。

### 多线程

本实现支持多线程，由预处理MULTI_THREAD控制，多线程版本依赖操作系统原生线程（c/thread_pool_c.c），仅支持Win32和Posix两种线程模型，已测试编译器和平台：

已测试编译器和平台：
```
gcc 1.42+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, openbsd, netbsd, dragonflybsd, solaris, openserver, unixware)
clang 3.0+ (linux, macos, freebsd, win32, openbsd, netbsd, dragonflybsd)
msvc 2.0+ (win32)
icc 8.1+ (win32, linux)
aocc 1.0+ (linux)
nvhpc/pgi 20.11/21.7 (linux)
open64 4.2.4/4.5.2.1/5.0 (linux)
openwatcom c++ 1.9 (win32)
watcom c++ 11.0 (win32)
borland c++ 5.5 (win32)
visualage c++ 3.5 (win32)
pcc 1.1.0 (linux, freebsd)
lcc 4.0 (win32)
dmc 8.57 (win32)
```


### OpenMP多线程

本实现支持OpenMP多线程，由预处理OPENMP_THREAD控制，已测试编译器和平台：
```
gcc 4.2+ (linux, freebsd, macos, openbsd, netbsd, dragonflybsd, solaris)
clang 3.5+ (linux, freebsd，macos, openbsd, netbsd, dragonflybsd)
msvc 8.0+ (win32)
icc 8.1+ (win32, linux)
aocc 1.0+ (linux)
nvhpc/pgi 20.11/21.7 (linux)
open64 4.2.4/4.5.2.1/5.0 (linux)
```

gcc编译示例：
```
gcc -DOPENMP_THREAD -O2 -fopenmp c/2048-ai.c -o 2048 -lm
```


## c/2048ai16.c

不使用64位整数的严格ISO C90 AI实现，不启用cache，查表法采取分表形式（单表小于64KiB，总内存需求256KiB），支持dos16目标（需要compact或large内存模型），限定搜索深度上限为3。

已测试编译器和平台：
```
gcc 1.42+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp, openbsd, netbsd, dragonflybsd, solaris, openserver, unixware)
clang 3.0+ (linux, macos, freebsd, win32, openbsd, netbsd, dragonflybsd)
msvc 2.0+ (win32)
icc 8.1+ (win32, linux)
aocc 1.0+ (linux)
nvhpc/pgi 20.11/21.7 (linux)
open64 4.2.4/4.5.2.1/5.0 (linux)
openwatcom c++ 1.9 (win32, dos32, dos16)
watcom c++ 10.6/11.0 (win32, dos32, dos16)
borland c++ 5.5 (win32)
visualage c++ 3.5 (win32)
tcc 0.9.27 (linux, win32)
pcc 1.1.0 (linux, freebsd)
lcc 4.0 (win32)
dmc 8.57 (win32)
cc (openserver, unixware)
compcert 3.12 (linux)
msvc 1.52 (dos16)
msc 5.1/6.0/7.0 (dos16)
quickc 2.01/2.51 (dos16)
borland c++ 2.0/3.1 (dos16)
turbo c++ 1.01/3.0 (dos16)
turbo c 1.5/2.01 (dos16)
symantec c++ 7.5 (dos16)
power c 2.2.2 (dos16)
```

* 编译器相关comments同c/2048-16b.c。



# C++

## cpp/2048.cpp

ISO C++98实现，使用64位整数，不依赖C++标准库。

使用FASTMODE预处理（默认），可启用查表法，会增加384KiB的常驻内存开销。

已测试编译器和平台：
```
gcc 2.1+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp, openbsd, netbsd, dragonflybsd, solaris, openserver, unixware)
clang 3.0+ (linux, macos, freebsd, win32, openbsd, netbsd, dragonflybsd)
msvc 2.0+ (win32)
icc 8.1+ (win32, linux)
aocc 1.0+ (linux)
nvhpc/pgi 20.11/21.7 (linux)
open64 4.2.4/4.5.2.1/5.0 (linux)
openwatcom c++ 1.9 (win32, dos32)
watcom c++ 11.0 (win32, dos32)
borland c++ 5.5 (win32)
visualage c++ 3.5 (win32)
dmc 8.57 (win32)
```

使用FASTMODE=0预处理（dos16目标下默认FASTMODE=0），代码段和数据段可控制在64KiB以内，额外支持：
```
openwatcom c++ 1.9 (dos16)
watcom c++ 11.0 (dos16)
```

* gcc版本低于2.6时，不识别cpp扩展名，请编译软链接cc扩展名，后同。

* 其余编译器已知问题参见c/2048.c。

## cpp/2048-16b.cpp

ISO C++98实现，不使用64位整数，不使用查表法。由于不依赖C++标准库，前标准时代的老旧C++编译器大都能支持。

已测试编译器和平台：
```
gcc 2.1+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp, openbsd, netbsd, dragonflybsd, solaris, openserver, unixware)
clang 3.0+ (linux, macos, freebsd, win32, openbsd, netbsd, dragonflybsd)
msvc 2.0+ (win32)
icc 8.1+ (win32, linux)
aocc 1.0+ (linux)
nvhpc/pgi 20.11/21.7 (linux)
open64 4.2.4/4.5.2.1/5.0 (linux)
openwatcom c++ 1.9 (win32, dos32, dos16)
watcom c++ 10.6/11.0 (win32, dos32, dos16)
borland c++ 5.5 (win32)
visualage c++ 3.5 (win32)
dmc 8.57 (win32)
msvc 1.52 (dos16)
msc 7.0 (dos16)
borland c++ 2.0/3.1 (dos16)
turbo c++ 1.01/3.0 (dos16)
symantec c++ 7.5 (dos16)
```


## cpp/2048-ai.cpp

AI版本，ISO C++98实现，可选支持多线程（预处理MULTI_THREAD或OPENMP_THREAD），默认启用查表法和std::map cache。

### 单线程

不启用MULTI_THREAD时（默认），无须依赖thread_pool.cpp，已测试编译器和平台：
```
gcc 2.6.3+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp, openbsd, netbsd, dragonflybsd, solaris, openserver, unixware)
clang 3.0+ (linux, macos, freebsd, win32, openbsd, netbsd, dragonflybsd)
msvc 4.2+ (win32)
icc 8.1+ (win32, linux)
aocc 1.0+ (linux)
nvhpc/pgi 20.11/21.7 (linux)
open64 4.2.4/4.5.2.1/5.0 (linux)
openwatcom c++ 1.9 (win32, dos32)
watcom c++ 11.0 (win32, dos32)
borland c++ 5.5 (win32)
dmc 8.57 (win32)
```

若使用FASTMODE=0预处理（dos16目标下默认FASTMODE=0），不启用std::map cache，查表法采取分表形式（单表小于64KiB，总内存需求384KiB），可支持dos16目标（需要compact或large内存模型），由于速度很慢，因此限制搜索深度上限为3，额外支持：
```
gcc 2.1/2.2.2/2.3.3/2.4.5/2.5.8 (linux)
msvc 2.x (win32)
visualage c++ 3.5 (win32)
openwatcom c++ 1.9 (dos16)
watcom c++ 11.0 (dos16)
```

* msvc 5.0必须应用SP3，否则优化选项会生成错误代码或者编译失败，其他版本msvc也都测试的是补丁打满的版本。

* watcom c++ 11.0未包含STL，需要使用[经过修改的STLport-4.5.3](http://assa.4ip.ru/watcom/stlport.html)，下文多线程场景一样。其他只要有内置STL的编译器尽量使用内置STL而非STLport。

* dmc不能使用优化，其64位整数运算优化有bug，产生错误代码。

* gcc-2.6.3使用的libg++-2.6.x中的STL非常原始，问题很多，默认是不会安装stl头文件的，legacy-gcc的libg++-2.6.2[调整](https://github.com/jackyjkchen/legacy-gcc/commit/354b366f60bb37359adbcb7307ab70039b5a3829#diff-ef832efd837dd21850a4ae1c9b95e0e353ce653288d1de797d24a5178f130031)后会安装，但不在默认搜索路径。编译示例：
```
g++-2.6.3 -O2 -I/usr/lib/gcc-lib/i686-legacy-linux-gnu/2.6.3/include/g++/stl  cpp/2048-ai.cpp -lstdc++ -lm -o 2048
```

* gcc-2.6.3也可以使用STLPort-2.033，在legacy-gcc中已提供，编译示例：
```
g++-2.6.3 -O2 -I/usr/lib/gcc-lib/i686-legacy-linux-gnu/2.6.3/include/stlport/ cpp/2048-ai.cpp -lm -o 2048
```


### 多线程

本实现支持多线程，由预处理MULTI_THREAD控制，多线程版本依赖操作系统原生线程（cpp/thread_pool.cpp），仅支持Win32和Posix两种线程模型，已测试编译器和平台：
```
gcc 2.6.3+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, openbsd, netbsd, dragonflybsd, solaris)
clang 3.0+ (linux, macos, freebsd, win32, openbsd, netbsd, dragonflybsd)
msvc 4.2+ (win32)
icc 8.1+ (win32, linux)
aocc 1.0+ (linux)
nvhpc/pgi 20.11/21.7 (linux)
open64 4.2.4/4.5.2.1/5.0 (linux)
openwatcom c++ 1.9 (win32)
watcom c++ 11.0 (win32)
borland c++ 5.5 (win32)
```

gcc编译示例：
```
g++ -DMULTI_THREAD -O2 cpp/2048-ai.cpp -pthread -o 2048
```

* gcc 2.7.2需要使用STLPort-3.12.3，在legacy-gcc中已提供，否则libg++-2.7.x的STL在多线程场景下会coredump，编译示例：
```
g++-2.7.2 -DMULTI_THREAD -O2 -I/usr/lib/gcc-lib/i686-legacy-linux-gnu/2.7.2/include/stlport/ cpp/2048-ai.cpp -pthread -o 2048
```

* gcc 2.6.3需要使用STLPort-2.033，在legacy-gcc中已提供，否则根本无法编译通过（使用libg++-2.6.x中的STL也无法编译通过），编译示例：
```
g++-2.6.3 -DMULTI_THREAD -O2 -I/usr/lib/gcc-lib/i686-legacy-linux-gnu/2.6.3/include/stlport/ cpp/2048-ai.cpp -lm -pthread -o 2048
```

* msvc 4.2的STL allocator线程不安全，有概率启动时crash。

### OpenMP多线程

本实现亦支持OpenMP多线程，由预处理OPENMP_THREAD控制，OpenMP多线程不依赖thread_pool.cpp，但编译器和平台更为受限，已测试编译器和平台：
```
gcc 4.2+ (linux, freebsd, macos, openbsd, netbsd, dragonflybsd, solaris)
clang 3.5+ (linux, freebsd，macos, openbsd, netbsd, dragonflybsd)
msvc 8.0+ (win32)
icc 8.1+ (win32, linux)
aocc 1.0+ (linux)
nvhpc/pgi 20.11/21.7 (linux)
open64 4.2.4/4.5.2.1/5.0 (linux)
```

gcc编译示例：
```
g++ -DOPENMP_THREAD -O2 -fopenmp cpp/2048-ai.cpp -o 2048
```


## cpp/2048ai16.cpp

不使用64位整数的ISO C++98 AI实现，不启用cache，查表法采取分表形式（单表小于64KiB，总内存需求256KiB），支持dos16目标（需要compact或large内存模型），限定搜索深度上限为3。

已测试编译器和平台：
```
gcc 2.1+ (linux, freebsd, macos, mingw, mingw-w64, cygwin, djgpp, openbsd, netbsd, dragonflybsd, solaris, openserver, unixware)
clang 3.0+ (linux, macos, freebsd, win32, openbsd, netbsd, dragonflybsd)
msvc 2.0+ (win32)
icc 8.1+ (win32, linux)
aocc 1.0+ (linux)
nvhpc/pgi 20.11/21.7 (linux)
open64 4.2.4/4.5.2.1/5.0 (linux)
openwatcom c++ 1.9 (win32, dos32, dos16)
watcom c++ 10.6/11.0 (win32, dos32, dos16)
borland c++ 5.5 (win32)
visualage c++ 3.5 (win32)
dmc 8.57 (win32)
msvc 1.52 (dos16)
msc 7.0 (dos16)
borland c++ 2.0/3.1 (dos16)
turbo c++ 1.01/3.0 (dos16)
symantec c++ 7.5 (dos16)
```



# Rust

## rust/Game2048

Rust实现，查表法，依赖rand、getch、clearscreen三个crates

已测试编译器和平台（Rust的编译器最低支持版本仅供参考，请尽可能使用最新版本，因为Rust严重依赖社区crates，虽然本身2048代码没有使用任何1.0版本以上的特性，但2022年底必须1.46以上版本才能构建成功，并随时间推移可能有更高需求）：
```
rust 1.46+ (linux, win32, freebsd, macos)
```


## rust/AI2048

Rust AI实现，查表法 + HashMap + 多线程，依赖rand、clearscreen、rayon、num_cpus四个crates

编译器和平台支持同上。




# C#

## csharp/2048.cs

C#实现，查表法。需要.net framework 2.0+。

已测试编译器和平台：
```
visual studio 2005+ (win32)
mono 1.1.1+ (linux, freebsd, macos)
```


## csharp/2048-ai.cs

C# AI实现，查表法 + Dictionary + 多线程。需要.net framework 2.0+。

编译器和平台支持同上。


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



# VB.net

## vb.net/2048.vb

VB.net实现，查表法。需要.net framework 2.0+。

已测试编译器和平台：
```
visual studio 2005+ (win32)
mono 1.2.3+ (linux, freebsd, macos)
```


## vb.net/2048-ai.vb

VB.net AI实现，查表法 + Dictionary + 多线程。需要.net framework 2.0+。

编译器和平台支持同上。


## vb.net/2048-old.vb

VB.net 1.0实现，查表法。兼容.net framework 1.0/1.1，仅支持Win32。

已测试编译器和平台：
```
visual studio 2002+ (win32)
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
jdk 1.5+ (linux, win32, freebsd, macos, openbsd, netbsd, dragonflybsd, solaris)
```

编译运行命令行示例：
```
cd java
gcc -I/opt/openjdk-bin-8.292_p10/include/ -I/opt/openjdk-bin-8.292_p10/include/linux/ -std=c90 -fPIC -O2 -shared javadeps.c -o libjavadeps.so 
javac 2048.java
java -Djava.library.path=. Game2048
```


## java/2048-ai.java + java/javadeps.c

Java AI实现，查表法 + HashMap + 多线程，由于Java标准库不支持清除屏幕，由JNI方式——java/javadeps.c实现。

编译器和平台支持同上。


## java/2048-old.java + java/javadeps.c

兼容Java 1.0的实现。

已测试Java版本和平台：
```
jdk 1.1+ (linux, win32)
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
borland pascal 7.01 (dos16)
turbo pascal 7.1 (dos16)
```


## pascal/2048-old.pas

不使用uint64、break、continue、uses strings的Pascal实现，且不使用查表法。

已测试编译器和平台：
```
free pascal 2.2+ (linux, win32, freebsd, macos, dos32)
borland pascal 7.01 (dos16)
turbo pascal 4.0/5.5/6.0/7.1 (dos16)
quick pascal 1.0 (dos16)
```

* turbo pascal 3.0或以下版本不支持uses，因此无法兼容。


## pascal/2048-ai.pas

Pascal AI实现，查表法，由预处理FASTMODE决定是否使用TDictionary cache（默认不启用），由预处理MULTI_THREAD决定是否使用多线程（默认不启用）。

默认不启用FASTMODE时，限定搜索深度上限为5。编译器支持范围更宽。

已测试编译器和平台：
```
free pascal 2.2+ (linux, win32, freebsd, macos, dos32)
```

启用FASTMODE，依赖TDictionary，搜索深度不限，编译器支持范围较窄。

已测试编译器和平台：
```
free pascal 3.2+ (linux, win32, freebsd, macos, dos32)
```

使用TDictionary+多线程的编译命令行示例：
```
fpc -dMULTI_THREAD -dFASTMODE:=1 -O2 pascal/2048-ai.pas
```



# Fortran

## fortran/2048.F03 + fortran/f03deps.c

现代Fortran2003实现，使用FASTMODE预处理判定是否使用查表法（默认）。系统相关功能（无回显输入，清除屏幕），由fortran/f03deps.c提供。

已测试编译器和平台：
```
gfortran 4.3+ (linux, mingw, mingw-w64, cygwin, freebsd, macos)
```

编译命令行示例：
```
gfortran -std=f2003 -O2 fortran/2048.F03 fortran/f03deps.c -o 2048
```


## fortran/2048-ai.F03 + fortran/f03deps.c

Fortran2003 AI实现，查表法，由于缺乏cache数据结构，限定搜索深度上限为5。系统相关功能（清除屏幕），由fortran/f03deps.c提供。

已测试编译器和平台：
```
gfortran 4.3+ (linux, mingw, mingw-w64, cygwin, freebsd, macos)
```

gfortran 4.3以上版本均支持OpenMP，推荐使用，编译命令行示例如下：

```
gfortran -std=f2003 -O2 -fopenmp fortran/2048-ai.F03 fortran/f03deps.c -o 2048
```


## fortran/2048.F90 + fortran/f90deps.c

现代Fortran90实现，使用FASTMODE预处理判定是否使用查表法（默认）。系统相关功能（无回显输入，清除屏幕），由fortran/f90deps.c提供。

已测试编译器和平台：
```
gfortran 4.0+ (linux, mingw, mingw-w64, cygwin, freebsd, macos)
```

编译命令行示例：
```
gfortran -std=f95 -O2 fortran/2048.F90 fortran/f90deps.c -o 2048
```


## fortran/2048.f + fortran/f77deps.c

传统Fortran77实现，固定模式源码格式，不使用查表法。系统相关功能（无回显输入，清除屏幕），由fortran/f77deps.c提供。

已测试编译器和平台：
```
g77 2.91.66-3.4.6 (linux, mingw, cygwin, freebsd)
gfortran 4.0+ (linux, mingw, mingw-w64, cygwin, freebsd)
```

编译命令行示例：
```
g77-3.4.6 -O2 fortran/2048.f fortran/f77deps.c -o 2048
```

使用-std=gnu，也可兼容gfortran编译器（必须gcc-8.5.0或以下）：
```
gfortran -std=gnu -O2 fortran/2048.f fortran/f90deps.c -o 2048
```



# Python

## python/2048.py

Python实现，不使用查表法。

已测试Python版本和平台：
```
python 2.4+ (linux, win32, freebsd, macos, openbsd, netbsd, dragonflybsd, solaris)
python 3.0+ (linux, win32, freebsd, macos, openbsd, netbsd, dragonflybsd, solaris)
pypy/pypy3 all (linux, win32, macos)
```

* 在amd64 + linux平台，python 2.2/2.3也可以运行，由于缺乏可移植性，不例入兼容列表。


## python/2048-ai.py

Python AI实现，查表法 + 原生dict cache，限定搜索深度上限为3。建议使用pypy速度较快。

Python版本和平台支持同上。


## python/2048-16b.py

不使用64位整数的Python实现，不使用查表法。

已测试Python版本和平台：
```
python 1.6+ (linux, win32, freebsd, macos, openbsd, netbsd, dragonflybsd, solaris)
python 3.0+ (linux, win32, freebsd, macos, openbsd, netbsd, dragonflybsd, solaris)
pypy/pypy3 all (linux, win32, macos)
```

* python 1.6/2.0版本需要编译python的时候手工解除Modules/Setup中termios行的注释启用该module。



# Lua

## lua/2048.lua + lua/luadeps.c

Lua 5.3+实现，使用查表法，依赖Lua 5.3或以上版本提供的原生64位整数运算支持，由于原生Lua对操作系统判定和无回显输入不支持，相关功能由lua/luadeps.c提供。

已测试Lua版本和平台：
```
lua-5.3+ (linux, win32, freebsd, macos)
```

编译运行命令行示例：
```
gcc -std=c99 -I/usr/include/lua5.4 -shared -fPIC -O2 lua/luadeps.c  -o luadeps.so
./lua/2048.lua
```


## lua/2048-ai.lua + lua/luadeps.c

AI实现。查表法 + 原生table cache，限定搜索深度上限为3，依赖Lua 5.3或以上版本提供的原生64位整数运算支持，由于原生Lua对操作系统判定和无回显输入不支持，相关功能由lua/luadeps.c提供。

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
bash 3.1+ (linux, freebsd, macos, openbsd, netbsd, dragonflybsd)
```

* 声称兼容bash语法的zsh不支持64位无符号整数，因此无法运行。

