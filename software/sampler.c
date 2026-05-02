#include "sampler.h"

void sampler_init(SamplerSet sampler_sets[SAMPLER_SETS])
{
    for (int i = 0; i < SAMPLER_SETS; i++)
    {
        for (int j = 0; j < SAMPLER_HIST; j++)
        {
            sampler_sets[i].entries[j].valid = 0;
            sampler_sets[i].entries[j].signature = 0;
            sampler_sets[i].entries[j].pc = 0;
            sampler_sets[i].entries[j].previous_time = 0;
            sampler_sets[i].entries[j].lru = 0;
            sampler_sets[i].entries[j].prefetching = 0;
        }
    }
}

int sampler_find(SamplerSet *set, uint64_t signature)
{
    for (int i = 0; i < SAMPLER_HIST; i++)
    {
        if (set->entries[i].valid && set->entries[i].signature == signature)
        {
            return i;
        }
    }

    return -1;
}

int sampler_find_lru_victim(SamplerSet *set)
{
    int victim = -1;
    uint32_t maior_lru = 0;

    for (int i = 0; i < SAMPLER_HIST; i++)
    {
        if (!set->entries[i].valid)
        {
            return i;
        }

        if (victim == -1 || set->entries[i].lru > maior_lru)
        {
            maior_lru = set->entries[i].lru;
            victim = i;
        }
    }

    return victim;
}

void sampler_age_entries(SamplerSet *set, uint32_t current_lru)
{
    for (int i = 0; i < SAMPLER_HIST; i++)
    {
        if (set->entries[i].valid && set->entries[i].lru < current_lru)
        {
            set->entries[i].lru++;
        }
    }
}

int sampler_allocate_or_replace(SamplerSet *set, uint64_t signature)
{
    int pos = sampler_find(set, signature);

    if (pos != -1)
    {
        return pos;
    }

    pos = sampler_find_lru_victim(set);
    return pos;
}