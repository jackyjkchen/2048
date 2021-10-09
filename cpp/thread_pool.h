#ifndef _THREAD_POOL_H_
#define _THREAD_POOL_H_

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__linux__) || defined(linux) || defined(__unix__) || defined(unix) || defined(__CYGWIN__) || defined(__MACH__)
#define UNIX_LIKE 1
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

#if defined(max)
#undef max
#endif
#if defined(min)
#undef min
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
#elif defined(_WIN32)
class ThreadLock;
class ConditionVariableLegacy {
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

class ThreadLock {
public:
    ThreadLock();
    ~ThreadLock();

    void lock();
    void unlock();

    bool wait(int timeout_ms = -1);
    void signal();
    void broadcast();

private:
    CriticalSection m_mutex;
    ConditionVariable m_cond;
};

class LockScope {
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

class ThreadPool {
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
    THRD_HANDLE *m_thread_handle;
    static THRD_INST _threadstart(void *param);
};

#endif
