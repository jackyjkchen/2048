#ifndef QUEUE_H
#define QUEUE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    void *buf;
    size_t nnode;
    size_t nsize;
    size_t headidx;
    size_t tailidx;
} deque_base_t;

#define deque_t(ET)        \
    struct {               \
        deque_base_t base; \
        ET tmp;            \
    }

#define deque_init(ctx) deque_init_(&(ctx)->base, sizeof((ctx)->tmp))

#define deque_delete(ctx) deque_delete_(&(ctx)->base)

#define deque_pop_front(ctx) deque_pop_front_(&(ctx)->base, sizeof((ctx)->tmp))

#define deque_pop_back(ctx) deque_pop_back_(&(ctx)->base, sizeof((ctx)->tmp))

#define deque_push_front(ctx, node) deque_push_front_(&(ctx)->base, &node, sizeof((ctx)->tmp))

#define deque_push_back(ctx, node) deque_push_back_(&(ctx)->base, &node, sizeof((ctx)->tmp))

#define deque_empty(ctx) ((ctx)->base.nnode == 0)

#define deque_nodes(ctx) ((ctx)->base.nnode)

#define deque_size(ctx) ((ctx)->base.nsize)

#define deque_shrink(ctx) deque_shrink_(&(ctx)->base, sizeof((ctx)->tmp))

/* private function */
extern int deque_init_(deque_base_t *base, size_t node_size);

extern void deque_delete_(deque_base_t *base);

extern void* deque_pop_front_(deque_base_t *base, size_t node_size);

extern void* deque_pop_back_(deque_base_t *base, size_t node_size);

extern int deque_push_front_(deque_base_t *base, void *node, size_t node_size);

extern int deque_push_back_(deque_base_t *base, void *node, size_t node_size);

extern size_t deque_shrink_(deque_base_t *base, size_t node_size);

#ifdef __cplusplus
}
#endif

#endif
