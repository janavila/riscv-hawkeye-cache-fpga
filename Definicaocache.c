#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

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

/* =========================
   INICIALIZA CACHE DE DADOS
   ========================= */

void inicializa_cache_dados(CacheDados *cache)
{
	for (int i = 0; i < NUM_SETS_DADOS; i++)
	{
		for (int j = 0; j < ASSOCIATIVITY_DADOS; j++)
		{
			cache->sets[i].linhas[j].valid = 0;
			cache->sets[i].linhas[j].tag = 0;
			cache->sets[i].linhas[j].lru_estado = 0;
		}
	}

	cache->hits = 0;
	cache->misses = 0;

	printf("Cache de dados limpa para iniciar o programa!\n");
}

/* =========================
   INICIALIZA CACHE UNIFICADA
   ========================= */

void inicializa_cache_unificada(CacheUnificada *cache)
{
	for (int i = 0; i < NUM_SETS_UNIFICADA; i++)
	{
		for (int j = 0; j < ASSOCIATIVITY_UNIFICADA; j++)
		{
			cache->sets[i].linhas[j].valid = 0;
			cache->sets[i].linhas[j].tag = 0;
			cache->sets[i].linhas[j].lru_estado = 0;
		}
	}

	cache->hits = 0;
	cache->misses = 0;

	printf("Cache unificada limpa para iniciar o programa!\n");
}
void imprime_cache_dados(CacheDados *cache)
{
	printf("\n--- CACHE DE DADOS ---\n");

	for (int i = 0; i < NUM_SETS_DADOS; i++)
	{
		printf("Set %d:\n", i);

		for (int j = 0; j < ASSOCIATIVITY_DADOS; j++)
		{
			printf("  Linha %d -> valid: %d | tag: %u | lru: %d\n",
				   j,
				   cache->sets[i].linhas[j].valid,
				   cache->sets[i].linhas[j].tag,
				   cache->sets[i].linhas[j].lru_estado);
		}
	}

	printf("Hits: %lu | Misses: %lu\n", cache->hits, cache->misses);
}

/* =========================
   FUNÇÃO PARA MOSTRAR CACHE UNIFICADA
   ========================= */

void imprime_cache_unificada(CacheUnificada *cache)
{
	printf("\n--- CACHE UNIFICADA ---\n");

	for (int i = 0; i < NUM_SETS_UNIFICADA; i++)
	{
		printf("Set %d:\n", i);

		for (int j = 0; j < ASSOCIATIVITY_UNIFICADA; j++)
		{
			printf("  Linha %d -> valid: %d | tag: %u | lru: %d\n",
				   j,
				   cache->sets[i].linhas[j].valid,
				   cache->sets[i].linhas[j].tag,
				   cache->sets[i].linhas[j].lru_estado);
		}
	}

	printf("Hits: %lu | Misses: %lu\n", cache->hits, cache->misses);
}

/* =========================
   MAIN
   ========================= */

int main()
{

	CacheDados cache_dados;
	CacheUnificada cache_unificada;

	/* Inicializa automaticamente */
	inicializa_cache_dados(&cache_dados);
	inicializa_cache_unificada(&cache_unificada);

	int opcao;

	do
	{
		printf("\n====== MENU ======\n");
		printf("1 - Mostrar cache de dados\n");
		printf("2 - Mostrar cache unificada\n");
		printf("0 - Sair\n");
		printf("Opcao: ");
		scanf("%d", &opcao);

		switch (opcao)
		{

		case 1:
			imprime_cache_dados(&cache_dados);
			break;

		case 2:
			imprime_cache_unificada(&cache_unificada);
			break;

		case 0:
			printf("Encerrando...\n");
			break;

		default:
			printf("Opcao invalida!\n");
		}

	} while (opcao != 0);

	return 0;
}