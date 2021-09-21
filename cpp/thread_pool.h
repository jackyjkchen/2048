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
} ThrdCallback;

#ifdef __cplusplus
}
#endif

#if defined(__GNUC__) && __GNUC__ == 2 && __GNUC_MINOR__ < 8
#include <deque.h>
typedef deque<ThrdCallback> ThreadQueue;
#elif defined(_MSC_VER) && _MSC_VER < 1100
#include <deque>
typedef deque<ThrdCallback, allocator<ThrdCallback> > ThreadQueue;
#else
#include <deque>
typedef std::deque<ThrdCallback> ThreadQueue;
#endif

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

    bool wait(int timeout_ms = -1)
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
    int m_wait_num;
};
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
    int get_max_thrd_num();
    static int get_cpu_num();

private:
    static void thread_instance(void *param);
    ThreadQueue m_queue;
    ThrdCallback m_thrd;
    ThreadLock m_pool_lock;
    ThreadLock m_ctrl_lock;
    volatile bool m_pool_signaled;
    volatile bool m_stop;
    volatile int m_max_thrd_num;
    volatile int m_thrd_num;
    volatile int m_active_thrd_num;
#ifdef _WIN32
    HANDLE *m_thread_handle;
    static unsigned int WINAPI _threadstart(void *param);
#else
    pthread_t *m_thread_handle;
    static void* _threadstart(void *param);
#endif
};

#endif
