#include "thread_pool.h"

#if defined(__MINGW64__) || defined(__MINGW32__)
#undef __USE_MINGW_ANSI_STDIO
#define __USE_MINGW_ANSI_STDIO 0
#endif
#include <stdio.h>
#include <stdlib.h>

#if defined(__GLIBC__) && __GLIBC__ >= 2 && __GLIBC_MINOR__ >= 2
#include <sys/sysinfo.h>
#define USE_SYSINFO 1
#endif

#if defined(WINVER) && WINVER < 0x0600
ConditionVariableLegacy::ConditionVariableLegacy():m_semphore(NULL), m_wait_num(0) {
    m_semphore = CreateSemaphore(NULL, 0, INT_MAX, NULL);
    if (!m_semphore) {
        fprintf(stderr, "CreateSemaphore failed.");
        fflush(stderr);
        abort();
    }
}

ConditionVariableLegacy::~ConditionVariableLegacy() {
    CloseHandle(m_semphore);
}

bool ConditionVariableLegacy::wait(ThreadLock &lock, int timeout_ms /* = -1 */ ) {
    DWORD timeout = INFINITE;

    if (timeout_ms >= 0) {
        timeout = (DWORD)timeout_ms;
    }
    m_wait_num++;
    lock.unlock();
    DWORD ret = WaitForSingleObject(m_semphore, timeout);

    lock.lock();
    m_wait_num--;
    return (ret == WAIT_OBJECT_0) ? true : false;
}

void ConditionVariableLegacy::signal() {
    if (m_wait_num > 0) {
        ReleaseSemaphore(m_semphore, 1, NULL);
    }
}

void ConditionVariableLegacy::broadcast() {
    if (m_wait_num > 0) {
        ReleaseSemaphore(m_semphore, m_wait_num, NULL);
    }
}
#endif

ThreadLock::ThreadLock() {
#ifdef _WIN32
    InitializeCriticalSection(&m_mutex);
#if defined(WINVER) && WINVER >= 0x0600
    InitializeConditionVariable(&m_cond);
#endif
#else
    pthread_mutex_init(&m_mutex, NULL);
    pthread_cond_init(&m_cond, NULL);
#endif
}

ThreadLock::~ThreadLock() {
#ifdef _WIN32
    DeleteCriticalSection(&m_mutex);
#else
    pthread_mutex_destroy(&m_mutex);
    pthread_cond_destroy(&m_cond);
#endif
}

void ThreadLock::lock() {
#ifdef _WIN32
    EnterCriticalSection(&m_mutex);
#else
    pthread_mutex_lock(&m_mutex);
#endif
}

void ThreadLock::unlock() {
#ifdef _WIN32
    LeaveCriticalSection(&m_mutex);
#else
    pthread_mutex_unlock(&m_mutex);
#endif
}

bool ThreadLock::wait(int timeout_ms /* = -1 */ ) {
#ifdef _WIN32
#if defined(WINVER) && WINVER >= 0x0600
    DWORD timeout = INFINITE;

    if (timeout_ms >= 0) {
        timeout = (DWORD)timeout_ms;
    }
    return (TRUE == SleepConditionVariableCS(&m_cond, &m_mutex, timeout));
#else
    return m_cond.wait(*this, timeout_ms);
#endif
#else
    int ret = 0;

    if (timeout_ms >= 0) {
        timeval now = { 0, 0 };
        gettimeofday(&now, NULL);
        const timespec timeout =
            { now.tv_sec + timeout_ms / 1000, now.tv_usec * 1000 + (timeout_ms % 1000) * 1000 * 1000 };
        ret = pthread_cond_timedwait(&m_cond, &m_mutex, &timeout);
    } else {
        ret = pthread_cond_wait(&m_cond, &m_mutex);
    }
    return ret;
#endif
}

void ThreadLock::signal() {
#ifdef _WIN32
#if defined(WINVER) && WINVER >= 0x0600
    WakeConditionVariable(&m_cond);
#else
    m_cond.signal();
#endif
#else
    pthread_cond_signal(&m_cond);
#endif
}

void ThreadLock::broadcast() {
#ifdef _WIN32
#if defined(WINVER) && WINVER >= 0x0600
    WakeAllConditionVariable(&m_cond);
#else
    m_cond.broadcast();
#endif
#else
    pthread_cond_broadcast(&m_cond);
#endif
}

#ifdef _WIN32
#if defined(WINVER) && WINVER >= 0x0501
static DWORD _count_set_bits(ULONG_PTR bitMask) {
    DWORD LSHIFT = sizeof(ULONG_PTR) * 8 - 1;
    DWORD bitSetCount = 0;
    ULONG_PTR bitTest = (ULONG_PTR)1 << LSHIFT;

    for (DWORD i = 0; i <= LSHIFT; ++i) {
        bitSetCount += ((bitMask & bitTest) ? 1 : 0);
        bitTest /= 2;
    }

    return bitSetCount;
}
#endif
#endif

THRD_INST ThreadPool::_threadstart(void *param) {
    ThrdContext *context = (ThrdContext *)param;

    context->func(context->param);
    return 0;
}

int ThreadPool::get_cpu_num() {
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

ThreadPool::ThreadPool(int max_thrd_num /* = 0 */ ):m_pool_signaled(false), m_stop(true), m_thrd_num(max_thrd_num), m_active_thrd_num(0), m_thread_handle(NULL) {
    m_thrd_context.func = ThreadPool::thread_instance;
    m_thrd_context.param = this;
}

ThreadPool::~ThreadPool() {
    wait_all_thrd();
    free(m_thread_handle);
}

bool ThreadPool::init() {
    bool ret = false, clear_thrd = false;

    do {
        LockScope(this->m_ctrl_lock);
        if (m_thrd_num == 0) {
            m_thrd_num = get_cpu_num();
        }
        if (m_thrd_num <= 0) {
            break;
        }
        if (!m_thread_handle) {
            m_thread_handle = (THRD_HANDLE *)malloc(m_thrd_num * sizeof(THRD_HANDLE));
        }
        if (!m_thread_handle) {
            break;
        }
        m_pool_lock.lock();
        if (!m_stop) {
            m_pool_lock.unlock();
            break;
        }
        m_stop = false;
        m_pool_lock.unlock();
        for (int i = 0; i < m_thrd_num; ++i) {
#ifdef _WIN32
            m_thread_handle[i] = (HANDLE)_beginthreadex(NULL, 0, ThreadPool::_threadstart, &m_thrd_context, 0, NULL);

            if (!m_thread_handle[i]) {
#else
            if (pthread_create(&m_thread_handle[i], NULL, ThreadPool::_threadstart, &m_thrd_context) != 0) {
#endif
                m_thread_handle[i] = 0;
                clear_thrd = true;
                break;
            }
        }
        ret = true;
    } while (false);
    if (!ret && clear_thrd)
        wait_all_thrd();
    return ret;
}

void ThreadPool::add_task(thrd_callback func, void *param) {
    LockScope(this->m_ctrl_lock);
    ThrdContext context;

    context.func = func;
    context.param = param;
    m_pool_lock.lock();
    m_queue.push_back(context);
    m_pool_lock.signal();
    m_pool_signaled = true;
    m_pool_lock.unlock();
}

void ThreadPool::wait_all_task() {
    LockScope(this->m_ctrl_lock);
    m_pool_lock.lock();
    if (m_stop) {
        m_pool_lock.unlock();
        return;
    }
    while (!m_queue.empty() || m_active_thrd_num > 0) {
        m_pool_lock.wait();
    }
    m_pool_lock.unlock();
}

void ThreadPool::wait_all_thrd() {
    LockScope(this->m_ctrl_lock);
    m_pool_lock.lock();
    if (m_stop) {
        m_pool_lock.unlock();
        return;
    }
    m_stop = true;
    m_pool_lock.broadcast();
    m_pool_signaled = true;
    m_pool_lock.unlock();
    for (int i = 0; i < m_thrd_num; ++i) {
        if (m_thread_handle[i]) {
#ifdef _WIN32
            WaitForSingleObject(m_thread_handle[i], INFINITE);
            CloseHandle(m_thread_handle[i]);
#else
            pthread_join(m_thread_handle[i], NULL);
#endif
            m_thread_handle[i] = 0;
        }
    }
}

void ThreadPool::thread_instance(void *param) {
    ThreadPool *pthis = (ThreadPool *)param;

    while (true) {
        pthis->m_pool_lock.lock();
        if (pthis->m_queue.empty()) {
            if (pthis->m_stop) {
                pthis->m_pool_lock.unlock();
                break;
            }
            pthis->m_pool_signaled = false;
            if (pthis->m_active_thrd_num == 0) {
                pthis->m_pool_lock.broadcast();
            }
            while (!pthis->m_pool_signaled) {
                pthis->m_pool_lock.wait();
            }
            pthis->m_pool_lock.unlock();
            continue;
        }
        ThrdContext context = pthis->m_queue.front();

        pthis->m_queue.pop_front();
        pthis->m_active_thrd_num++;
        pthis->m_pool_lock.unlock();
        context.func(context.param);
        pthis->m_pool_lock.lock();
        pthis->m_active_thrd_num--;
        pthis->m_pool_lock.unlock();
    }
}
