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
#include <assert.h>
#else
#include <unistd.h>
#include <pthread.h>
#include <sys/time.h>
#endif

#ifdef _M_I86
typedef long int32;
#else
typedef int int32;
#endif

#ifdef __cplusplus
}
#endif

#if defined(__WATCOMC__)
#if defined(max)
#undef max
#endif
#if defined(min)
#undef min
#endif
#endif

#include <deque>

typedef void (*thrd_callback)(void *param);

struct ThrdCallback {
    thrd_callback func;
    void *param;
};

#if defined(WINVER) && WINVER < 0x0600
template<class LOCK>
class ConditionVariable
{
public:
    ConditionVariable(LOCK &lock) : m_lock(lock), m_semphore(NULL), m_wait_num(0)
    {
        assert(m_semphore = CreateSemaphore(NULL, 0, INT_MAX, NULL));
    }

    ~ConditionVariable()
    {
        CloseHandle(m_semphore);
    }

    bool wait(int32 timeout_ms = -1)
    {
        DWORD timeout = INFINITE;
        if (timeout_ms >= 0) {
            timeout = (DWORD)timeout_ms;
        }
        m_wait_num++;
        m_lock.unlock();
        DWORD ret = WaitForSingleObject(m_semphore, timeout);
        m_lock.lock();
        m_wait_num--;
        return (ret == WAIT_OBJECT_0) ? true : false;
    }

    void signal()
    {
        if (m_wait_num > 0) {
            ReleaseSemaphore(m_semphore, 1, NULL);
        }
    }

    void broadcast()
    {
        if (m_wait_num > 0) {
            ReleaseSemaphore(m_semphore, m_wait_num, NULL);
        }
    }

private:
    LOCK &m_lock;
    HANDLE m_semphore;
    int32 m_wait_num;
};
#endif

class ThreadLock
{
public:
    ThreadLock();
    ~ThreadLock();

    void lock();
    void unlock();

    bool wait(int32 timeout_ms = -1);
    void signal();
    void broadcast();

private:
#ifdef _WIN32
    CRITICAL_SECTION m_mutex;
#if defined(WINVER) && WINVER >= 0x0600
    CONDITION_VARIABLE m_cond;
#else
    ConditionVariable<ThreadLock> m_cond;
#endif
#else
    pthread_mutex_t m_mutex;
    pthread_cond_t m_cond;
#endif
};

template<class LOCK>
class LockScope
{
public:
    explicit LockScope(LOCK &lock) : m_lock(lock)
    {
        m_lock.lock();
    }
    ~LockScope()
    {
        m_lock.unlock();
    }
private:
    LockScope(const LockScope&);
    LockScope& operator=(LockScope&);
    LOCK &m_lock;
};

class ThreadPool
{
public:
    ThreadPool(int32 max_thrd_num = 0);
    ~ThreadPool();

    bool init();
    void add_task(thrd_callback func, void *param);
    void wait_all_task();
    void wait_all_thrd();
    int32 get_max_thrd_num();
    static int32 get_cpu_num();

#if defined(_MSC_VER) && _MSC_VER < 1100
    deque<ThrdCallback, allocator<ThrdCallback> > m_queue;
#else
    std::deque<ThrdCallback> m_queue;
#endif
private:
    static void thread_instance(void *param);
    ThrdCallback m_thrd;
    ThreadLock m_pool_lock;
    ThreadLock m_ctrl_lock;
    volatile bool m_pool_signaled;
    volatile bool m_stop;
    volatile int32 m_max_thrd_num;
    volatile int32 m_thrd_num;
    volatile int32 m_active_thrd_num;
#ifdef _WIN32
    HANDLE *m_thread_handle;
    static unsigned int WINAPI _threadstart(void *param);
#if defined(WINVER) && WINVER >= 0x0501
    static DWORD _count_set_bits(ULONG_PTR bitMask);
#endif
#else
    pthread_t *m_thread_handle;
    static void* _threadstart(void *param);
#endif
};

#endif
