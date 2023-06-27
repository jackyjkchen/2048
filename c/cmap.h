/*************************************************************************
 * Copyright (c) 2020 Wirtos
 *
 * This library is free software; you can redistribute it and/or modify it
 * under the terms of the MIT license. See LICENSE for details.
 */

#ifndef CMAP_H
#define CMAP_H

#include <stddef.h>             /* size_t, NULL */

#define MAP_VER_MAJOR 2
#define MAP_VER_MINOR 5
#define MAP_VER_PATCH 0

typedef size_t (*MapHashFunction)(const void *key, size_t memsize);
typedef int (*MapCmpFunction)(const void *a, const void *b, size_t memsize);

struct map_node_t;

typedef struct {
    MapHashFunction hash_func;
    MapCmpFunction cmp_func;
    size_t nbuckets, nnodes;
    struct map_node_t **buckets;
} map_base_t;

typedef struct {
    size_t bucketidx;
    struct map_node_t *node;
} map_iter_t;

#define map_pair_t(KT, VT) \
    struct {               \
        KT k;              \
        VT v;              \
    }

#define map_t(KT, VT)                     \
    struct {                              \
        map_base_t base;                  \
        KT tmpkey;                        \
        VT tmpval;                        \
    }

#define map_init(m, key_cmp_func, key_hash_func)                                        \
    (void)(                                                                             \
        (m)->base.nbuckets = 0,                                                         \
        (m)->base.nnodes = 0,                                                           \
        (m)->base.buckets = NULL,                                                       \
        (m)->base.cmp_func = (key_cmp_func != NULL) ? key_cmp_func : map_generic_cmp,   \
        (m)->base.hash_func = (key_hash_func != NULL) ? key_hash_func : map_generic_hash\
    )

#define map_stdinit(m) map_init(m, NULL, NULL)

#define map_delete(m)\
  (map_delete_(&(m)->base), map_init(m, (m)->base.cmp_func, (m)->base.hash_func))

#define map_get(m, key) \
    ((m)->tmpkey = key, \
     map_get_(&(m)->base, &(m)->tmpkey, sizeof((m)->tmpkey)))

#define map_set(m, key, value)                                     \
    (                                                              \
        (m)->tmpval = (value), (m)->tmpkey = (key),                \
        map_set_(&(m)->base,                                       \
                  &(m)->tmpkey, sizeof((m)->tmpkey),               \
                  map_boffset_(&(m)->tmpkey, &(m)->base.buckets), \
                  &(m)->tmpval, sizeof((m)->tmpval),               \
                  map_boffset_(&(m)->tmpval, &(m)->base.buckets)) \
    )

#define map_remove(m, key) \
    ((m)->tmpkey = (key),  \
     map_remove_(&(m)->base, &(m)->tmpkey, sizeof((m)->tmpkey)))

#define map_iter(m) \
    map_iter_()

#define map_equal(m1, m2, val_cmp_func)              \
    (                                                \
     map_sametype_(&(m1)->tmpkey, &(m2)->tmpkey),    \
     map_sametype_(&(m1)->tmpval, &(m2)->tmpval),    \
     map_equal_(&(m1)->base, &(m2)->base,            \
        sizeof((m2)->tmpkey), sizeof((m2)->tmpval),  \
        (val_cmp_func) )                             \
    )

#define map_from_pairs(m, count, pairs)                                                \
    (                                                                                  \
        ((count) > 0)                                                                  \
         ? (                                                                           \
             map_sametype_(&(m)->tmpkey, &(pairs)->k),                                 \
             map_sametype_(&(m)->tmpval, &(pairs)->v),                                 \
             map_from_pairs_(&(m)->base,                                               \
                             (count),                                                  \
                             sizeof(*pairs),                                           \
                             &(pairs)->k,                                              \
                             sizeof((m)->tmpkey),                                      \
                             map_boffset_(&(m)->tmpkey, &(m)->base.buckets),           \
                             &(pairs)->v,                                              \
                             sizeof((m)->tmpval),                                      \
                             map_boffset_(&(m)->tmpval, &(m)->base.buckets) )          \
           )                                                                           \
         : 1                                                                           \
    )

/* copy from m2 into m1 */
#define map_copy(m1, m2)                                             \
    (                                                                \
        map_sametype_(&(m1)->tmpkey, &(m2)->tmpkey),                 \
        map_sametype_(&(m1)->tmpval, &(m2)->tmpval),                 \
        map_copy_(&(m1)->base, &(m2)->base,                          \
                 sizeof((m1)->tmpkey),                               \
                  map_boffset_(&(m1)->tmpkey, &(m1)->base.buckets),  \
                  sizeof((m1)->tmpval),                              \
                  map_boffset_(&(m2)->tmpval, &(m2)->base.buckets))  \
    )

size_t map_generic_hash(const void *mem, size_t memsize);

int map_generic_cmp(const void *a, const void *b, size_t memsize);

/* "private" functions */
void map_delete_(map_base_t *);

void *map_get_(map_base_t *, const void *, size_t);

int map_set_(map_base_t *, const void *, size_t, size_t, const void *, size_t, size_t);

void map_remove_(map_base_t *, const void *, size_t);

map_iter_t map_iter_(void);

int map_equal_(map_base_t *, map_base_t *, size_t, size_t, MapCmpFunction);

int map_from_pairs_(map_base_t *, size_t, size_t, const void *, size_t, size_t, const void *, size_t, size_t);

int map_copy_(map_base_t *, map_base_t *, size_t, size_t, size_t, size_t);

#define map_boffset_(a, b) ((const char *)(a) - (const char *)(b))

#define map_sametype_(a, b) ((void)((1) ? (a) : (b)))


/*typedef map_t(void *) map_void_t;
typedef map_t(char *) map_str_t;
typedef map_t(int) map_int_t;
typedef map_t(char) map_char_t;
typedef map_t(float) map_float_t;
typedef map_t(double) map_double_t;*/

#endif /* CMAP_H */
