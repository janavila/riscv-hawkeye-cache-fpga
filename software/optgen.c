#include "optgen.h"

void optgen_init(OPTgen *opt, uint64_t size)
{
    opt->num_cache = 0;
    opt->access = 0;
    opt->cache_size = size;

    for (int i = 0; i < OPTGEN_SIZE; i++)
    {
        opt->liveness_intervals[i] = 0;
    }
}

uint64_t optgen_get_hits(OPTgen *opt)
{
    return opt->num_cache;
}

void optgen_set_access(OPTgen *opt, uint64_t val)
{
    opt->access++;
    opt->liveness_intervals[val] = 0;
}

void optgen_set_prefetch(OPTgen *opt, uint64_t val)
{
    opt->liveness_intervals[val] = 0;
}

bool optgen_is_cache(OPTgen *opt, uint64_t val, uint64_t endVal)
{
    bool cache = true;
    unsigned int count = (unsigned int)endVal;

    while (count != val)
    {
        if (opt->liveness_intervals[count] >= opt->cache_size)
        {
            cache = false;
            break;
        }

        count = (count + 1) % OPTGEN_SIZE;
    }

    if (cache)
    {
        count = (unsigned int)endVal;

        while (count != val)
        {
            opt->liveness_intervals[count]++;
            count = (count + 1) % OPTGEN_SIZE;
        }

        opt->num_cache++;
    }

    return cache;
}