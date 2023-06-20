#include "deque.h"

#include <stdlib.h>
#include <string.h>

int deque_init_(deque_base_t *base, size_t node_size, size_t queue_size) {
    if(!base->buf) {
        base->buf = malloc(node_size * queue_size);
        if(!base->buf) {
            return 0;
        }
        memset(base->buf, 0x00, node_size * queue_size);
        base->nsize = queue_size;
        base->nnode = 0;
        base->headidx = 0;
        base->tailidx = 0;
    } else {
        return 0;
    }
    return 1;
}

void deque_delete_(deque_base_t *base) {
    free(base->buf);
    base->buf = NULL;
    base->nnode = 0;
    base->nsize = 0;
    base->headidx = 0;
    base->tailidx = 0;
}

void* deque_pop_front_(deque_base_t *base, size_t node_size) {
    void *ret = NULL;
    if (base->nnode == 0) {
        return ret;
    }
    ret = (unsigned char *)base->buf + base->headidx * node_size;
    base->headidx += 1;
    if (base->headidx == base->nsize) {
        base->headidx = 0;
    }
    base->nnode--;
    return ret;
}

void* deque_pop_back_(deque_base_t *base, size_t node_size) {
    void *ret = NULL;
    if (base->nnode == 0) {
        return ret;
    }
    if (base->tailidx == 0) {
        base->tailidx = base->nsize - 1;
    } else {
        base->tailidx -= 1;
    }
    ret = (unsigned char *)base->buf + base->tailidx * node_size;
    base->nnode--;
    return ret;
}

int deque_push_front_(deque_base_t *base, void *node, size_t node_size) {
    if (base->nnode >= base->nsize) {
        return 0;
    }
    if (base->headidx == 0) {
        base->headidx = base->nsize - 1;
    } else {
        base->headidx -= 1;
    }
    memcpy((unsigned char *)base->buf + base->headidx * node_size, node, node_size);
    base->nnode++;
    return 1;
}

int deque_push_back_(deque_base_t *base, void *node, size_t node_size) {
    if (base->nnode >= base->nsize) {
        return 0;
    }
    memcpy((unsigned char *)base->buf + base->tailidx * node_size, node, node_size);
    base->tailidx += 1;
    if (base->tailidx == base->nsize) {
        base->tailidx = 0;
    }
    base->nnode++;
    return 1;
}

