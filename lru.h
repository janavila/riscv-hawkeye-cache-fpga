#ifndef LRU_H
#define LRU_H

#include "cache.h"

/* =========================
   PROTOTIPOS DAS FUNCOES
   ========================= */

void atualizaLru (CacheDados *cache, RequisicaoMemoria *req);
void aplicaLru(CacheDados *cache, RequisicaoMemoria *req);


/* =========================
   PROTOTIPOS DAS FUNCOES
   =========================

RequisicaoMemoria requisita_endereco_dados(unsigned int endereco);

void inicializa_cache_dados(CacheDados *cache);
void imprime_requisicao(RequisicaoMemoria *req);
void imprime_cache_dados(CacheDados *cache);
void acessa_cache_dados(CacheDados *cache, unsigned int endereco);
void imprime_set_dados(CacheDados *cache, int set);

 */

 #endif /* LRU_H */