#include "deque.h"

#define DEQUE_DEBUG 0

#if DEQUE_DEBUG
#include <stdio.h>
#endif
#include <stdlib.h>
#include <string.h>

#define DEFAULT_SIZE 16

int deque_init_(deque_base_t *base, size_t node_size) {
    if (!base->buf) {
        base->buf = malloc(node_size * DEFAULT_SIZE);
        if (!base->buf) {
            return 0;
        }
        memset(base->buf, 0x00, node_size * DEFAULT_SIZE);
        base->nsize = DEFAULT_SIZE;
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

void *deque_pop_front_(deque_base_t *base, size_t node_size) {
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

void *deque_pop_back_(deque_base_t *base, size_t node_size) {
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

static int deque_realloc_(deque_base_t *base, size_t node_size) {
    void *newbuf = realloc(base->buf, (base->nsize << 1) * node_size);

    if (!newbuf) {
        return 0;
    }
    base->buf = newbuf;
    memmove((unsigned char *)base->buf + base->nsize * node_size, base->buf, base->tailidx * node_size);
    base->tailidx += base->nsize;
    base->nsize <<= 1;
    return 1;
}

int deque_push_front_(deque_base_t *base, void *node, size_t node_size) {
    if (base->nnode >= base->nsize) {
        if (!deque_realloc_(base, node_size)) {
            return 0;
        }
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
        if (!deque_realloc_(base, node_size)) {
            return 0;
        }
    }
    memcpy((unsigned char *)base->buf + base->tailidx * node_size, node, node_size);
    base->tailidx += 1;
    if (base->tailidx == base->nsize) {
        base->tailidx = 0;
    }
    base->nnode++;
    return 1;
}

#define _max(a,b) ( ((a)>(b)) ? (a):(b) )

size_t deque_shrink_(deque_base_t *base, size_t node_size) {
    void *newbuf = NULL;
    size_t newsize = base->nsize, nodes = 0;

    if ((base->nnode << 1) > base->nsize || base->nsize == DEFAULT_SIZE) {
        return base->nsize;
    }

    while ((newsize >> 1) >= _max(base->nnode, DEFAULT_SIZE)) {
        newsize >>= 1;
    }

    newbuf = malloc(newsize * node_size);
    if (!newbuf) {
        return base->nsize;
    }
    memset(newbuf, 0x00, newsize * node_size);

    nodes = (base->headidx < base->tailidx) ? base->nnode : ((base->nnode != 0) ? (base->nsize - base->headidx) : 0);
    if (nodes > 0) {
        memcpy((unsigned char *)newbuf, (unsigned char *)base->buf + base->headidx * node_size, nodes * node_size);
    }
    if (base->nnode - nodes > 0) {
        memcpy((unsigned char *)newbuf + nodes * node_size, (unsigned char *)base->buf, base->tailidx * node_size);
    }
    free(base->buf);
    base->buf = newbuf;
    base->nsize = newsize;
    base->headidx = 0;
    base->tailidx = base->nnode;
    if (base->tailidx == base->nsize) {
        base->tailidx = 0;
    }
    return base->nsize;
}
