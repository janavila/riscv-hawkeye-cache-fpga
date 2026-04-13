#include "lru.h"
#include "cache.h"
#include <stdio.h>
#include <stdlib.h>

void atualizaLru (CacheDados *cache, RequisicaoMemoria *req){

   unsigned int temp = cache->sets[req->set].lru_estado[0];

   if (req->tag == temp)
   {
    //já é o LRU, nada muda
    printf("Esta entrando quando é LRU");
   }else
   {
       printf("Esta entrando quando não é LRU");
        cache->sets[req->set].lru_estado[0] = req->tag;
        cache->sets[req->set].lru_estado[1] = temp;
   }

}

void aplicaLru(CacheDados *cache, RequisicaoMemoria *req){
    unsigned int tagLRU = cache->sets[req->set].lru_estado[1];
    for (int i = 0; i < ASSOCIATIVITY_DADOS; i++)
    {
        if (cache->sets[req->set].linhas[i].tag == tagLRU)
        {
            cache->sets[req->set].linhas[i].valid = 0;
			cache->sets[req->set].linhas[i].tag = 0;
			cache->sets[req->set].linhas[i].lru_estado = 0;
        }   
    }
    cache->sets[req->set].lru_estado[1] = -1;
}