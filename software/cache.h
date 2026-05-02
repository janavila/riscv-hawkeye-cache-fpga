#ifndef CACHE_H
#define CACHE_H
#include "hawkeye.h"
#include "sampler.h"
#include "optgen.h"

#define RRIP_MAX 7
#define RRIP_INSERCAO_AMIGAVEL 0
#define RRIP_INSERCAO_AVERSA RRIP_MAX

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
   unsigned int rrpv;
   uint64_t assinatura_hawkeye;
} LinhaCache;

typedef enum
{
   POLITICA_L1_LRU = 0,
   POLITICA_L1_HAWKEYE = 1
} PoliticaL1;

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
} SetCacheUnificada;

/* =========================
   CACHE DE DADOS
   ========================= */

typedef struct
{
   SetCacheDados sets[NUM_SETS_DADOS];
   unsigned long hits;
   unsigned long misses;
   PoliticaL1 politica_ativa;

   HawkeyePredictor hawkeye_preditor;
   OPTgen optgen_sets[NUM_SETS_DADOS];
   SamplerSet sampler_sets[SAMPLER_SETS];
   uint64_t set_timer[NUM_SETS_DADOS];
} CacheDados;
/* =========================
   CACHE UNIFICADA
   ========================= */

typedef enum
{
   POLITICA_L2_LRU = 0,
   POLITICA_L2_HAWKEYE = 1
} PoliticaL2;

typedef struct
{
   SetCacheUnificada sets[NUM_SETS_UNIFICADA];
   unsigned long hits;
   unsigned long misses;
   PoliticaL2 politica_ativa;
   HawkeyePredictor hawkeye_preditor;

   OPTgen optgen_sets[NUM_SETS_UNIFICADA];
   SamplerSet sampler_sets[SAMPLER_SETS];
   uint64_t set_timer[NUM_SETS_UNIFICADA];
} CacheUnificada;
/* =========================================================
   ESTRUTURA DE REQUISIÇÃO DE MEMÓRIA
   ========================================================= */

typedef struct
{
   unsigned int endereco;
   unsigned int bloco;
   unsigned int set;
   unsigned int tag;
   unsigned int offset;
   unsigned long pseudo_pc;
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

int consulta_cache_dados(CacheDados *cache, unsigned int endereco, unsigned long pseudo_pc);
int consulta_cache_unificada(CacheUnificada *cache, unsigned int endereco, unsigned long pseudo_pc);
void insere_endereco_na_l1(CacheDados *cache, unsigned int endereco, unsigned long pseudo_pc);
void insere_endereco_na_l2(CacheUnificada *cache, unsigned int endereco, unsigned long pseudo_pc);

void atualiza_lru_unificada(CacheUnificada *cache, RequisicaoMemoria *req, int linha_acessada);
int escolhe_vitima_lru_unificada(CacheUnificada *cache, RequisicaoMemoria *req);

void acessa_hierarquia_memoria(CacheDados *cache_dados,
                               CacheUnificada *cache_unificada,
                               unsigned int endereco,
                               unsigned long pseudo_pc);

void set_politica_l2(CacheUnificada *cache, PoliticaL2 politica);
const char *nome_politica_l2(PoliticaL2 politica);

void atualiza_estado_l2(CacheUnificada *cache, RequisicaoMemoria *req, int linha_acessada, int hit);
int escolhe_vitima_l2(CacheUnificada *cache, RequisicaoMemoria *req);

void atualiza_hawkeye_l2(CacheUnificada *cache, uint64_t pc, int hit);
int escolhe_vitima_hawkeye_l2(CacheUnificada *cache, RequisicaoMemoria *req, uint64_t pc);

void hawkeye_init_cache_state(CacheUnificada *cache);
void hawkeye_update_on_access(CacheUnificada *cache, RequisicaoMemoria *req, uint64_t pc, int hit);

int linha_cache_friendly(CacheUnificada *cache, uint64_t pc);
int escolhe_vitima_hawkeye_real(CacheUnificada *cache, RequisicaoMemoria *req);

void set_politica_l1(CacheDados *cache, PoliticaL1 politica);
const char *nome_politica_l1(PoliticaL1 politica);

void hawkeye_init_cache_state_l1(CacheDados *cache);
void hawkeye_update_on_access_l1(CacheDados *cache, RequisicaoMemoria *req, uint64_t pc, int hit);

void atualiza_estado_l1(CacheDados *cache, RequisicaoMemoria *req, int linha_acessada);
int escolhe_vitima_l1(CacheDados *cache, RequisicaoMemoria *req);
int escolhe_vitima_hawkeye_l1(CacheDados *cache, RequisicaoMemoria *req, uint64_t pc);
int escolhe_vitima_hawkeye_real_l1(CacheDados *cache, RequisicaoMemoria *req);
int linha_cache_friendly_l1(CacheDados *cache, uint64_t pc);

void atualiza_rrip_l1(CacheDados *cache, RequisicaoMemoria *req, int linha, int hit);
int escolhe_vitima_rrip_l1(CacheDados *cache, RequisicaoMemoria *req);

void atualiza_rrip_l2(CacheUnificada *cache, RequisicaoMemoria *req, int linha, int hit);
int escolhe_vitima_rrip_l2(CacheUnificada *cache, RequisicaoMemoria *req);

#endif /* CACHE_H */