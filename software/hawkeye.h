#ifndef HAWKEYE_H
#define HAWKEYE_H

#include <stdint.h>

#define HAWKEYE_PCMAP_SIZE 2048
#define HAWKEYE_MAX_PCMAP 31

typedef struct
{
    unsigned char contador[HAWKEYE_PCMAP_SIZE];
} HawkeyePredictor;

uint64_t hawkeye_crc(uint64_t address);

void hawkeye_init(HawkeyePredictor *pred);
int hawkeye_get_prediction(HawkeyePredictor *pred, uint64_t pc);
void hawkeye_increase(HawkeyePredictor *pred, uint64_t pc);
void hawkeye_decrease(HawkeyePredictor *pred, uint64_t pc);

#endif