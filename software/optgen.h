#ifndef OPTGEN_H
#define OPTGEN_H

#include <stdint.h>
#include <stdbool.h>

#define OPTGEN_SIZE 128

typedef struct
{
    unsigned int liveness_intervals[OPTGEN_SIZE];
    uint64_t num_cache;
    uint64_t access;
    uint64_t cache_size;
} OPTgen;

void optgen_init(OPTgen *opt, uint64_t size);
uint64_t optgen_get_hits(OPTgen *opt);
void optgen_set_access(OPTgen *opt, uint64_t val);
void optgen_set_prefetch(OPTgen *opt, uint64_t val);
bool optgen_is_cache(OPTgen *opt, uint64_t val, uint64_t endVal);

#endif