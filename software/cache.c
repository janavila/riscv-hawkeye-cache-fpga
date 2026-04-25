#include "cache.h"
#include "lru.h"
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
		cache->sets[i].lru_estado[0] = 0;
		cache->sets[i].lru_estado[1] = 0;
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
		cache->sets[i].lru_estado[0] = 0;
		cache->sets[i].lru_estado[1] = 0;
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
		printf("--- SET_LRU [%d][%d] \n", cache->sets[i].lru_estado[0], cache->sets[i].lru_estado[1]);

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
	// cache->sets[req->set].linhas[linha_escolhida].lru_estado = 0; //o LRU vai alterar isso
}
void acessa_cache_dados(CacheDados *cache, unsigned int endereco)
{
	RequisicaoMemoria req;
	int linha_hit;
	int linha_invalida;
	int linha_vitima;

	req = requisita_endereco_dados(endereco);

	linha_hit = busca_hit_no_set_dados(cache, &req);

	if (linha_hit != -1)
	{
		cache->hits++;
		atualizaLru(cache, &req, linha_hit);
		printf("\nHIT na cache de dados! Set %u, linha %d\n", req.set, linha_hit);
		return;
	}

	cache->misses++;
	printf("\nMISS na cache de dados! Endereco %u\n", endereco);

	linha_invalida = busca_linha_invalida_dados(cache, &req);

	if (linha_invalida != -1)
	{
		insere_bloco_no_set_dados(cache, &req, linha_invalida);
		atualizaLru(cache, &req, linha_invalida);
		printf("Bloco inserido no set %u, linha %d\n", req.set, linha_invalida);
	}
	else
	{
		linha_vitima = aplicaLru(cache, &req);

		if (linha_vitima != -1)
		{
			insere_bloco_no_set_dados(cache, &req, linha_vitima);
			atualizaLru(cache, &req, linha_vitima);
			printf("LRU aplicada no set %u, nova insercao na linha %d\n", req.set, linha_vitima);
		}
		else
		{
			printf("Erro: nenhuma vitima encontrada pela LRU no set %u\n", req.set);
		}
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

RequisicaoMemoria requisita_endereco_unificada(unsigned int endereco)
{
	RequisicaoMemoria req;

	req.endereco = endereco;
	req.offset = endereco % BLOCK_SIZE_UNIFICADA_BYTES;
	req.bloco = endereco / BLOCK_SIZE_UNIFICADA_BYTES;
	req.set = req.bloco % NUM_SETS_UNIFICADA;
	req.tag = req.bloco / NUM_SETS_UNIFICADA;

	return req;
}

int busca_hit_no_set_unificada(CacheUnificada *cache, RequisicaoMemoria *req)
{
	for (int i = 0; i < ASSOCIATIVITY_UNIFICADA; i++)
	{
		if (cache->sets[req->set].linhas[i].valid == 1)
		{
			if (cache->sets[req->set].linhas[i].tag == req->tag)
			{
				return i;
			}
		}
	}

	return -1;
}

int busca_linha_invalida_unificada(CacheUnificada *cache, RequisicaoMemoria *req)
{
	for (int i = 0; i < ASSOCIATIVITY_UNIFICADA; i++)
	{
		if (cache->sets[req->set].linhas[i].valid == 0)
		{
			return i;
		}
	}

	return -1;
}

void insere_bloco_no_set_unificada(CacheUnificada *cache, RequisicaoMemoria *req, int linha_escolhida)
{
	cache->sets[req->set].linhas[linha_escolhida].valid = 1;
	cache->sets[req->set].linhas[linha_escolhida].tag = req->tag;
	cache->sets[req->set].linhas[linha_escolhida].lru_estado = 0;
}

void acessa_cache_unificada(CacheUnificada *cache, unsigned int endereco)
{
	RequisicaoMemoria req;
	int linha_hit;
	int linha_invalida;
	int linha_vitima;

	req = requisita_endereco_unificada(endereco);

	linha_hit = busca_hit_no_set_unificada(cache, &req);

	if (linha_hit != -1)
	{
		cache->hits++;
		atualiza_lru_unificada(cache, &req, linha_hit);
		printf("\nHIT na cache unificada! Set %u, linha %d\n", req.set, linha_hit);
		return;
	}

	cache->misses++;
	printf("\nMISS na cache unificada! Endereco %u\n", endereco);

	linha_invalida = busca_linha_invalida_unificada(cache, &req);

	if (linha_invalida != -1)
	{
		insere_bloco_no_set_unificada(cache, &req, linha_invalida);
		atualiza_lru_unificada(cache, &req, linha_invalida);
		printf("Bloco inserido na cache unificada no set %u, linha %d\n", req.set, linha_invalida);
	}
	else
	{
		linha_vitima = escolhe_vitima_lru_unificada(cache, &req);

		if (linha_vitima != -1)
		{
			cache->sets[req.set].linhas[linha_vitima].valid = 1;
			cache->sets[req.set].linhas[linha_vitima].tag = req.tag;
			cache->sets[req.set].linhas[linha_vitima].lru_estado = 0;

			atualiza_lru_unificada(cache, &req, linha_vitima);

			printf("LRU aplicada na cache unificada, nova insercao no set %u, linha %d\n", req.set, linha_vitima);
		}
		else
		{
			printf("Erro: nenhuma vitima encontrada pela LRU na L2 no set %u\n", req.set);
		}
	}
}
void imprime_set_unificada(CacheUnificada *cache, int set)
{
	if (set < 0 || set >= NUM_SETS_UNIFICADA)
	{
		printf("Set invalido!\n");
		return;
	}

	printf("\n--- SET %d DA CACHE UNIFICADA ---\n", set);

	for (int j = 0; j < ASSOCIATIVITY_UNIFICADA; j++)
	{
		printf("Linha %d -> valid: %d | tag: %u | lru: %d\n",
			   j,
			   cache->sets[set].linhas[j].valid,
			   cache->sets[set].linhas[j].tag,
			   cache->sets[set].linhas[j].lru_estado);
	}
}

int consulta_cache_dados(CacheDados *cache, unsigned int endereco)
{
	RequisicaoMemoria req;
	int linha_hit;

	req = requisita_endereco_dados(endereco);
	linha_hit = busca_hit_no_set_dados(cache, &req);

	if (linha_hit != -1)
	{
		atualizaLru(cache, &req, linha_hit);
		printf("\nHIT na L1 (cache de dados)! Set %u, linha %d\n", req.set, linha_hit);
		return 1;
	}

	printf("\nMISS na L1 (cache de dados)! Endereco %u\n", endereco);
	return 0;
}

void acessa_hierarquia_memoria(CacheDados *cache_dados, CacheUnificada *cache_unificada, unsigned int endereco)
{
	int hit_l1;
	int hit_l2;

	printf("\n=== ACESSO A HIERARQUIA DE MEMORIA ===\n");
	printf("Endereco solicitado: %u\n", endereco);

	hit_l1 = consulta_cache_dados(cache_dados, endereco);

	if (hit_l1)
	{
		cache_dados->hits++;
		printf("Resultado final: dado encontrado na L1.\n");
		return;
	}

	cache_dados->misses++;

	hit_l2 = consulta_cache_unificada(cache_unificada, endereco);

	if (hit_l2)
	{
		cache_unificada->hits++;
		printf("Bloco encontrado na L2. Trazendo bloco para a L1...\n");
		insere_endereco_na_l1(cache_dados, endereco);
		printf("Resultado final: dado atendido pela L2 e promovido para a L1.\n");
		return;
	}

	cache_unificada->misses++;

	printf("Bloco nao encontrado na L2. Buscando na memoria principal...\n");

	printf("Inserindo bloco na L2...\n");
	insere_endereco_na_l2(cache_unificada, endereco);

	printf("Inserindo bloco na L1...\n");
	insere_endereco_na_l1(cache_dados, endereco);

	printf("Resultado final: dado atendido pela memoria principal e inserido na L2 e na L1.\n");
}

void insere_endereco_na_l1(CacheDados *cache, unsigned int endereco)
{
	RequisicaoMemoria req;
	int linha_invalida;
	int linha_vitima;

	req = requisita_endereco_dados(endereco);

	linha_invalida = busca_linha_invalida_dados(cache, &req);

	if (linha_invalida != -1)
	{
		insere_bloco_no_set_dados(cache, &req, linha_invalida);
		atualizaLru(cache, &req, linha_invalida);
		printf("Bloco inserido na L1 no set %u, linha %d\n", req.set, linha_invalida);
	}
	else
	{
		linha_vitima = aplicaLru(cache, &req);

		if (linha_vitima != -1)
		{
			insere_bloco_no_set_dados(cache, &req, linha_vitima);
			atualizaLru(cache, &req, linha_vitima);
			printf("LRU aplicada na L1, nova insercao no set %u, linha %d\n", req.set, linha_vitima);
		}
		else
		{
			printf("Erro: nenhuma vitima encontrada pela LRU na L1 no set %u\n", req.set);
		}
	}
}

void insere_endereco_na_l2(CacheUnificada *cache, unsigned int endereco)
{
	RequisicaoMemoria req;
	int linha_invalida;
	int linha_vitima;

	req = requisita_endereco_unificada(endereco);

	linha_invalida = busca_linha_invalida_unificada(cache, &req);

	if (linha_invalida != -1)
	{
		insere_bloco_no_set_unificada(cache, &req, linha_invalida);
		atualiza_lru_unificada(cache, &req, linha_invalida);
		printf("Bloco inserido na L2 no set %u, linha %d\n", req.set, linha_invalida);
	}
	else
	{
		linha_vitima = escolhe_vitima_lru_unificada(cache, &req);

		cache->sets[req.set].linhas[linha_vitima].valid = 1;
		cache->sets[req.set].linhas[linha_vitima].tag = req.tag;

		atualiza_lru_unificada(cache, &req, linha_vitima);

		printf("LRU aplicada na L2, nova insercao no set %u, linha %d\n", req.set, linha_vitima);
	}
}
void atualiza_lru_unificada(CacheUnificada *cache, RequisicaoMemoria *req, int linha_acessada)
{
	for (int i = 0; i < ASSOCIATIVITY_UNIFICADA; i++)
	{
		if (cache->sets[req->set].linhas[i].valid == 1)
		{
			if (i == linha_acessada)
			{
				cache->sets[req->set].linhas[i].lru_estado = 0;
			}
			else
			{
				cache->sets[req->set].linhas[i].lru_estado++;
			}
		}
	}
}

int escolhe_vitima_lru_unificada(CacheUnificada *cache, RequisicaoMemoria *req)
{
	int linha_vitima = -1;
	int maior_idade = -1;

	for (int i = 0; i < ASSOCIATIVITY_UNIFICADA; i++)
	{
		if (cache->sets[req->set].linhas[i].valid == 1)
		{
			if (cache->sets[req->set].linhas[i].lru_estado > maior_idade)
			{
				maior_idade = cache->sets[req->set].linhas[i].lru_estado;
				linha_vitima = i;
			}
		}
	}

	return linha_vitima;
}

int consulta_cache_unificada(CacheUnificada *cache, unsigned int endereco)
{
	RequisicaoMemoria req;
	int linha_hit;

	req = requisita_endereco_unificada(endereco);
	linha_hit = busca_hit_no_set_unificada(cache, &req);

	if (linha_hit != -1)
	{
		atualiza_lru_unificada(cache, &req, linha_hit);
		printf("HIT na L2 (cache unificada)! Set %u, linha %d\n", req.set, linha_hit);
		return 1;
	}

	printf("MISS na L2 (cache unificada)! Endereco %u\n", endereco);
	return 0;
}
