#ifndef _THREAD_POOL_H_
#define _THREAD_POOL_H_

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <process.h>
#include <limits.h>
#else
#include <unistd.h>
#include <pthread.h>
#include <sys/time.h>
#endif
#include <stdio.h>

#if defined(__WATCOMC__)
#if defined(max)
#undef max
#endif
#if defined(min)
#undef min
#endif
#endif

typedef void (*thrd_callback)(void *param);

typedef struct {
    thrd_callback func;
    void *param;
} ThrdContext;

#ifdef __cplusplus
}
#endif

#if defined(__GNUC__) && __GNUC__ == 2 && __GNUC_MINOR__ < 8
#include <deque.h>
typedef deque<ThrdContext> ThreadQueue;
#elif defined(_MSC_VER) && _MSC_VER < 1100
#include <deque>
typedef deque<ThrdContext, allocator<ThrdContext> > ThreadQueue;
#else
#include <deque>
typedef std::deque<ThrdContext> ThreadQueue;
#endif

#if defined(WINVER) && WINVER >= 0x0600
typedef CONDITION_VARIABLE ConditionVariable;
#else
class ThreadLock;
class ConditionVariableLegacy
{
public:
    ConditionVariableLegacy();
    ~ConditionVariableLegacy();
    bool wait(ThreadLock &lock, int timeout_ms = -1);
    void signal();
    void broadcast();

private:
    HANDLE m_semphore;
    int m_wait_num;
};
typedef ConditionVariableLegacy ConditionVariable;
#endif

class ThreadLock
{
public:
    ThreadLock();
    ~ThreadLock();

    void lock();
    void unlock();

    bool wait(int timeout_ms = -1);
    void signal();
    void broadcast();

private:
#ifdef _WIN32
    CRITICAL_SECTION m_mutex;
    ConditionVariable m_cond;
#else
    pthread_mutex_t m_mutex;
    pthread_cond_t m_cond;
#endif
};

class LockScope
{
public:
    explicit LockScope(ThreadLock &lock) : m_lock(lock)
    {
        m_lock.lock();
    }
    ~LockScope()
    {
        m_lock.unlock();
    }
private:
    LockScope();
    LockScope(const LockScope&);
    LockScope& operator=(LockScope&);
    ThreadLock &m_lock;
};

class ThreadPool
{
public:
    ThreadPool(int max_thrd_num = 0);
    ~ThreadPool();

    bool init();
    void add_task(thrd_callback func, void *param);
    void wait_all_task();
    void wait_all_thrd();
    static int get_cpu_num();

private:
    static void thread_instance(void *param);
    ThreadQueue m_queue;
    ThrdContext m_thrd_context;
    ThreadLock m_pool_lock;
    ThreadLock m_ctrl_lock;
    bool m_pool_signaled;
    bool m_stop;
    int m_thrd_num;
    int m_active_thrd_num;
#ifdef _WIN32
    HANDLE *m_thread_handle;
    static unsigned int WINAPI _threadstart(void *param);
#else
    pthread_t *m_thread_handle;
    static void* _threadstart(void *param);
#endif
};

#endif
