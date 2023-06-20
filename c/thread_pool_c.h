#ifndef _THREAD_POOL_H_
#define _THREAD_POOL_H_

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    void *ctx;
} THREADLOCK_CTX, THREADPOOL_CTX;

typedef void (*thrd_callback)(void *param);

extern int threadlock_init(THREADLOCK_CTX *ctx);

extern void threadlock_uninit(THREADLOCK_CTX *ctx);

extern void threadlock_lock(THREADLOCK_CTX *ctx);

extern void threadlock_unlock(THREADLOCK_CTX *ctx);

extern int threadlock_wait(THREADLOCK_CTX *ctx, int timeout_ms);

extern void threadlock_signal(THREADLOCK_CTX *ctx);

extern void threadlock_broadcast(THREADLOCK_CTX *ctx);

extern int threadpool_startup(THREADPOOL_CTX *ctx, int max_thrd_num);

extern void threadpool_cleanup(THREADPOOL_CTX *ctx);

extern int threadpool_addtask(THREADPOOL_CTX *ctx, thrd_callback func, void *param);

extern void threadpool_waitalltask(THREADPOOL_CTX *ctx);

extern void threadpool_waitallthrd(THREADPOOL_CTX *ctx);

extern int threadpool_thrdcount(THREADPOOL_CTX *ctx);

extern int threadpool_cpucount(void);

#ifdef __cplusplus
}
#endif

#endif
