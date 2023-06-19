/*************************************************************************
 * Copyright (c) 2020 Wirtos
 *
 * This library is free software; you can redistribute it and/or modify it
 * under the terms of the MIT license. See LICENSE for details.
 */

#include <stdlib.h>             /* malloc, realloc */
#include <string.h>             /* strcmp, memset, memcmp, memcpy */
#include "cmap.h"

typedef struct map_node_t map_node_t;

struct map_node_t {
    size_t hash;
    void *key;
    void *value;
    map_node_t *next;
};

/* djb2 hashing algorithm */
size_t map_generic_hash(const void *mem, size_t memsize) {
    /* 5381 and 33 - efficient magic numbers */
    const unsigned char *barr = mem;
    size_t hash = 5381;
    size_t i;

    for (i = 0; i < memsize; i++) {
        hash = ((hash << 5) + hash) ^ (barr[i]);
    }
    return hash;
}

int map_generic_cmp(const void *a, const void *b, size_t memsize) {
    return memcmp(a, b, memsize);
}

static map_node_t *map_newnode(const void *key, size_t ksize, size_t koffset, const void *value, size_t vsize,
                               size_t voffset, MapHashFunction hash_func) {
    map_node_t *node;

    node = (map_node_t *) malloc(sizeof(*node) + koffset + ksize + voffset + vsize);
    if (node == NULL) {
        return NULL;
    }
    node->key = (char *)(node + 1) + koffset;
    node->value = (char *)(node + 1) + voffset;
    memcpy(node->key, key, ksize);
    memcpy(node->value, value, vsize);
    node->hash = hash_func(key, ksize); /* Call map-specific hash function */
    node->next = NULL;
    return node;
}


size_t map_bucketidx(map_base_t *m, size_t hash) {
    /* If the implementation is changed to allow a non-power-of-2 bucket count,
     * the line below should be changed to use mod instead of AND */
    return hash & (m->nbuckets - 1);
}


static void map_addnode(map_base_t *m, map_node_t *node) {
    size_t n = map_bucketidx(m, node->hash);

    node->next = m->buckets[n];
    m->buckets[n] = node;
}


static int map_resize(map_base_t *m, size_t nbuckets) {
    map_node_t *nodes, *node, *next;
    map_node_t **buckets;
    size_t i;

    /* Chain all nodes together */
    nodes = NULL;
    i = m->nbuckets;
    while (i--) {
        node = (m->buckets)[i];
        while (node != NULL) {
            next = node->next;
            node->next = nodes;
            nodes = node;
            node = next;
        }
    }
    /* Reset buckets */
    buckets = (map_node_t **) realloc(m->buckets, sizeof(*m->buckets) * nbuckets);
    if (buckets != NULL) {
        m->buckets = buckets;
        m->nbuckets = nbuckets;
        /* todo: introduce a portable ifdef. NULL's bits aren't always all-zeros */
        memset(m->buckets, 0, sizeof(*m->buckets) * m->nbuckets);
        /* Re-add nodes to buckets */
        node = nodes;
        while (node != NULL) {
            next = node->next;
            map_addnode(m, node);
            node = next;
        }
    }
    /* Return error code if realloc() failed */
    return (buckets == NULL) ? 0 : 1;
}


static map_node_t **map_getref(map_base_t *m, const void *key, size_t ksize) {
    size_t hash = m->hash_func(key, ksize);
    map_node_t **next;

    if (m->nbuckets > 0) {
        next = &m->buckets[map_bucketidx(m, hash)];
        while (*next != NULL) {
            if ((*next)->hash == hash && m->cmp_func(key, (*next)->key, ksize) == 0) {
                return next;
            }
            next = &(*next)->next;
        }
    }
    return NULL;
}


void map_delete_(map_base_t *m) {
    map_node_t *next, *node;
    size_t i;

    i = m->nbuckets;
    while (i--) {
        node = m->buckets[i];
        while (node != NULL) {
            next = node->next;
            free(node);
            node = next;
        }
    }
    free(m->buckets);
}


void *map_get_(map_base_t *m, const void *key, size_t ksize) {
    map_node_t **next = map_getref(m, key, ksize);

    return next != NULL ? (*next)->value : NULL;
}


int map_set_(map_base_t *m, const void *key, size_t ksize, size_t koffset, const void *value, size_t vsize,
             size_t voffset) {
    size_t n;
    map_node_t **next, *node;

    /* Find & replace existing node */
    next = map_getref(m, key, ksize);
    if (next != NULL) {
        memcpy((*next)->value, value, vsize);
        return 1;
    }
    /* Add new node */
    node = map_newnode(key, ksize, koffset, value, vsize, voffset, m->hash_func);
    if (node == NULL) {
        return 0;
    }
    if (m->nnodes >= m->nbuckets) {
        n = (m->nbuckets > 0) ? (m->nbuckets * 2) : 1;
        if (!map_resize(m, n)) {
            free(node);
            return 0;
        }
    }
    map_addnode(m, node);
    m->nnodes++;
    return 1;
}


void map_remove_(map_base_t *m, const void *key, size_t ksize) {
    map_node_t *node;
    map_node_t **next = map_getref(m, key, ksize);

    if (next != NULL) {
        node = *next;
        *next = (*next)->next;
        free(node);
        m->nnodes--;
    }
}


map_iter_t map_iter_(void) {
    map_iter_t iter;

    iter.bucketidx = (size_t)-1;
    iter.node = NULL;
    return iter;
}


void *map_next_(map_base_t *m, map_iter_t *iter) {
    if (iter->node != NULL) {
        iter->node = iter->node->next;
        if (iter->node == NULL) {
            goto nextBucket;
        }
    } else {
      nextBucket:
        do {
            if (++iter->bucketidx >= m->nbuckets) {
                return NULL;
            }
            iter->node = m->buckets[iter->bucketidx];
        } while (iter->node == NULL);
    }
    return iter->node->key;
}


int map_equal_(map_base_t *m1, map_base_t *m2, size_t ksize, size_t vsize, MapCmpFunction val_cmp_func) {
    void *m1_key;
    map_iter_t m1_it = map_iter(m1);

    if (m1->nnodes != m2->nnodes) {
        return 0;
    }
    if (!val_cmp_func)
        val_cmp_func = map_generic_cmp;
    while ((m1_key = map_next_(m1, &m1_it)) != 0) {
        void *m2_val_ptr = map_get_(m2, m1_key, ksize);

        if (m2_val_ptr == NULL || val_cmp_func(map_get_(m1, m1_key, ksize), m2_val_ptr, vsize) != 0) {
            return 0;
        }
    }
    return 1;
}

int map_from_pairs_(map_base_t *m, size_t pcount, size_t psize,
                    const void *key, size_t ksize, size_t koffset, const void *val, size_t vsize, size_t voffset) {
    size_t i;

    for (i = 0; i < pcount; i++) {
        if (!map_set_(m, key, ksize, koffset, val, vsize, voffset)) {
            return 0;
        }
        key = (char *)key + psize;
        val = (char *)val + psize;
    }
    return 1;
}
int map_copy_(map_base_t *m1, map_base_t *m2, size_t ksize, size_t koffset, size_t vsize, size_t voffset) {
    map_node_t *next, *node;
    size_t i;

    if (m2->nbuckets > (m1->nbuckets - m1->nnodes) && !map_resize(m1, m2->nbuckets))
        return 0;

    i = m2->nbuckets;
    while (i--) {
        node = m2->buckets[i];
        while (node != NULL) {
            next = node->next;
            if (!map_set_(m1, node->key, ksize, koffset, node->value, vsize, voffset)) {
                return 0;
            }
            node = next;
        }
    }
    return 1;
}
