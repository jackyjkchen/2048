#include "thread_pool_c.h"
#include "deque.h"

#if defined(__linux__) || defined(linux) || defined(__unix__) || defined(unix) || defined(__CYGWIN__) || defined(__MACH__)
#ifndef __DJGPP__
#define UNIX_LIKE 1
#endif
#endif

#if !defined(_WIN32) && !defined(UNIX_LIKE)
#error "This library need win32 thread or posix thread."
#endif

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <process.h>
#include <limits.h>
typedef CRITICAL_SECTION CriticalSection;
typedef HANDLE THRD_HANDLE;
#define THRD_INST unsigned int WINAPI
#else
#include <unistd.h>
#include <pthread.h>
#include <sys/time.h>
typedef pthread_mutex_t CriticalSection;
typedef pthread_cond_t ConditionVariable;
typedef pthread_t THRD_HANDLE;
#define THRD_INST void*
#endif

#if defined(__MINGW64__) || defined(__MINGW32__)
#undef __USE_MINGW_ANSI_STDIO
#define __USE_MINGW_ANSI_STDIO 0
#endif
#include <stdlib.h>
#include <string.h>

#if defined(__GLIBC__) && __GLIBC__ >= 2 && __GLIBC_MINOR__ >= 2
#include <sys/sysinfo.h>
#define USE_SYSINFO 1
#endif

typedef struct {
    thrd_callback func;
    void *param;
} ThrdContext;

typedef deque_t(ThrdContext) ThreadQueue;

#if defined(WINVER) && WINVER >= 0x0600
typedef CONDITION_VARIABLE ConditionVariable;
#elif defined(WINVER)
typedef struct {
    HANDLE semphore;
    int wait_num;
} LEGACYCV_CTX;

static int legacycv_init(LEGACYCV_CTX* ctx) {
    ctx->semphore = CreateSemaphore(NULL, 0, INT_MAX, NULL);
    if (!ctx->semphore) {
        return 0;
    }
    return 1;
}

static void legacycv_uinit(LEGACYCV_CTX* ctx) {
    CloseHandle(ctx->semphore);
}

static int legacycv_wait(LEGACYCV_CTX* ctx, THREADLOCK_CTX *lock, int timeout_ms) {
    DWORD timeout = INFINITE, ret = 0;

    if (timeout_ms >= 0) {
        timeout = (DWORD)timeout_ms;
    }
    ctx->wait_num++;
    threadlock_unlock(lock);
    ret = WaitForSingleObject(ctx->semphore, timeout);

    threadlock_lock(lock);
    ctx->wait_num--;
    return (ret == WAIT_OBJECT_0);
}

static void legacycv_signal(LEGACYCV_CTX* ctx) {
    if (ctx->wait_num > 0) {
        ReleaseSemaphore(ctx->semphore, 1, NULL);
    }
}

static void legacycv_broadcast(LEGACYCV_CTX* ctx) {
    if (ctx->wait_num > 0) {
        ReleaseSemaphore(ctx->semphore, ctx->wait_num, NULL);
    }
}

typedef LEGACYCV_CTX ConditionVariable;
#endif

typedef struct {
    CriticalSection mutex;
    ConditionVariable cond;
} THREADLOCK_CTX_;

int threadlock_init(THREADLOCK_CTX *ctx) {
    THREADLOCK_CTX_ *ctx_ = NULL;
    if (!ctx->ctx) {
        ctx->ctx = malloc(sizeof(THREADLOCK_CTX_));
        if (!ctx->ctx) {
            return 0;
        }
        memset(ctx->ctx, 0x00, sizeof(THREADLOCK_CTX_));
    } else {
        return 0;
    }
    ctx_ = (THREADLOCK_CTX_*)ctx->ctx;
#ifdef _WIN32
    InitializeCriticalSection(&ctx_->mutex);
#if defined(WINVER) && WINVER >= 0x0600
    InitializeConditionVariable(&ctx_->cond);
#else
    if (!legacycv_init(&ctx_->cond)) {
        free(ctx->ctx);
        ctx->ctx = NULL;
        return 0;
    }
#endif
#else
    pthread_mutex_init(&ctx_->mutex, NULL);
    pthread_cond_init(&ctx_->cond, NULL);
#endif
    return 1;
}

void threadlock_uninit(THREADLOCK_CTX *ctx) {
    THREADLOCK_CTX_ *ctx_ = (THREADLOCK_CTX_*)ctx->ctx;
#ifdef _WIN32
    DeleteCriticalSection(&ctx_->mutex);
#if defined(WINVER) && WINVER < 0x0600
    legacycv_uinit(&ctx_->cond);
#endif
#else
    pthread_mutex_destroy(&ctx_->mutex);
    pthread_cond_destroy(&ctx_->cond);
#endif
    free(ctx->ctx);
    ctx->ctx = NULL;
}

void threadlock_lock(THREADLOCK_CTX *ctx) {
    THREADLOCK_CTX_ *ctx_ = (THREADLOCK_CTX_*)ctx->ctx;
#ifdef _WIN32
    EnterCriticalSection(&ctx_->mutex);
#else
    pthread_mutex_lock(&ctx_->mutex);
#endif
}

void threadlock_unlock(THREADLOCK_CTX *ctx) {
    THREADLOCK_CTX_ *ctx_ = (THREADLOCK_CTX_*)ctx->ctx;
#ifdef _WIN32
    LeaveCriticalSection(&ctx_->mutex);
#else
    pthread_mutex_unlock(&ctx_->mutex);
#endif
}

int threadlock_wait(THREADLOCK_CTX *ctx, int timeout_ms) {
    THREADLOCK_CTX_ *ctx_ = (THREADLOCK_CTX_*)ctx->ctx;
#ifdef _WIN32
#if defined(WINVER) && WINVER >= 0x0600
    DWORD timeout = INFINITE;

    if (timeout_ms >= 0) {
        timeout = (DWORD)timeout_ms;
    }
    return (TRUE == SleepConditionVariableCS(&ctx_->cond, &ctx_->mutex, timeout));
#else
    return legacycv_wait(&ctx_->cond, ctx, timeout_ms);
#endif
#else
    int ret = 0;

    if (timeout_ms >= 0) {
        struct timespec timeout;
        struct timeval now = { 0, 0 };
        gettimeofday(&now, NULL);
        timeout.tv_sec = now.tv_sec + timeout_ms / 1000;
        timeout.tv_nsec = now.tv_usec * 1000 + (timeout_ms % 1000) * 1000 * 1000;
        ret = pthread_cond_timedwait(&ctx_->cond, &ctx_->mutex, &timeout);
    } else {
        ret = pthread_cond_wait(&ctx_->cond, &ctx_->mutex);
    }
    return (ret == 0);
#endif
}

void threadlock_signal(THREADLOCK_CTX *ctx) {
    THREADLOCK_CTX_ *ctx_ = (THREADLOCK_CTX_*)ctx->ctx;
#ifdef _WIN32
#if defined(WINVER) && WINVER >= 0x0600
    WakeConditionVariable(&ctx_->cond);
#else
    legacycv_signal(&ctx_->cond);
#endif
#else
    pthread_cond_signal(&ctx_->cond);
#endif
}

void threadlock_broadcast(THREADLOCK_CTX *ctx) {
    THREADLOCK_CTX_ *ctx_ = (THREADLOCK_CTX_*)ctx->ctx;
#ifdef _WIN32
#if defined(WINVER) && WINVER >= 0x0600
    WakeAllConditionVariable(&ctx_->cond);
#else
    legacycv_broadcast(&ctx_->cond);
#endif
#else
    pthread_cond_broadcast(&ctx_->cond);
#endif
}

#if defined(WINVER) && WINVER >= 0x0501
static DWORD _count_set_bits(ULONG_PTR bitMask) {
    DWORD LSHIFT = sizeof(ULONG_PTR) * 8 - 1;
    DWORD bitSetCount = 0, i = 0;
    ULONG_PTR bitTest = (ULONG_PTR)1 << LSHIFT;

    for (i = 0; i <= LSHIFT; ++i) {
        bitSetCount += ((bitMask & bitTest) ? 1 : 0);
        bitTest /= 2;
    }

    return bitSetCount;
}
#endif

static THRD_INST _threadstart(void *param) {
    ThrdContext *context = (ThrdContext *)param;

    context->func(context->param);
    return 0;
}

int threadpool_cpucount(void) {
    int cpu_num = 0;

#ifdef _WIN32
#if defined(WINVER) && WINVER >= 0x0501
    DWORD length = 0;
    PSYSTEM_LOGICAL_PROCESSOR_INFORMATION buf = NULL, ptr = NULL;
    BOOL ret = FALSE;

    while ((ret = GetLogicalProcessorInformation(buf, &length)) == FALSE) {
        if (GetLastError() == ERROR_INSUFFICIENT_BUFFER) {
            buf = (PSYSTEM_LOGICAL_PROCESSOR_INFORMATION)malloc(length);
            if (!buf) {
                return -1;
            }
        } else {
            free(buf);
            return -1;
        }
    }
    ptr = buf;
    while ((BYTE *)ptr - (BYTE *)buf + sizeof(SYSTEM_LOGICAL_PROCESSOR_INFORMATION) <= length) {
        if (ptr && ptr->Relationship == RelationProcessorCore) {
            cpu_num += _count_set_bits(ptr->ProcessorMask);
        }
        ptr++;
    }
    free(buf);
#else
    SYSTEM_INFO sysinfo;

    GetSystemInfo(&sysinfo);
    cpu_num = sysinfo.dwNumberOfProcessors;
#endif
#elif defined(USE_SYSINFO)
    cpu_num = get_nprocs();
#elif defined(_SC_NPROCESSORS_ONLN)
    cpu_num = (int)sysconf(_SC_NPROCESSORS_ONLN);
#else
    cpu_num = 1;
#endif
    return cpu_num;
}

typedef struct {
    ThreadQueue queue;
    ThrdContext thrd_context;
    THREADLOCK_CTX pool_lock;
    THREADLOCK_CTX ctrl_lock;
    int pool_signaled;
    int stop;
    int thrd_count;
    int active_thrd_count;
    THRD_HANDLE *thread_handle;
} THREADPOOL_CTX_;

int threadpool_thrdcount(THREADPOOL_CTX *ctx) {
    THREADPOOL_CTX_ *ctx_ = (THREADPOOL_CTX_*)ctx->ctx;
    return ctx_->thrd_count;
}

static void thread_instance(void *param) {
    THREADPOOL_CTX_ *ctx_ = (THREADPOOL_CTX_ *)param;

    while (1) {
        ThrdContext context;
        threadlock_lock(&ctx_->pool_lock);
        if (deque_empty(&ctx_->queue)) {
            if (ctx_->stop) {
                threadlock_unlock(&ctx_->pool_lock);
                break;
            }
            ctx_->pool_signaled = 0;
            if (ctx_->active_thrd_count == 0) {
                threadlock_broadcast(&ctx_->pool_lock);
            }
            while (!ctx_->pool_signaled) {
                threadlock_wait(&ctx_->pool_lock, -1);
            }
            threadlock_unlock(&ctx_->pool_lock);
            continue;
        }
        memcpy(&context, deque_pop_front(&ctx_->queue), sizeof(ThrdContext));
        ctx_->active_thrd_count++;
        threadlock_unlock(&ctx_->pool_lock);
        context.func(context.param);
        threadlock_lock(&ctx_->pool_lock);
        ctx_->active_thrd_count--;
        threadlock_unlock(&ctx_->pool_lock);
    }
}

int threadpool_startup(THREADPOOL_CTX *ctx, int max_thrd_num) {
    THREADPOOL_CTX_ *ctx_ = NULL;
    int ret = 0, clear_thrd = 0;

    if (!ctx->ctx) {
        ctx->ctx = malloc(sizeof(THREADPOOL_CTX_));
        if (!ctx->ctx) {
            return 0;
        }
        memset(ctx->ctx, 0x00, sizeof(THREADPOOL_CTX_));
    } else {
        return 0;
    }

    ctx_ = (THREADPOOL_CTX_*)ctx->ctx;
    do {
        if (!deque_init(&ctx_->queue)) {
            break;
        }
        ctx_->thrd_context.func = thread_instance;
        ctx_->thrd_context.param = ctx_;
        if (!threadlock_init(&ctx_->pool_lock)) {
            break;
        }
        if (!threadlock_init(&ctx_->ctrl_lock)) {
            break;
        }
        ctx_->pool_signaled = 0;
        ctx_->stop = 1;
        ctx_->thrd_count = max_thrd_num;
        ctx_->active_thrd_count = 0;
        ctx_->thread_handle = NULL;
        ret = 1;
    } while (0);

    if (!ret) {
        free(ctx->ctx);
        ctx->ctx = NULL;
        return 0;
    }

    threadlock_lock(&ctx_->ctrl_lock);
    do {
        int i = 0;
        ret = 0;
        if (ctx_->thrd_count == 0) {
            ctx_->thrd_count = threadpool_cpucount();
        }
        if (ctx_->thrd_count <= 0) {
            break;
        }
        if (!ctx_->thread_handle) {
            ctx_->thread_handle = (THRD_HANDLE *)malloc(ctx_->thrd_count * sizeof(THRD_HANDLE));
        }
        if (!ctx_->thread_handle) {
            break;
        }
        threadlock_lock(&ctx_->pool_lock);
        if (!ctx_->stop) {
            threadlock_unlock(&ctx_->pool_lock);
            break;
        }
        ctx_->stop = 0;
        threadlock_unlock(&ctx_->pool_lock);
        for (i = 0; i < ctx_->thrd_count; ++i) {
#ifdef _WIN32
            ctx_->thread_handle[i] = (HANDLE)_beginthreadex(NULL, 0, _threadstart, &ctx_->thrd_context, 0, NULL);

            if (!ctx_->thread_handle[i]) {
#else
            if (pthread_create(&ctx_->thread_handle[i], NULL, _threadstart, &ctx_->thrd_context) != 0) {
#endif
                ctx_->thread_handle[i] = 0;
                clear_thrd = 1;
                break;
            }
        }
        ret = 1;
    } while (0);
    threadlock_unlock(&ctx_->ctrl_lock);
    if (!ret) {
        free(ctx->ctx);
        ctx->ctx = NULL;
        if (clear_thrd) {
            threadpool_waitallthrd(ctx);
        }
    }
    return ret;
}

void threadpool_cleanup(THREADPOOL_CTX *ctx) {
    THREADPOOL_CTX_ *ctx_ = (THREADPOOL_CTX_*)ctx->ctx;
    threadpool_waitallthrd(ctx);
    deque_delete(&ctx_->queue);
	threadlock_uninit(&ctx_->pool_lock);
	threadlock_uninit(&ctx_->ctrl_lock);
    free(ctx_->thread_handle);
    free(ctx->ctx);
    ctx->ctx = NULL;
}

int threadpool_addtask(THREADPOOL_CTX *ctx, thrd_callback func, void *param) {
    THREADPOOL_CTX_ *ctx_ = (THREADPOOL_CTX_*)ctx->ctx;
    ThrdContext context;
    int ret = 0;

    threadlock_lock(&ctx_->ctrl_lock);
    context.func = func;
    context.param = param;
    threadlock_lock(&ctx_->pool_lock);
    if (deque_push_back(&ctx_->queue, context)) {
        ret = 1;
    }
    threadlock_signal(&ctx_->pool_lock);
    ctx_->pool_signaled = 1;
    threadlock_unlock(&ctx_->pool_lock);
    threadlock_unlock(&ctx_->ctrl_lock);
    return ret;
}

void threadpool_waitalltask(THREADPOOL_CTX *ctx) {
    THREADPOOL_CTX_ *ctx_ = (THREADPOOL_CTX_*)ctx->ctx;
    threadlock_lock(&ctx_->ctrl_lock);
    threadlock_lock(&ctx_->pool_lock);
    if (ctx_->stop) {
        threadlock_unlock(&ctx_->pool_lock);
        threadlock_unlock(&ctx_->ctrl_lock);
        return;
    }
    while (!deque_empty(&ctx_->queue) || ctx_->active_thrd_count > 0) {
        threadlock_wait(&ctx_->pool_lock, -1);
    }
    threadlock_unlock(&ctx_->pool_lock);
    threadlock_unlock(&ctx_->ctrl_lock);
}

void threadpool_waitallthrd(THREADPOOL_CTX *ctx) {
    THREADPOOL_CTX_ *ctx_ = (THREADPOOL_CTX_*)ctx->ctx;
    int i = 0;
    threadlock_lock(&ctx_->ctrl_lock);
    threadlock_lock(&ctx_->pool_lock);
    if (ctx_->stop) {
        threadlock_unlock(&ctx_->pool_lock);
        threadlock_unlock(&ctx_->ctrl_lock);
        return;
    }
    ctx_->stop = 1;
    threadlock_broadcast(&ctx_->pool_lock);
    ctx_->pool_signaled = 1;
    threadlock_unlock(&ctx_->pool_lock);
    for (i = 0; i < ctx_->thrd_count; ++i) {
        if (ctx_->thread_handle[i]) {
#ifdef _WIN32
            WaitForSingleObject(ctx_->thread_handle[i], INFINITE);
            CloseHandle(ctx_->thread_handle[i]);
#else
            pthread_join(ctx_->thread_handle[i], NULL);
#endif
            ctx_->thread_handle[i] = 0;
        }
    }
    threadlock_unlock(&ctx_->ctrl_lock);
}


