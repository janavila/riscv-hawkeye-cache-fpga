#include "lru.h"
#include "cache.h"
#include <stdio.h>
#include <stdlib.h>

void atualizaLru(CacheDados *cache, RequisicaoMemoria *req, int linha_acessada)
{
    /* unsigned int temp = cache->sets[req->set].lru_estado[0];

    if (req->tag == temp)
    {
        // já é o mais recente, não muda
        return;
    }
    else
    {
        cache->sets[req->set].lru_estado[0] = req->tag;
        cache->sets[req->set].lru_estado[1] = temp;
    }
    */

    cache->sets[req->set].lru_estado[0] = linha_acessada;
}

int aplicaLru(CacheDados *cache, RequisicaoMemoria *req)
{
    int vitima = 1 - cache->sets[req->set].lru_estado[0];
 
    cache->sets[req->set].linhas[vitima].valid     = 0;
    cache->sets[req->set].linhas[vitima].tag        = 0;
    cache->sets[req->set].linhas[vitima].lru_estado = 0;
 
    return vitima;
}