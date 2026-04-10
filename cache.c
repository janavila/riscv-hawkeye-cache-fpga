#include "cache.h"
#include <stdio.h>
#include <stdlib.h>


/* =========================================================
   FUNÇÃO DE REQUISIÇÃO DE ENDEREÇO - CACHE DE DADOS
   ========================================================= */

/*
   Essa função recebe um endereço de memória e gera uma
   requisição já quebrada em:
   - bloco
   - set
   - tag
   - offset

   Ela ainda não acessa a cache.
   Ela apenas prepara as informações que serão usadas
   pelas políticas de substituição depois.
*/
RequisicaoMemoria requisita_endereco_dados(unsigned int endereco)
{
	RequisicaoMemoria req;

	req.endereco = endereco;

	/* Offset = posição dentro do bloco */
	req.offset = endereco % BLOCK_SIZE_DADOS_BYTES;

	/* Bloco = endereço dividido pelo tamanho do bloco */
	req.bloco = endereco / BLOCK_SIZE_DADOS_BYTES;

	/* Set = bloco mapeado para um dos sets da cache */
	req.set = req.bloco % NUM_SETS_DADOS;

	/* Tag = identifica qual bloco está naquele set */
	req.tag = req.bloco / NUM_SETS_DADOS;

	return req;
}

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

void imprime_requisicao(RequisicaoMemoria *req)
{
	printf("\n--- REQUISICAO DE MEMORIA ---\n");
	printf("Endereco original: %u\n", req->endereco);
	printf("Bloco: %u\n", req->bloco);
	printf("Set: %u\n", req->set);
	printf("Tag: %u\n", req->tag);
	printf("Offset: %u\n", req->offset);
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
/* =========================================================
   FUNÇÃO PARA BUSCAR HIT NO SET DA CACHE DE DADOS
   ========================================================= */

/*
   Essa função verifica se a tag procurada já está presente
   em alguma linha válida do set correspondente.

   Retorno:
   - índice da linha (0 ou 1, no caso da L1 de dados) se achar hit
   - -1 se não encontrar
*/
int busca_hit_no_set_dados(CacheDados *cache, RequisicaoMemoria *req)
{
	for (int i = 0; i < ASSOCIATIVITY_DADOS; i++)
	{
		/*
		   Primeiro verifica se a linha está válida.
		   Não adianta comparar tag em linha vazia.
		*/
		if (cache->sets[req->set].linhas[i].valid == 1)
		{
			/*
			   Se a tag da linha for igual à tag da requisição,
			   então encontramos o bloco na cache.
			*/
			if (cache->sets[req->set].linhas[i].tag == req->tag)
			{
				return i; // hit: retorna a linha onde encontrou
			}
		}
	}

	/*
	   Se terminou o laço e não encontrou nada,
	   então foi miss.
	*/
	return -1;
}

int busca_linha_invalida_dados(CacheDados *cache, RequisicaoMemoria *req)
{
	for (int i = 0; i < ASSOCIATIVITY_DADOS; i++)
	{
		if (cache->sets[req->set].linhas[i].valid == 0)
		{
			return i;
		}
	}

	return -1;
}

void insere_bloco_no_set_dados(CacheDados *cache, RequisicaoMemoria *req, int linha_escolhida)
{
	cache->sets[req->set].linhas[linha_escolhida].valid = 1;
	cache->sets[req->set].linhas[linha_escolhida].tag = req->tag;
	cache->sets[req->set].linhas[linha_escolhida].lru_estado = 0;
}
void acessa_cache_dados(CacheDados *cache, unsigned int endereco)
{
	RequisicaoMemoria req;
	int linha_hit;
	int linha_invalida;

	req = requisita_endereco_dados(endereco);

	linha_hit = busca_hit_no_set_dados(cache, &req);

	if (linha_hit != -1)
	{
		cache->hits++;
		printf("\nHIT na cache de dados! Set %u, linha %d\n", req.set, linha_hit);
		return;
	}

	cache->misses++;
	printf("\nMISS na cache de dados! Endereco %u\n", endereco);

	linha_invalida = busca_linha_invalida_dados(cache, &req);

	if (linha_invalida != -1)
	{
		insere_bloco_no_set_dados(cache, &req, linha_invalida);
		printf("Bloco inserido no set %u, linha %d\n", req.set, linha_invalida);
	}
	else
	{
		printf("Set %u cheio. Substituicao ainda nao implementada.\n", req.set);
	}
}

void imprime_set_dados(CacheDados *cache, int set)
{
	if (set < 0 || set >= NUM_SETS_DADOS)
	{
		printf("Set invalido!\n");
		return;
	}

	printf("\n--- SET %d DA CACHE DE DADOS ---\n", set);

	for (int j = 0; j < ASSOCIATIVITY_DADOS; j++)
	{
		printf("Linha %d -> valid: %d | tag: %u | lru: %d\n",
			   j,
			   cache->sets[set].linhas[j].valid,
			   cache->sets[set].linhas[j].tag,
			   cache->sets[set].linhas[j].lru_estado);
	}
}