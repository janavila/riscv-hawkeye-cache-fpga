#include "hawkeye.h"

uint64_t hawkeye_crc(uint64_t address)
{
    unsigned long long crcPolynomial = 3988292384ULL;
    unsigned long long result = address;

    for (unsigned int i = 0; i < 32; i++)
    {
        if ((result & 1ULL) == 1ULL)
            result = (result >> 1) ^ crcPolynomial;
        else
            result >>= 1;
    }

    return result;
}

void hawkeye_init(HawkeyePredictor *pred)
{
    for (int i = 0; i < HAWKEYE_PCMAP_SIZE; i++)
    {
        pred->contador[i] = (HAWKEYE_MAX_PCMAP + 1) / 2;
    }
}

int hawkeye_get_prediction(HawkeyePredictor *pred, uint64_t pc)
{
    uint64_t indice = hawkeye_crc(pc) % HAWKEYE_PCMAP_SIZE;

    if (pred->contador[indice] < ((HAWKEYE_MAX_PCMAP + 1) / 2))
        return 0; /* cache-averse */

    return 1; /* cache-friendly */
}

void hawkeye_increase(HawkeyePredictor *pred, uint64_t pc)
{
    uint64_t indice = hawkeye_crc(pc) % HAWKEYE_PCMAP_SIZE;

    if (pred->contador[indice] < HAWKEYE_MAX_PCMAP)
    {
        pred->contador[indice]++;
    }
}

void hawkeye_decrease(HawkeyePredictor *pred, uint64_t pc)
{
    uint64_t indice = hawkeye_crc(pc) % HAWKEYE_PCMAP_SIZE;

    if (pred->contador[indice] > 0)
    {
        pred->contador[indice]--;
    }
}