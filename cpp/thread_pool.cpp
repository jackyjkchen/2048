#include <stdlib.h>
#include "thread_pool.h"

ThreadLock::ThreadLock()
#if defined(WINVER) && WINVER < 0x0600
    : m_cond(*this)
#endif
{
#ifdef _WIN32
    InitializeCriticalSection(&m_mutex);
#if WINVER > 0x0600
    InitializeConditionVariable(&m_cond);
#endif
#else
    pthread_mutex_init(&m_mutex, NULL);
    pthread_cond_init(&m_cond, NULL);
#endif
}

ThreadLock::~ThreadLock()
{
#ifdef _WIN32
    DeleteCriticalSection(&m_mutex);
#else
    pthread_mutex_destroy(&m_mutex);
    pthread_cond_destroy(&m_cond);
#endif
}

void ThreadLock::lock()
{
#ifdef _WIN32
    EnterCriticalSection(&m_mutex);
#else
    pthread_mutex_lock(&m_mutex);
#endif
}

void ThreadLock::unlock()
{
#ifdef _WIN32
    LeaveCriticalSection(&m_mutex);
#else
    pthread_mutex_unlock(&m_mutex);
#endif
}

bool ThreadLock::wait(int32 timeout_ms/* = -1*/)
{
#ifdef _WIN32
#if WINVER >= 0x0600
    DWORD timeout = INFINITE;
    if (timeout_ms >= 0) {
        timeout = (DWORD)timeout_ms;
    }
    return (TRUE == SleepConditionVariableCS(&m_cond, &m_mutex, timeout));
#else
    return m_cond.wait(timeout_ms);
#endif
#else
    int ret = 0;
    if (timeout_ms >= 0) {
        timeval now = { 0 };
        gettimeofday(&now, NULL);
        const timespec timeout = {now.tv_sec + timeout_ms / 1000, now.tv_usec * 1000 + (timeout_ms % 1000) * 1000 * 1000};
        ret = pthread_cond_timedwait(&m_cond, &m_mutex, &timeout);
    } else {
        ret = pthread_cond_wait(&m_cond, &m_mutex);
    }
    return ret;
#endif
}

void ThreadLock::signal()
{
#ifdef _WIN32
#if WINVER >= 0x0600
    WakeConditionVariable(&m_cond);
#else
    m_cond.signal();
#endif
#else
    pthread_cond_signal(&m_cond);
#endif
}

void ThreadLock::broadcast()
{
#ifdef _WIN32
#if WINVER >= 0x0600
    WakeAllConditionVariable(&m_cond);
#else
    m_cond.broadcast();
#endif
#else
    pthread_cond_broadcast(&m_cond);
#endif
}

#ifdef _WIN32
#if defined(WINVER) && WINVER >= 0x0502
DWORD ThreadPool::_count_set_bits(ULONG_PTR bitMask)
{
    DWORD LSHIFT = sizeof(ULONG_PTR) * 8 - 1;
    DWORD bitSetCount = 0;
    ULONG_PTR bitTest = (ULONG_PTR)1 << LSHIFT;
    DWORD i;

    for (i = 0; i <= LSHIFT; ++i) {
        bitSetCount += ((bitMask & bitTest) ? 1 : 0);
        bitTest /= 2;
    }

    return bitSetCount;
}
#endif

unsigned int WINAPI ThreadPool::_threadstart(void *param)
{
    ThrdCallback *thrd = (ThrdCallback *)param;
    thrd->func(thrd->param);
    return 0;
}
#else
void* ThreadPool::_threadstart(void *param)
{
    ThrdCallback *thrd = (ThrdCallback *)param;
    thrd->func(thrd->param);
    return NULL;
}
#endif

int32 ThreadPool::get_cpu_num()
{
    int32 cpu_num = 0;
#ifdef _WIN32
#if defined(WINVER) && WINVER >= 0x0502
    DWORD length = 0;
    PSYSTEM_LOGICAL_PROCESSOR_INFORMATION buf = NULL, ptr = NULL;
    BOOL ret = FALSE;
    while ((ret = GetLogicalProcessorInformation(buf, &length)) == FALSE) {
        if (GetLastError() == ERROR_INSUFFICIENT_BUFFER) {
            buf = (PSYSTEM_LOGICAL_PROCESSOR_INFORMATION)malloc(length);
            if (!buf) {
                return -1;
            }
        }
        else {
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
#else
    cpu_num = (int32)sysconf(_SC_NPROCESSORS_CONF);
#endif
    return cpu_num;
}

ThreadPool::ThreadPool(int32 max_thrd_num/* = 0*/) : m_pool_signaled(false), m_stop(false), m_max_thrd_num(max_thrd_num), m_thrd_num(0), m_active_thrd_num(0), m_thread_handle(NULL)
{
    m_thrd.func = ThreadPool::thread_instance;
    m_thrd.param = this;
}

ThreadPool::~ThreadPool()
{
    wait_all_thrd();
    free(m_thread_handle);
}

bool ThreadPool::init()
{
    m_ctrl_lock.lock();
    if (m_max_thrd_num == 0) {
        m_max_thrd_num = get_cpu_num();
    }
    if (m_max_thrd_num <= 0 || m_thrd_num != 0) {
        m_ctrl_lock.unlock();
        return false;
    }
    if (!m_thread_handle) {
#ifdef _WIN32
        m_thread_handle = (HANDLE *)malloc(m_max_thrd_num * sizeof(HANDLE));
#else
        m_thread_handle = (pthread_t *)malloc(m_max_thrd_num * sizeof(pthread_t));
#endif
    }
    if (!m_thread_handle) {
        m_ctrl_lock.unlock(); //LCOV_EXCL_LINE
        return false;         //LCOV_EXCL_LINE
    }
    for (int32 i= 0; i<m_max_thrd_num; ++i) {
#ifdef _WIN32
        if (!(m_thread_handle[i] = (HANDLE)_beginthreadex(NULL, 0, ThreadPool::_threadstart, &m_thrd, 0, NULL))) {
#else
        if (pthread_create(&m_thread_handle[i], NULL, ThreadPool::_threadstart, &m_thrd) != 0) {
#endif
            m_ctrl_lock.unlock(); //LCOV_EXCL_LINE
            wait_all_thrd();      //LCOV_EXCL_LINE
            return false;         //LCOV_EXCL_LINE
        }
    }
    m_thrd_num = m_max_thrd_num;
    m_ctrl_lock.unlock();
    return true;
}

void ThreadPool::add_task(thrd_callback func, void *param)
{
    LockScope<ThreadLock>(this->m_ctrl_lock);
    if (m_thrd_num == 0) {
        return;
    }
    ThrdCallback clbk;
    clbk.func = func;
    clbk.param = param;
    m_pool_lock.lock();
    m_queue.push_back(clbk);
    m_pool_lock.broadcast();
    m_pool_signaled = true;
    m_pool_lock.unlock();
}

void ThreadPool::wait_all_task()
{
    LockScope<ThreadLock>(this->m_ctrl_lock);
    if (m_thrd_num == 0) {
        return;
    }
    while (true) {
        m_pool_lock.lock();
        if (m_queue.empty() && m_active_thrd_num == 0) {
            m_pool_signaled = false;
            m_pool_lock.unlock();
            return;
        }
        m_pool_lock.wait();
        m_pool_lock.unlock();
    }
}

void ThreadPool::wait_all_thrd()
{
    LockScope<ThreadLock>(this->m_ctrl_lock);
    if (m_thrd_num == 0) {
        return;
    }
    m_pool_lock.lock();
    m_stop = true;
    m_pool_lock.broadcast();
    m_pool_signaled = true;
    m_pool_lock.unlock();
    for (int32 i = 0; i < m_max_thrd_num; ++i) {
        if (m_thread_handle[i] > 0) {
#ifdef _WIN32
            WaitForSingleObject(m_thread_handle[i], INFINITE);
            CloseHandle(m_thread_handle[i]);
#else
            pthread_join(m_thread_handle[i], NULL);
#endif
            m_thread_handle[i] = 0;
        }
    }
    m_thrd_num = 0;
}

int ThreadPool::get_max_thrd_num()
{
    LockScope<ThreadLock>(this->m_ctrl_lock);
    return m_max_thrd_num;
}

void ThreadPool::thread_instance(void *param) {
    ThreadPool *pthis = (ThreadPool *)param;
    while (true) {
        pthis->m_pool_lock.lock();
        if (pthis->m_queue.empty()) {
            pthis->m_pool_signaled = false;
            if (pthis->m_stop) {
                pthis->m_pool_lock.unlock();
                break;
            }
            if (pthis->m_active_thrd_num == 0) {
                pthis->m_pool_lock.broadcast();
                pthis->m_pool_signaled = true;
            }
            while (!pthis->m_pool_signaled) {
                pthis->m_pool_lock.wait();
            }
            pthis->m_pool_lock.unlock();
            continue;
        }
        ThrdCallback clbk = pthis->m_queue.front();
        pthis->m_queue.pop_front();
        pthis->m_active_thrd_num++;
        pthis->m_pool_lock.unlock();
        clbk.func(clbk.param);
        pthis->m_pool_lock.lock();
        pthis->m_active_thrd_num--;
        pthis->m_pool_lock.unlock();
    }
}

