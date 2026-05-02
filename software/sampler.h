#ifndef SAMPLER_H
#define SAMPLER_H

#include <stdint.h>
#include <stdbool.h>

#define SAMPLER_HIST 8
#define SAMPLER_ENTRIES 2800
#define SAMPLER_SETS (SAMPLER_ENTRIES / SAMPLER_HIST)

typedef struct
{
    int valid;
    uint64_t signature;
    uint64_t pc;
    uint32_t previous_time;
    uint32_t lru;
    int prefetching;
} SamplerEntry;

typedef struct
{
    SamplerEntry entries[SAMPLER_HIST];
} SamplerSet;

void sampler_init(SamplerSet sampler_sets[SAMPLER_SETS]);

int sampler_find(SamplerSet *set, uint64_t signature);
int sampler_find_lru_victim(SamplerSet *set);
void sampler_age_entries(SamplerSet *set, uint32_t current_lru);
int sampler_allocate_or_replace(SamplerSet *set, uint64_t signature);

#endif