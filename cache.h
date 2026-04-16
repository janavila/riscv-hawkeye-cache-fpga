#ifndef CACHE_H
#define CACHE_H

/* =========================
   PARÂMETROS DA CACHE L1 DADOS
   ========================= */

#define CACHE_DADOS_SIZE_BYTES 4096
#define BLOCK_SIZE_DADOS_BYTES 32
#define ASSOCIATIVITY_DADOS 2

#define NUM_LINES_DADOS (CACHE_DADOS_SIZE_BYTES / BLOCK_SIZE_DADOS_BYTES)
#define NUM_SETS_DADOS (NUM_LINES_DADOS / ASSOCIATIVITY_DADOS)

/* =========================
   PARÂMETROS DA CACHE L2 UNIFICADA
   ========================= */

#define CACHE_UNIFICADA_SIZE_BYTES 32768
#define BLOCK_SIZE_UNIFICADA_BYTES 64
#define ASSOCIATIVITY_UNIFICADA 8

#define NUM_LINES_UNIFICADA (CACHE_UNIFICADA_SIZE_BYTES / BLOCK_SIZE_UNIFICADA_BYTES)
#define NUM_SETS_UNIFICADA (NUM_LINES_UNIFICADA / ASSOCIATIVITY_UNIFICADA)

/* =========================
   ESTRUTURA DE UMA LINHA DE CACHE
   ========================= */

typedef struct
{
   int valid;
   unsigned int tag;
   int lru_estado;
} LinhaCache;

/* =========================
   SET DA CACHE DE DADOS
   ========================= */

typedef struct
{
   LinhaCache linhas[ASSOCIATIVITY_DADOS];
   unsigned int lru_estado[2];
} SetCacheDados;

/* =========================
   SET DA CACHE UNIFICADA
   ========================= */

typedef struct
{
   LinhaCache linhas[ASSOCIATIVITY_UNIFICADA];
   unsigned int lru_estado[2];
} SetCacheUnificada;

/* =========================
   CACHE DE DADOS
   ========================= */

typedef struct
{
   SetCacheDados sets[NUM_SETS_DADOS];
   unsigned long hits;
   unsigned long misses;
} CacheDados;

/* =========================
   CACHE UNIFICADA
   ========================= */

typedef struct
{
   SetCacheUnificada sets[NUM_SETS_UNIFICADA];
   unsigned long hits;
   unsigned long misses;
} CacheUnificada;
/* =========================================================
   ESTRUTURA DE REQUISIÇÃO DE MEMÓRIA
   ========================================================= */

typedef struct
{
   unsigned int endereco; // endereço original recebido
   unsigned int bloco;    // número do bloco na memória
   unsigned int set;      // set onde esse bloco mapeia
   unsigned int tag;      // tag do bloco
   unsigned int offset;   // deslocamento dentro do bloco
} RequisicaoMemoria;

/* =========================
   PROTOTIPOS DAS FUNCOES
   ========================= */

RequisicaoMemoria requisita_endereco_dados(unsigned int endereco);

void inicializa_cache_dados(CacheDados *cache);
void imprime_requisicao(RequisicaoMemoria *req);
void imprime_cache_dados(CacheDados *cache);
void acessa_cache_dados(CacheDados *cache, unsigned int endereco);
void imprime_set_dados(CacheDados *cache, int set);

RequisicaoMemoria requisita_endereco_unificada(unsigned int endereco);

void inicializa_cache_unificada(CacheUnificada *cache);
void imprime_cache_unificada(CacheUnificada *cache);

int busca_hit_no_set_unificada(CacheUnificada *cache, RequisicaoMemoria *req);
int busca_linha_invalida_unificada(CacheUnificada *cache, RequisicaoMemoria *req);
void insere_bloco_no_set_unificada(CacheUnificada *cache, RequisicaoMemoria *req, int linha_escolhida);
void acessa_cache_unificada(CacheUnificada *cache, unsigned int endereco);
void imprime_set_unificada(CacheUnificada *cache, int set);

int consulta_cache_dados(CacheDados *cache, unsigned int endereco);
int consulta_cache_unificada(CacheUnificada *cache, unsigned int endereco);

void insere_endereco_na_l1(CacheDados *cache, unsigned int endereco);
void insere_endereco_na_l2(CacheUnificada *cache, unsigned int endereco);

void acessa_hierarquia_memoria(CacheDados *cache_dados, CacheUnificada *cache_unificada, unsigned int endereco);
#endif /* CACHE_H */