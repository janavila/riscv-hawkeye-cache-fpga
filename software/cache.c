#include "cache.h"
#include "lru.h"
#include <stdio.h>
#include <stdlib.h>

/* =========================================================
   FUNÇÃO DE REQUISIÇÃO DE ENDEREÇO - CACHE DE DADOS
   ========================================================= */

RequisicaoMemoria requisita_endereco_dados(unsigned int endereco)
{
	RequisicaoMemoria req;

	req.endereco = endereco;
	req.offset = endereco % BLOCK_SIZE_DADOS_BYTES;
	req.bloco = endereco / BLOCK_SIZE_DADOS_BYTES;
	req.set = req.bloco % NUM_SETS_DADOS;
	req.tag = req.bloco / NUM_SETS_DADOS;
	req.pseudo_pc = 0;

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
			cache->sets[i].linhas[j].rrpv = RRIP_MAX;
			cache->sets[i].linhas[j].assinatura_hawkeye = 0;
		}
		cache->sets[i].lru_estado[0] = 0;
		cache->sets[i].lru_estado[1] = 0;
	}

	cache->hits = 0;
	cache->misses = 0;
	cache->politica_ativa = POLITICA_L1_LRU;
	hawkeye_init_cache_state_l1(cache);

	printf("Cache de dados limpa para iniciar o programa!\n");
}

void imprime_requisicao(RequisicaoMemoria *req)
{
	printf("\n--- REQUISICAO DE MEMORIA ---\n");
	printf("Endereco original : %u\n", req->endereco);
	printf("Bloco             : %u\n", req->bloco);
	printf("Set               : %u\n", req->set);
	printf("Tag               : %u\n", req->tag);
	printf("Offset            : %u\n", req->offset);
	printf("Pseudo-PC         : %lu\n", req->pseudo_pc);
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
			cache->sets[i].linhas[j].rrpv = RRIP_MAX;
			cache->sets[i].linhas[j].assinatura_hawkeye = 0;
		}
	}

	cache->hits = 0;
	cache->misses = 0;
	cache->politica_ativa = POLITICA_L2_LRU;
	hawkeye_init_cache_state(cache);

	printf("Cache unificada limpa para iniciar o programa!\n");
}

/* =========================
   IMPRIME CACHES
   ========================= */

void imprime_cache_dados(CacheDados *cache)
{
	printf("\n--- CACHE DE DADOS (L1) ---\n");
	printf("Politica ativa: %s\n", nome_politica_l1(cache->politica_ativa));

	for (int i = 0; i < NUM_SETS_DADOS; i++)
	{
		printf("Set %d: [LRU_ESTADO: %d]\n", i, cache->sets[i].lru_estado[0]);
		for (int j = 0; j < ASSOCIATIVITY_DADOS; j++)
		{
			printf("  Linha %d -> valid: %d | tag: %u | lru: %d | rrpv: %u\n",
				   j,
				   cache->sets[i].linhas[j].valid,
				   cache->sets[i].linhas[j].tag,
				   cache->sets[i].linhas[j].lru_estado,
				   cache->sets[i].linhas[j].rrpv);
		}
	}
	printf("Hits: %lu | Misses: %lu\n", cache->hits, cache->misses);
}

void imprime_cache_unificada(CacheUnificada *cache)
{
	printf("\n--- CACHE UNIFICADA (L2) ---\n");
	printf("Politica ativa: %s\n", nome_politica_l2(cache->politica_ativa));

	for (int i = 0; i < NUM_SETS_UNIFICADA; i++)
	{
		printf("Set %d:\n", i);
		for (int j = 0; j < ASSOCIATIVITY_UNIFICADA; j++)
		{
			printf("  Linha %d -> valid: %d | tag: %u | lru: %d | rrpv: %u\n",
				   j,
				   cache->sets[i].linhas[j].valid,
				   cache->sets[i].linhas[j].tag,
				   cache->sets[i].linhas[j].lru_estado,
				   cache->sets[i].linhas[j].rrpv);
		}
	}
	printf("Hits: %lu | Misses: %lu\n", cache->hits, cache->misses);
}

/* =========================================================
   BUSCA HIT / LINHA INVÁLIDA
   ========================================================= */

int busca_hit_no_set_dados(CacheDados *cache, RequisicaoMemoria *req)
{
	for (int i = 0; i < ASSOCIATIVITY_DADOS; i++)
	{
		if (cache->sets[req->set].linhas[i].valid == 1 &&
			cache->sets[req->set].linhas[i].tag == req->tag)
		{
			return i;
		}
	}
	return -1;
}

int busca_linha_invalida_dados(CacheDados *cache, RequisicaoMemoria *req)
{
	for (int i = 0; i < ASSOCIATIVITY_DADOS; i++)
	{
		if (cache->sets[req->set].linhas[i].valid == 0)
			return i;
	}
	return -1;
}

void insere_bloco_no_set_dados(CacheDados *cache, RequisicaoMemoria *req, int linha)
{
	cache->sets[req->set].linhas[linha].valid = 1;
	cache->sets[req->set].linhas[linha].tag = req->tag;
}

int busca_hit_no_set_unificada(CacheUnificada *cache, RequisicaoMemoria *req)
{
	for (int i = 0; i < ASSOCIATIVITY_UNIFICADA; i++)
	{
		if (cache->sets[req->set].linhas[i].valid == 1 &&
			cache->sets[req->set].linhas[i].tag == req->tag)
		{
			return i;
		}
	}
	return -1;
}

int busca_linha_invalida_unificada(CacheUnificada *cache, RequisicaoMemoria *req)
{
	for (int i = 0; i < ASSOCIATIVITY_UNIFICADA; i++)
	{
		if (cache->sets[req->set].linhas[i].valid == 0)
			return i;
	}
	return -1;
}

void insere_bloco_no_set_unificada(CacheUnificada *cache, RequisicaoMemoria *req, int linha)
{
	cache->sets[req->set].linhas[linha].valid = 1;
	cache->sets[req->set].linhas[linha].tag = req->tag;
	cache->sets[req->set].linhas[linha].lru_estado = 0;
}

/* =========================================================
   IMPRIME SETS INDIVIDUAIS
   ========================================================= */

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
		printf("Linha %d -> valid: %d | tag: %u | lru: %d | rrpv: %u\n",
			   j,
			   cache->sets[set].linhas[j].valid,
			   cache->sets[set].linhas[j].tag,
			   cache->sets[set].linhas[j].lru_estado,
			   cache->sets[set].linhas[j].rrpv);
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
		printf("Linha %d -> valid: %d | tag: %u | lru: %d | rrpv: %u\n",
			   j,
			   cache->sets[set].linhas[j].valid,
			   cache->sets[set].linhas[j].tag,
			   cache->sets[set].linhas[j].lru_estado,
			   cache->sets[set].linhas[j].rrpv);
	}
}

/* =========================================================
   REQUISIÇÃO DE ENDEREÇO - CACHE UNIFICADA
   ========================================================= */

RequisicaoMemoria requisita_endereco_unificada(unsigned int endereco)
{
	RequisicaoMemoria req;

	req.endereco = endereco;
	req.offset = endereco % BLOCK_SIZE_UNIFICADA_BYTES;
	req.bloco = endereco / BLOCK_SIZE_UNIFICADA_BYTES;
	req.set = req.bloco % NUM_SETS_UNIFICADA;
	req.tag = req.bloco / NUM_SETS_UNIFICADA;
	req.pseudo_pc = 0;

	return req;
}

/* =========================================================
   ACESSA CACHE DE DADOS (L1 ISOLADA — opcao 3 do menu)
   ---------------------------------------------------------
   CORRECAO BUG #1: misses agora usam atualiza_estado_l1 e
   escolhe_vitima_l1, respeitando a politica ativa.
   Antes chamava atualizaLru/aplicaLru diretamente, fazendo
   a L1 rodar sempre LRU independente do que estava no menu.
   ========================================================= */
void acessa_cache_dados(CacheDados *cache, unsigned int endereco)
{
	RequisicaoMemoria req = requisita_endereco_dados(endereco);
	/* pseudo_pc = 0: acesso manual nao tem contexto de PC */

	int linha_hit = busca_hit_no_set_dados(cache, &req);

	if (linha_hit != -1)
	{
		cache->hits++;
		atualiza_estado_l1(cache, &req, linha_hit);
		printf("\nHIT na cache de dados! Set %u, linha %d\n", req.set, linha_hit);
		return;
	}

	cache->misses++;
	printf("\nMISS na cache de dados! Endereco %u\n", endereco);

	int linha_invalida = busca_linha_invalida_dados(cache, &req);

	if (linha_invalida != -1)
	{
		insere_bloco_no_set_dados(cache, &req, linha_invalida);
		/* BUG #1 CORRIGIDO: era atualizaLru(cache, &req, linha_invalida) */
		atualiza_estado_l1(cache, &req, linha_invalida);
		printf("Bloco inserido no set %u, linha %d\n", req.set, linha_invalida);
	}
	else
	{
		/* BUG #1 CORRIGIDO: era aplicaLru(cache, &req) diretamente */
		int linha_vitima = escolhe_vitima_l1(cache, &req);
		if (linha_vitima != -1)
		{
			insere_bloco_no_set_dados(cache, &req, linha_vitima);
			atualiza_estado_l1(cache, &req, linha_vitima);
			printf("Politica %s aplicada na L1, set %u, linha %d\n",
				   nome_politica_l1(cache->politica_ativa), req.set, linha_vitima);
		}
		else
		{
			printf("Erro: nenhuma vitima encontrada na L1, set %u\n", req.set);
		}
	}
}

/* =========================================================
   ACESSA CACHE UNIFICADA (L2 ISOLADA — opcao 7 do menu)
   ========================================================= */
void acessa_cache_unificada(CacheUnificada *cache, unsigned int endereco)
{
	RequisicaoMemoria req = requisita_endereco_unificada(endereco);

	int linha_hit = busca_hit_no_set_unificada(cache, &req);

	if (linha_hit != -1)
	{
		cache->hits++;
		atualiza_estado_l2(cache, &req, linha_hit, 1);
		printf("\nHIT na cache unificada! Set %u, linha %d\n", req.set, linha_hit);
		return;
	}

	cache->misses++;
	printf("\nMISS na cache unificada! Endereco %u\n", endereco);

	int linha_invalida = busca_linha_invalida_unificada(cache, &req);

	if (linha_invalida != -1)
	{
		insere_bloco_no_set_unificada(cache, &req, linha_invalida);
		atualiza_estado_l2(cache, &req, linha_invalida, 0);
		printf("Bloco inserido na L2, set %u, linha %d\n", req.set, linha_invalida);
	}
	else
	{
		int linha_vitima = escolhe_vitima_l2(cache, &req);
		if (linha_vitima != -1)
		{
			insere_bloco_no_set_unificada(cache, &req, linha_vitima);
			atualiza_estado_l2(cache, &req, linha_vitima, 0);
			printf("Politica %s aplicada na L2, set %u, linha %d\n",
				   nome_politica_l2(cache->politica_ativa), req.set, linha_vitima);
		}
		else
		{
			printf("Erro: nenhuma vitima encontrada na L2, set %u\n", req.set);
		}
	}
}

/* =========================================================
   CONSULTA — usado pela hierarquia
   ========================================================= */

int consulta_cache_dados(CacheDados *cache, unsigned int endereco, unsigned long pseudo_pc)
{
	RequisicaoMemoria req = requisita_endereco_dados(endereco);
	req.pseudo_pc = pseudo_pc;

	int linha_hit = busca_hit_no_set_dados(cache, &req);

	if (linha_hit != -1)
	{
		atualiza_estado_l1(cache, &req, linha_hit);
		printf("\nHIT na L1! Set %u, linha %d\n", req.set, linha_hit);
		return 1;
	}

	printf("\nMISS na L1! Endereco %u\n", endereco);
	return 0;
}

int consulta_cache_unificada(CacheUnificada *cache, unsigned int endereco, unsigned long pseudo_pc)
{
	RequisicaoMemoria req = requisita_endereco_unificada(endereco);
	req.pseudo_pc = pseudo_pc;

	int linha_hit = busca_hit_no_set_unificada(cache, &req);

	if (linha_hit != -1)
	{
		atualiza_estado_l2(cache, &req, linha_hit, 1);
		printf("HIT na L2! Set %u, linha %d\n", req.set, linha_hit);
		return 1;
	}

	printf("MISS na L2! Endereco %u\n", endereco);
	return 0;
}

/* =========================================================
   INSERE NA L1
   ========================================================= */

void insere_endereco_na_l1(CacheDados *cache, unsigned int endereco, unsigned long pseudo_pc)
{
	RequisicaoMemoria req = requisita_endereco_dados(endereco);
	req.pseudo_pc = pseudo_pc;

	int linha_invalida = busca_linha_invalida_dados(cache, &req);

	if (linha_invalida != -1)
	{
		insere_bloco_no_set_dados(cache, &req, linha_invalida);
		atualiza_estado_l1(cache, &req, linha_invalida);
		printf("Bloco inserido na L1, set %u, linha %d\n", req.set, linha_invalida);
	}
	else
	{
		int linha_vitima = escolhe_vitima_l1(cache, &req);
		if (linha_vitima != -1)
		{
			insere_bloco_no_set_dados(cache, &req, linha_vitima);
			atualiza_estado_l1(cache, &req, linha_vitima);
			printf("Politica %s aplicada na L1, set %u, linha %d\n",
				   nome_politica_l1(cache->politica_ativa), req.set, linha_vitima);
		}
		else
		{
			printf("Erro: nenhuma vitima encontrada na L1, set %u\n", req.set);
		}
	}
}

/* =========================================================
   INSERE NA L2
   ---------------------------------------------------------
   CORRECAO PROBLEMA #5: atualiza_estado_l2 chamado com hit=0
   aqui. Isso garante que o preditor registra o miss (inserção)
   uma unica vez. escolhe_vitima_l2 apenas seleciona a vitima
   pelo RRIP sem tocar no preditor.
   ========================================================= */

void insere_endereco_na_l2(CacheUnificada *cache, unsigned int endereco, unsigned long pseudo_pc)
{
	RequisicaoMemoria req = requisita_endereco_unificada(endereco);
	req.pseudo_pc = pseudo_pc;

	int linha_invalida = busca_linha_invalida_unificada(cache, &req);

	if (linha_invalida != -1)
	{
		insere_bloco_no_set_unificada(cache, &req, linha_invalida);
		/* hit=0: inserção nova, preditor aprende que é um miss */
		atualiza_estado_l2(cache, &req, linha_invalida, 0);
		printf("Bloco inserido na L2, set %u, linha %d\n", req.set, linha_invalida);
	}
	else
	{
		int linha_vitima = escolhe_vitima_l2(cache, &req);
		if (linha_vitima != -1)
		{
			insere_bloco_no_set_unificada(cache, &req, linha_vitima);
			/* hit=0: inserção nova */
			atualiza_estado_l2(cache, &req, linha_vitima, 0);
			printf("Politica %s aplicada na L2, set %u, linha %d\n",
				   nome_politica_l2(cache->politica_ativa), req.set, linha_vitima);
		}
		else
		{
			printf("Erro: nenhuma vitima encontrada na L2, set %u\n", req.set);
		}
	}
}

/* =========================================================
   HIERARQUIA COMPLETA L1 -> L2 -> RAM
   ========================================================= */

void acessa_hierarquia_memoria(CacheDados *cache_dados,
							   CacheUnificada *cache_unificada,
							   unsigned int endereco,
							   unsigned long pseudo_pc)
{
	printf("\n=== ACESSO A HIERARQUIA ===  Endereco: %u  PC: %lu\n", endereco, pseudo_pc);

	int hit_l1 = consulta_cache_dados(cache_dados, endereco, pseudo_pc);
	if (hit_l1)
	{
		cache_dados->hits++;
		printf("Resultado: L1 HIT.\n");
		return;
	}
	cache_dados->misses++;

	int hit_l2 = consulta_cache_unificada(cache_unificada, endereco, pseudo_pc);
	if (hit_l2)
	{
		cache_unificada->hits++;
		insere_endereco_na_l1(cache_dados, endereco, pseudo_pc);
		printf("Resultado: L2 HIT — promovido para L1.\n");
		return;
	}
	cache_unificada->misses++;

	printf("Resultado: RAM — inserindo em L2 e L1.\n");
	insere_endereco_na_l2(cache_unificada, endereco, pseudo_pc);
	insere_endereco_na_l1(cache_dados, endereco, pseudo_pc);
}

/* =========================================================
   LRU UNIFICADA (L2 modo LRU)
   ========================================================= */

void atualiza_lru_unificada(CacheUnificada *cache, RequisicaoMemoria *req, int linha_acessada)
{
	for (int i = 0; i < ASSOCIATIVITY_UNIFICADA; i++)
	{
		if (cache->sets[req->set].linhas[i].valid)
		{
			if (i == linha_acessada)
				cache->sets[req->set].linhas[i].lru_estado = 0;
			else
				cache->sets[req->set].linhas[i].lru_estado++;
		}
	}
}

int escolhe_vitima_lru_unificada(CacheUnificada *cache, RequisicaoMemoria *req)
{
	int linha_vitima = -1;
	int maior_idade = -1;

	for (int i = 0; i < ASSOCIATIVITY_UNIFICADA; i++)
	{
		if (cache->sets[req->set].linhas[i].valid &&
			cache->sets[req->set].linhas[i].lru_estado > maior_idade)
		{
			maior_idade = cache->sets[req->set].linhas[i].lru_estado;
			linha_vitima = i;
		}
	}
	return linha_vitima;
}

/* =========================================================
   POLITICA L2 — SELETOR
   ========================================================= */

void set_politica_l2(CacheUnificada *cache, PoliticaL2 politica)
{
	cache->politica_ativa = politica;
}

const char *nome_politica_l2(PoliticaL2 politica)
{
	if (politica == POLITICA_L2_LRU)
		return "LRU";
	if (politica == POLITICA_L2_HAWKEYE)
		return "HAWKEYE";
	return "DESCONHECIDA";
}

/* =========================================================
   ATUALIZA ESTADO L2
   ---------------------------------------------------------
   CORRECAO PROBLEMA #3: agora recebe o parametro `hit` e
   o passa corretamente para atualiza_rrip_l2 e para
   hawkeye_update_on_access. Antes sempre passava hit=1,
   zerando o rrpv mesmo em insercoes (miss), o que impedia
   o mecanismo RRIP de funcionar corretamente.
   ========================================================= */
void atualiza_estado_l2(CacheUnificada *cache, RequisicaoMemoria *req,
						int linha_acessada, int hit)
{
	uint64_t pc = (uint64_t)req->pseudo_pc;

	if (cache->politica_ativa == POLITICA_L2_LRU)
	{
		atualiza_lru_unificada(cache, req, linha_acessada);
	}
	else if (cache->politica_ativa == POLITICA_L2_HAWKEYE)
	{
		/* PROBLEMA #3 CORRIGIDO: hit passado corretamente */
		hawkeye_update_on_access(cache, req, pc, hit);
		atualiza_rrip_l2(cache, req, linha_acessada, hit);
	}
}

/* =========================================================
   ESCOLHE VITIMA L2
   ---------------------------------------------------------
   CORRECAO PROBLEMA #5: nao chama mais hawkeye_update_on_access
   aqui. O update do preditor ocorre apenas em atualiza_estado_l2
   (via insere_endereco_na_l2 com hit=0), garantindo que cada
   acesso é processado exatamente uma vez pelo preditor.
   ========================================================= */
int escolhe_vitima_l2(CacheUnificada *cache, RequisicaoMemoria *req)
{
	if (cache->politica_ativa == POLITICA_L2_LRU)
		return escolhe_vitima_lru_unificada(cache, req);

	if (cache->politica_ativa == POLITICA_L2_HAWKEYE)
		return escolhe_vitima_rrip_l2(cache, req);

	return -1;
}

/* =========================================================
   HAWKEYE L2 — FUNCOES AUXILIARES
   ========================================================= */

void atualiza_hawkeye_l2(CacheUnificada *cache, uint64_t pc, int hit)
{
	if (hit)
		hawkeye_increase(&cache->hawkeye_preditor, pc);
	else
		hawkeye_decrease(&cache->hawkeye_preditor, pc);
}

int escolhe_vitima_hawkeye_l2(CacheUnificada *cache, RequisicaoMemoria *req, uint64_t pc)
{
	(void)pc;
	return escolhe_vitima_hawkeye_real(cache, req);
}

void hawkeye_init_cache_state(CacheUnificada *cache)
{
	hawkeye_init(&cache->hawkeye_preditor);
	sampler_init(cache->sampler_sets);

	for (int i = 0; i < NUM_SETS_UNIFICADA; i++)
	{
		optgen_init(&cache->optgen_sets[i], ASSOCIATIVITY_UNIFICADA);
		cache->set_timer[i] = 0;
	}
}

/* =========================================================
   HAWKEYE_UPDATE_ON_ACCESS — L2
   ---------------------------------------------------------
   CORRECAO BUG #4: era hawkeye_crc(req->bloco >> 6).
   req->bloco ja e endereco/64. O shift 6 extra descartava bits
   validos, reduzindo a diversidade de signatures e causando
   colisoes desnecessarias no sampler.
   Correto: hawkeye_crc(req->bloco) % 256.
   ========================================================= */
void hawkeye_update_on_access(CacheUnificada *cache, RequisicaoMemoria *req,
							  uint64_t pc, int hit)
{
	uint64_t currentVal = cache->set_timer[req->set] % OPTGEN_SIZE;

	/* BUG #4 CORRIGIDO: era hawkeye_crc(req->bloco >> 6) */
	uint64_t signature = hawkeye_crc(req->bloco) % 256;
	uint32_t sample_set = req->set % SAMPLER_SETS;

	int pos = sampler_find(&cache->sampler_sets[sample_set], signature);

	if (pos != -1)
	{
		if (!hit)
		{
			uint32_t prev_mod = cache->sampler_sets[sample_set].entries[pos].previous_time % OPTGEN_SIZE;
			int should_cache = optgen_is_cache(&cache->optgen_sets[req->set], currentVal, prev_mod);

			if (should_cache)
				hawkeye_increase(&cache->hawkeye_preditor,
								 cache->sampler_sets[sample_set].entries[pos].pc);
			else
				hawkeye_decrease(&cache->hawkeye_preditor,
								 cache->sampler_sets[sample_set].entries[pos].pc);
		}

		optgen_set_access(&cache->optgen_sets[req->set], currentVal);
		sampler_age_entries(&cache->sampler_sets[sample_set],
							cache->sampler_sets[sample_set].entries[pos].lru);

		cache->sampler_sets[sample_set].entries[pos].pc = pc;
		cache->sampler_sets[sample_set].entries[pos].previous_time = (uint32_t)cache->set_timer[req->set];
		cache->sampler_sets[sample_set].entries[pos].lru = 0;
		cache->sampler_sets[sample_set].entries[pos].prefetching = 0;
	}
	else
	{
		pos = sampler_allocate_or_replace(&cache->sampler_sets[sample_set], signature);

		cache->sampler_sets[sample_set].entries[pos].valid = 1;
		cache->sampler_sets[sample_set].entries[pos].signature = signature;
		cache->sampler_sets[sample_set].entries[pos].pc = pc;
		cache->sampler_sets[sample_set].entries[pos].previous_time = (uint32_t)cache->set_timer[req->set];
		cache->sampler_sets[sample_set].entries[pos].lru = 0;
		cache->sampler_sets[sample_set].entries[pos].prefetching = 0;

		optgen_set_access(&cache->optgen_sets[req->set], currentVal);
		sampler_age_entries(&cache->sampler_sets[sample_set], SAMPLER_HIST - 1);
	}

	cache->set_timer[req->set] = (cache->set_timer[req->set] + 1) % 1024;
}

int linha_cache_friendly(CacheUnificada *cache, uint64_t pc)
{
	return hawkeye_get_prediction(&cache->hawkeye_preditor, pc);
}

int escolhe_vitima_hawkeye_real(CacheUnificada *cache, RequisicaoMemoria *req)
{
	int linha_escolhida = -1;
	unsigned int maior_rrpv = 0;

	for (int i = 0; i < ASSOCIATIVITY_UNIFICADA; i++)
	{
		if (cache->sets[req->set].linhas[i].valid)
		{
			uint64_t pc_linha = ((uint64_t)cache->sets[req->set].linhas[i].tag << 6) | req->set;

			if (!linha_cache_friendly(cache, pc_linha))
			{
				if (linha_escolhida == -1 ||
					cache->sets[req->set].linhas[i].rrpv > maior_rrpv)
				{
					maior_rrpv = cache->sets[req->set].linhas[i].rrpv;
					linha_escolhida = i;
				}
			}
		}
	}

	/* Fallback: todos sao friendly — usa LRU */
	if (linha_escolhida == -1)
		return escolhe_vitima_lru_unificada(cache, req);

	return linha_escolhida;
}

/* =========================================================
   POLITICA L1 — SELETOR
   ========================================================= */

void set_politica_l1(CacheDados *cache, PoliticaL1 politica)
{
	cache->politica_ativa = politica;
}

const char *nome_politica_l1(PoliticaL1 politica)
{
	if (politica == POLITICA_L1_LRU)
		return "LRU";
	if (politica == POLITICA_L1_HAWKEYE)
		return "HAWKEYE";
	return "DESCONHECIDA";
}

/* =========================================================
   HAWKEYE L1 — INIT
   ========================================================= */

void hawkeye_init_cache_state_l1(CacheDados *cache)
{
	hawkeye_init(&cache->hawkeye_preditor);
	sampler_init(cache->sampler_sets);

	for (int i = 0; i < NUM_SETS_DADOS; i++)
	{
		/* cache_size = ASSOCIATIVITY - 1: deixa espaco para nova insercao */
		optgen_init(&cache->optgen_sets[i], ASSOCIATIVITY_DADOS);
		cache->set_timer[i] = 0;
	}
}

int linha_cache_friendly_l1(CacheDados *cache, uint64_t pc)
{
	return hawkeye_get_prediction(&cache->hawkeye_preditor, pc);
}

/* =========================================================
   HAWKEYE_UPDATE_ON_ACCESS — L1
   ---------------------------------------------------------
   CORRECAO BUG #3: era hawkeye_crc(req->bloco >> 5).
   req->bloco ja e endereco/32. O shift 5 extra descartava bits
   validos e causava colisoes no sampler da L1.
   Correto: hawkeye_crc(req->bloco) % 256.
   ========================================================= */
void hawkeye_update_on_access_l1(CacheDados *cache, RequisicaoMemoria *req,
								 uint64_t pc, int hit)
{
	uint64_t currentVal = cache->set_timer[req->set] % OPTGEN_SIZE;

	/* BUG #3 CORRIGIDO: era hawkeye_crc(req->bloco >> 5) */
	uint64_t signature = hawkeye_crc(req->bloco) % 256;
	uint32_t sample_set = req->set % SAMPLER_SETS;

	int pos = sampler_find(&cache->sampler_sets[sample_set], signature);

	if (pos != -1)
	{
		if (!hit)
		{
			uint32_t prev_mod = cache->sampler_sets[sample_set].entries[pos].previous_time % OPTGEN_SIZE;
			int should_cache = optgen_is_cache(&cache->optgen_sets[req->set], currentVal, prev_mod);

			if (should_cache)
				hawkeye_increase(&cache->hawkeye_preditor,
								 cache->sampler_sets[sample_set].entries[pos].pc);
			else
				hawkeye_decrease(&cache->hawkeye_preditor,
								 cache->sampler_sets[sample_set].entries[pos].pc);
		}

		optgen_set_access(&cache->optgen_sets[req->set], currentVal);
		sampler_age_entries(&cache->sampler_sets[sample_set],
							cache->sampler_sets[sample_set].entries[pos].lru);

		cache->sampler_sets[sample_set].entries[pos].pc = pc;
		cache->sampler_sets[sample_set].entries[pos].previous_time = (uint32_t)cache->set_timer[req->set];
		cache->sampler_sets[sample_set].entries[pos].lru = 0;
		cache->sampler_sets[sample_set].entries[pos].prefetching = 0;
	}
	else
	{
		pos = sampler_allocate_or_replace(&cache->sampler_sets[sample_set], signature);

		cache->sampler_sets[sample_set].entries[pos].valid = 1;
		cache->sampler_sets[sample_set].entries[pos].signature = signature;
		cache->sampler_sets[sample_set].entries[pos].pc = pc;
		cache->sampler_sets[sample_set].entries[pos].previous_time = (uint32_t)cache->set_timer[req->set];
		cache->sampler_sets[sample_set].entries[pos].lru = 0;
		cache->sampler_sets[sample_set].entries[pos].prefetching = 0;

		optgen_set_access(&cache->optgen_sets[req->set], currentVal);
		sampler_age_entries(&cache->sampler_sets[sample_set], SAMPLER_HIST - 1);
	}

	cache->set_timer[req->set] = (cache->set_timer[req->set] + 1) % 1024;
}

int escolhe_vitima_hawkeye_real_l1(CacheDados *cache, RequisicaoMemoria *req)
{
	int linha_escolhida = -1;
	unsigned int maior_rrpv = 0;

	for (int i = 0; i < ASSOCIATIVITY_DADOS; i++)
	{
		if (cache->sets[req->set].linhas[i].valid)
		{
			uint64_t pc_linha = ((uint64_t)cache->sets[req->set].linhas[i].tag << 5) | req->set;

			if (!linha_cache_friendly_l1(cache, pc_linha))
			{
				if (linha_escolhida == -1 ||
					cache->sets[req->set].linhas[i].rrpv > maior_rrpv)
				{
					maior_rrpv = cache->sets[req->set].linhas[i].rrpv;
					linha_escolhida = i;
				}
			}
		}
	}

	/* Fallback: todos sao friendly — usa LRU */
	if (linha_escolhida == -1)
		return aplicaLru(cache, req);

	return linha_escolhida;
}

int escolhe_vitima_hawkeye_l1(CacheDados *cache, RequisicaoMemoria *req, uint64_t pc)
{
	(void)pc;
	return escolhe_vitima_hawkeye_real_l1(cache, req);
}

/* =========================================================
   ATUALIZA ESTADO L1
   ========================================================= */
void atualiza_estado_l1(CacheDados *cache, RequisicaoMemoria *req, int linha_acessada)
{
	uint64_t pc = (uint64_t)req->pseudo_pc;

	if (cache->politica_ativa == POLITICA_L1_LRU)
	{
		atualizaLru(cache, req, linha_acessada);
	}
	else if (cache->politica_ativa == POLITICA_L1_HAWKEYE)
	{
		hawkeye_update_on_access_l1(cache, req, pc, 1);
		atualiza_rrip_l1(cache, req, linha_acessada, 1);
	}
}

/* =========================================================
   ESCOLHE VITIMA L1
   ========================================================= */
int escolhe_vitima_l1(CacheDados *cache, RequisicaoMemoria *req)
{
	if (cache->politica_ativa == POLITICA_L1_LRU)
		return aplicaLru(cache, req);

	if (cache->politica_ativa == POLITICA_L1_HAWKEYE)
	{
		/* Registra o miss no preditor antes de escolher a vitima */
		hawkeye_update_on_access_l1(cache, req, (uint64_t)req->pseudo_pc, 0);
		return escolhe_vitima_rrip_l1(cache, req);
	}

	return -1;
}

/* =========================================================
   RRIP L2
   ========================================================= */

void atualiza_rrip_l2(CacheUnificada *cache, RequisicaoMemoria *req, int linha, int hit)
{
	uint64_t pc = (uint64_t)req->pseudo_pc;
	int amigavel = hawkeye_get_prediction(&cache->hawkeye_preditor, pc);

	cache->sets[req->set].linhas[linha].assinatura_hawkeye = pc;

	if (hit)
	{
		if (amigavel)
			cache->sets[req->set].linhas[linha].rrpv = 0;
		else if (cache->sets[req->set].linhas[linha].rrpv > 0)
			cache->sets[req->set].linhas[linha].rrpv--;
		return;
	}

	/* Miss (insercao): define rrpv conforme predicao */
	if (amigavel)
		cache->sets[req->set].linhas[linha].rrpv = RRIP_INSERCAO_AMIGAVEL;
	else
		cache->sets[req->set].linhas[linha].rrpv = RRIP_INSERCAO_AVERSA;
}

int escolhe_vitima_rrip_l2(CacheUnificada *cache, RequisicaoMemoria *req)
{
	while (1)
	{
		/* Procura linha com rrpv maximo (candidata a eviction) */
		for (int i = 0; i < ASSOCIATIVITY_UNIFICADA; i++)
		{
			if (cache->sets[req->set].linhas[i].valid &&
				cache->sets[req->set].linhas[i].rrpv == RRIP_MAX)
			{
				/* Penaliza o preditor pela eviction */
				hawkeye_decrease(&cache->hawkeye_preditor,
								 cache->sets[req->set].linhas[i].assinatura_hawkeye);
				return i;
			}
		}

		/* Nenhuma com rrpv maximo: envelhece todas */
		for (int i = 0; i < ASSOCIATIVITY_UNIFICADA; i++)
		{
			if (cache->sets[req->set].linhas[i].valid &&
				cache->sets[req->set].linhas[i].rrpv < RRIP_MAX)
			{
				cache->sets[req->set].linhas[i].rrpv++;
			}
		}
	}
}

/* =========================================================
   RRIP L1
   ========================================================= */

void atualiza_rrip_l1(CacheDados *cache, RequisicaoMemoria *req, int linha, int hit)
{
	uint64_t pc = (uint64_t)req->pseudo_pc;
	int amigavel = hawkeye_get_prediction(&cache->hawkeye_preditor, pc);

	cache->sets[req->set].linhas[linha].assinatura_hawkeye = pc;

	if (hit)
	{
		if (amigavel)
			cache->sets[req->set].linhas[linha].rrpv = 0;
		else if (cache->sets[req->set].linhas[linha].rrpv > 0)
			cache->sets[req->set].linhas[linha].rrpv--;
		return;
	}

	if (amigavel)
		cache->sets[req->set].linhas[linha].rrpv = RRIP_INSERCAO_AMIGAVEL;
	else
		cache->sets[req->set].linhas[linha].rrpv = RRIP_INSERCAO_AVERSA;
}

int escolhe_vitima_rrip_l1(CacheDados *cache, RequisicaoMemoria *req)
{
	while (1)
	{
		for (int i = 0; i < ASSOCIATIVITY_DADOS; i++)
		{
			if (cache->sets[req->set].linhas[i].valid &&
				cache->sets[req->set].linhas[i].rrpv == RRIP_MAX)
			{
				hawkeye_decrease(&cache->hawkeye_preditor,
								 cache->sets[req->set].linhas[i].assinatura_hawkeye);
				return i;
			}
		}

		for (int i = 0; i < ASSOCIATIVITY_DADOS; i++)
		{
			if (cache->sets[req->set].linhas[i].valid &&
				cache->sets[req->set].linhas[i].rrpv < RRIP_MAX)
			{
				cache->sets[req->set].linhas[i].rrpv++;
			}
		}
	}
}
