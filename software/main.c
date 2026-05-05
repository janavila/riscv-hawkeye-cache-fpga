#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
typedef LARGE_INTEGER tempo_t;
static void tempo_inicio(tempo_t *t) { QueryPerformanceCounter(t); }
static double tempo_decorrido_ms(tempo_t *inicio) {
    LARGE_INTEGER fim, freq;
    QueryPerformanceCounter(&fim);
    QueryPerformanceFrequency(&freq);
    return 1000.0 * (fim.QuadPart - inicio->QuadPart) / freq.QuadPart;
}
#else
#include <time.h>
typedef struct timespec tempo_t;
static void tempo_inicio(tempo_t *t) { clock_gettime(CLOCK_MONOTONIC, t); }
static double tempo_decorrido_ms(tempo_t *inicio) {
    struct timespec fim;
    clock_gettime(CLOCK_MONOTONIC, &fim);
    return (fim.tv_sec - inicio->tv_sec) * 1000.0
           + (fim.tv_nsec - inicio->tv_nsec) / 1e6;
}
#endif
#include "cache.h"
#include "file_io.h"

/* =========================
   MAIN
   ========================= */

int main()
{
	// config do console para UTF-8
#ifdef _WIN32
	SetConsoleOutputCP(65001);
	SetConsoleCP(65001);
#endif
	CacheDados cache_dados;
	CacheUnificada cache_unificada;
	int opcao;
	unsigned int endereco;
	RequisicaoMemoria req;
	int set_escolhido;

	inicializa_cache_dados(&cache_dados);
	inicializa_cache_unificada(&cache_unificada);

	do
	{
		printf("\n====== MENU ======\n");
		printf("1 - Mostrar cache de dados inteira (L1)\n");
		printf("2 - Fazer requisicao de endereco na L1\n");
		printf("3 - Acessar cache de dados (L1 isolada)\n");
		printf("4 - Mostrar um set especifico da L1\n");
		printf("5 - Mostrar cache unificada inteira (L2)\n");
		printf("6 - Fazer requisicao de endereco na L2\n");
		printf("7 - Acessar cache unificada (L2 isolada)\n");
		printf("8 - Mostrar um set especifico da L2\n");
		printf("9 - Acessar hierarquia completa (L1 -> L2 -> memoria)\n");
		printf("10 - Ler endereços de um arquivo e processar na hierarquia\n");
		printf("11 - Salvar um exemplo de arquivo de teste\n");
		printf("12 - Escolher politica da L2 (LRU / HAWKEYE)\n");
		printf("13 - Escolher politica da L1 (LRU / HAWKEYE)\n");
		printf("14 - Resetar caches (zerar L1 e L2 como no inicio do programa)\n");
		printf("15 - Benchmark completo: rodar todos os traces com LRU e depois com Hawkeye\n");
		printf("Politica atual da L1: %s\n", nome_politica_l1(cache_dados.politica_ativa));
		printf("Politica atual da L2: %s\n", nome_politica_l2(cache_unificada.politica_ativa));
		printf("0 - Sair\n");
		printf("Opcao: ");

		if (scanf("%d", &opcao) != 1)
		{
			printf("Entrada invalida!\n");
			while (getchar() != '\n')
				;
			opcao = -1;
			continue;
		}

		switch (opcao)
		{
		case 1:
			imprime_cache_dados(&cache_dados);
			break;

		case 2:
			printf("Digite um endereco de memoria: ");
			if (scanf("%u", &endereco) != 1)
			{
				printf("Entrada invalida!\n");
				while (getchar() != '\n')
					;
				break;
			}
			req = requisita_endereco_dados(endereco);
			imprime_requisicao(&req);
			break;

		case 3:
			printf("Digite um endereco de memoria: ");
			if (scanf("%u", &endereco) != 1)
			{
				printf("Entrada invalida!\n");
				while (getchar() != '\n')
					;
				break;
			}
			acessa_cache_dados(&cache_dados, endereco);
			break;

		case 4:
			printf("Digite o numero do set da L1: ");
			if (scanf("%d", &set_escolhido) != 1)
			{
				printf("Entrada invalida!\n");
				while (getchar() != '\n')
					;
				break;
			}
			imprime_set_dados(&cache_dados, set_escolhido);
			break;

		case 5:
			imprime_cache_unificada(&cache_unificada);
			break;

		case 6:
			printf("Digite um endereco de memoria: ");
			if (scanf("%u", &endereco) != 1)
			{
				printf("Entrada invalida!\n");
				while (getchar() != '\n')
					;
				break;
			}
			req = requisita_endereco_unificada(endereco);
			imprime_requisicao(&req);
			break;

		case 7:
		{
			int sub;
			printf("\n--- ACESSO A L2 ISOLADA ---\n");
			printf("  1 - Digitar endereco manualmente\n");
			printf("  2 - Ler enderecos de um arquivo\n");
			printf("  Opcao: ");

			if (scanf("%d", &sub) != 1)
			{
				printf("Entrada invalida!\n");
				while (getchar() != '\n')
					;
				break;
			}

			if (sub == 1)
			{
				/* ---- entrada manual ---- */
				printf("Digite um endereco de memoria: ");
				if (scanf("%u", &endereco) != 1)
				{
					printf("Entrada invalida!\n");
					while (getchar() != '\n')
						;
					break;
				}
				acessa_cache_unificada(&cache_unificada, endereco);
			}
			else if (sub == 2)
			{
				/* ---- leitura de arquivo ---- */
				char nome_arq[100];
				printf("Digite o nome do arquivo: ");
				scanf("%s", nome_arq);

				VetorAcessos v = le_vetor_de_arquivo(nome_arq);

				if (v.dados != NULL)
				{
					printf("Processando %lu enderecos na L2 isolada...\n", (unsigned long)v.tamanho);
					/* zera contadores antes de rodar o trace */
					cache_unificada.hits = 0;
					cache_unificada.misses = 0;

					for (size_t i = 0; i < v.tamanho; i++)
					{
						acessa_hierarquia_memoria(&cache_dados,
												  &cache_unificada,
												  v.dados[i].endereco,
												  v.dados[i].pseudo_pc);
					}

					libera_vetor(&v);

					/* resumo */
					unsigned long total = cache_unificada.hits + cache_unificada.misses;

					printf("\n╔══════════════════════════════════════════╗\n");
					printf("║     RESUMO — L2 ISOLADA: %-14s║\n", nome_arq);
					printf("╠══════════════════════════════════════════╣\n");
					printf("║  Acessos : %-30lu║\n", total);
					printf("║  Hits    : %-30lu║\n", cache_unificada.hits);
					printf("║  Misses  : %-30lu║\n", cache_unificada.misses);
					if (total > 0)
						printf("║  Hit Rate: %-29.2f%%║\n",
							   100.0 * cache_unificada.hits / total);
					printf("╚══════════════════════════════════════════╝\n");
				}
			}
			else
			{
				printf("Opcao invalida!\n");
			}
			break;
		}
		case 8:
			printf("Digite o numero do set da L2: ");
			if (scanf("%d", &set_escolhido) != 1)
			{
				printf("Entrada invalida!\n");
				while (getchar() != '\n')
					;
				break;
			}
			imprime_set_unificada(&cache_unificada, set_escolhido);
			break;

		case 9:
			printf("Digite um endereco de memoria: ");
			if (scanf("%u", &endereco) != 1)
			{
				printf("Entrada invalida!\n");
				while (getchar() != '\n')
					;
				break;
			}
			acessa_hierarquia_memoria(&cache_dados, &cache_unificada, endereco, 0UL);
			break;
		case 10:
		{
			char nome_arq[100];
			printf("Digite o nome do arquivo: ");
			scanf("%s", nome_arq);

			VetorAcessos v = le_vetor_de_arquivo(nome_arq);

			PoliticaL1 pol_l1 = cache_dados.politica_ativa;
			PoliticaL2 pol_l2 = cache_unificada.politica_ativa;

			inicializa_cache_dados(&cache_dados);
			inicializa_cache_unificada(&cache_unificada);

			set_politica_l1(&cache_dados, pol_l1);
			set_politica_l2(&cache_unificada, pol_l2);

			if (v.dados != NULL)
			{
				printf("Processando %lu enderecos...\n", (unsigned long)v.tamanho);
				/* zera contadores antes de rodar o trace */
				cache_dados.hits = 0;
				cache_dados.misses = 0;
				cache_unificada.hits = 0;
				cache_unificada.misses = 0;

				tempo_t t_inicio;
				tempo_inicio(&t_inicio);

				for (size_t i = 0; i < v.tamanho; i++)
				{
					acessa_hierarquia_memoria(&cache_dados,
											  &cache_unificada,
											  v.dados[i].endereco,
											  v.dados[i].pseudo_pc);
				}

				double tempo_ms = tempo_decorrido_ms(&t_inicio);

				libera_vetor(&v);

				/* =============================================
				   RESUMO DE MÉTRICAS
				   ============================================= */
				unsigned long total_l1 = cache_dados.hits + cache_dados.misses;
				unsigned long total_l2 = cache_unificada.hits + cache_unificada.misses;

				/* misses totais = chegaram à memória principal */
				unsigned long misses_totais = cache_unificada.misses;

				/* custo simulado em ciclos:
				   hit L1 = 1 ciclo
				   hit L2 = 10 ciclos
				   miss total (RAM) = 100 ciclos               */
				unsigned long ciclos_estimados =
					cache_dados.hits * 1UL +
					cache_unificada.hits * 10UL +
					misses_totais * 100UL;

				printf("\n╔══════════════════════════════════════════╗\n");
				printf("║         RESUMO — TRACE: %-15s║\n", nome_arq);
				printf("╠══════════════════════════════════════════╣\n");

				printf("║  L1 (Cache de Dados)                     ║\n");
				printf("║    Acessos : %-28lu║\n", total_l1);
				printf("║    Hits    : %-28lu║\n", cache_dados.hits);
				printf("║    Misses  : %-28lu║\n", cache_dados.misses);
				if (total_l1 > 0)
					printf("║    Hit Rate: %-27.2f%%║\n",
						   100.0 * cache_dados.hits / total_l1);

				printf("╠══════════════════════════════════════════╣\n");

				printf("║  L2 (Cache Unificada)                    ║\n");
				printf("║    Acessos : %-28lu║\n", total_l2);
				printf("║    Hits    : %-28lu║\n", cache_unificada.hits);
				printf("║    Misses  : %-28lu║\n", cache_unificada.misses);
				if (total_l2 > 0)
					printf("║    Hit Rate: %-27.2f%%║\n",
						   100.0 * cache_unificada.hits / total_l2);

				printf("╠══════════════════════════════════════════╣\n");

				printf("║  Visão Geral                             ║\n");
				printf("║    Total acessos (L1)  : %-16lu║\n", total_l1);
				printf("║    Misses até RAM      : %-16lu║\n", misses_totais);
				printf("║    Ciclos estimados    : %-16lu║\n", ciclos_estimados);

				printf("╠══════════════════════════════════════════╣\n");
				printf("║  Totais Absolutos                        ║\n");
				printf("║    Total hits  (L1+L2): %-16lu║\n",
					   cache_dados.hits + cache_unificada.hits);
				printf("║    Total misses(L1+L2): %-16lu║\n",
					   cache_dados.misses + cache_unificada.misses);
				printf("║    Tempo de execucao  : %-13.2f ms║\n", tempo_ms);
				printf("╚══════════════════════════════════════════╝\n");
			}
			break;
		}

		case 11:
		{
			int n;
			char nome_arq[100];
			printf("Quantos endereços aleatórios deseja gerar? ");
			if (scanf("%d", &n) != 1 || n <= 0)
			{
				printf("Quantidade inválida!\n");
				while (getchar() != '\n')
					;
				break;
			}
			printf("Digite o nome do arquivo para salvar (ex: random_trace.txt): ");
			scanf("%s", nome_arq);
			// Aloca memória para os valores
			AcessoTrace *enderecos_aleatorios = (AcessoTrace *)malloc((size_t)n * sizeof(AcessoTrace));

			if (enderecos_aleatorios == NULL)
			{
				printf("Erro ao alocar memoria.\n");
				break;
			}

			for (int i = 0; i < n; i++)
			{
				enderecos_aleatorios[i].endereco = (unsigned int)(rand() % 65536);
				enderecos_aleatorios[i].pseudo_pc = 100UL + (unsigned long)(i % 4);
			}

			if (salva_vetor_em_arquivo(nome_arq, enderecos_aleatorios, (size_t)n) == 0)
			{
				printf("Arquivo de teste salvo com sucesso.\n");
			}

			free(enderecos_aleatorios);
			break;
		}
		case 12:
		{
			int escolha_politica;
			printf("\n--- POLITICA DA L2 ---\n");
			printf("1 - LRU\n");
			printf("2 - HAWKEYE\n");
			printf("Opcao: ");

			if (scanf("%d", &escolha_politica) != 1)
			{
				printf("Entrada invalida!\n");
				while (getchar() != '\n')
					;
				break;
			}

			if (escolha_politica == 1)
			{
				set_politica_l2(&cache_unificada, POLITICA_L2_LRU);
				printf("Politica da L2 alterada para LRU.\n");
			}
			else if (escolha_politica == 2)
			{
				set_politica_l2(&cache_unificada, POLITICA_L2_HAWKEYE);
				printf("Politica da L2 alterada para HAWKEYE.\n");
			}
			else
			{
				printf("Opcao invalida!\n");
			}
			break;
		}

		case 13:
		{
			int escolha_politica;
			printf("\n--- POLITICA DA L1 ---\n");
			printf("1 - LRU\n");
			printf("2 - HAWKEYE\n");
			printf("Opcao: ");

			if (scanf("%d", &escolha_politica) != 1)
			{
				printf("Entrada invalida!\n");
				while (getchar() != '\n')
					;
				break;
			}

			if (escolha_politica == 1)
			{
				set_politica_l1(&cache_dados, POLITICA_L1_LRU);
				printf("Politica da L1 alterada para LRU.\n");
			}
			else if (escolha_politica == 2)
			{
				set_politica_l1(&cache_dados, POLITICA_L1_HAWKEYE);
				printf("Politica da L1 alterada para HAWKEYE.\n");
			}
			else
			{
				printf("Opcao invalida!\n");
			}
			break;
		}

		case 14:
		{
			PoliticaL1 pol_l1_atual = cache_dados.politica_ativa;
			PoliticaL2 pol_l2_atual = cache_unificada.politica_ativa;
			inicializa_cache_dados(&cache_dados);
			inicializa_cache_unificada(&cache_unificada);
			set_politica_l1(&cache_dados, pol_l1_atual);
			set_politica_l2(&cache_unificada, pol_l2_atual);
			printf("Caches resetadas. Politicas mantidas: L1=%s L2=%s\n",
				   nome_politica_l1(pol_l1_atual), nome_politica_l2(pol_l2_atual));
			break;
		}

		case 15:
		{
			#define NUM_TRACES_BENCH 4
			char nomes_traces[NUM_TRACES_BENCH][100];
			printf("Trace 1 (ex: trace_streaming.txt): ");
			scanf("%s", nomes_traces[0]);
			printf("Trace 2 (ex: trace_conv.txt): ");
			scanf("%s", nomes_traces[1]);
			printf("Trace 3 (ex: trace_linkedlist.txt): ");
			scanf("%s", nomes_traces[2]);
			printf("Trace 4 (ex: trace_pattern.txt): ");
			scanf("%s", nomes_traces[3]);

			typedef struct {
				double hr_l1;
				double hr_l2;
				unsigned long ciclos;
			} ResultadoBench;

			ResultadoBench res_lru[NUM_TRACES_BENCH];
			ResultadoBench res_hawk[NUM_TRACES_BENCH];
			double tempo_ms[2][NUM_TRACES_BENCH];
			unsigned long hits_total[2][NUM_TRACES_BENCH];
			unsigned long misses_total[2][NUM_TRACES_BENCH];

			PoliticaL1 pols_l1[2] = { POLITICA_L1_LRU, POLITICA_L1_HAWKEYE };
			PoliticaL2 pols_l2[2] = { POLITICA_L2_LRU, POLITICA_L2_HAWKEYE };

			for (int p = 0; p < 2; p++)
			{
				for (int t = 0; t < NUM_TRACES_BENCH; t++)
				{
					inicializa_cache_dados(&cache_dados);
					inicializa_cache_unificada(&cache_unificada);
					set_politica_l1(&cache_dados, pols_l1[p]);
					set_politica_l2(&cache_unificada, pols_l2[p]);
					cache_dados.hits = 0;
					cache_dados.misses = 0;
					cache_unificada.hits = 0;
					cache_unificada.misses = 0;

					VetorAcessos v = le_vetor_de_arquivo(nomes_traces[t]);

					tempo_t t_ini;
					tempo_inicio(&t_ini);

					if (v.dados != NULL)
					{
						for (size_t i = 0; i < v.tamanho; i++)
						{
							acessa_hierarquia_memoria(&cache_dados,
													  &cache_unificada,
													  v.dados[i].endereco,
													  v.dados[i].pseudo_pc);
						}
						libera_vetor(&v);
					}

					tempo_ms[p][t] = tempo_decorrido_ms(&t_ini);

					unsigned long total_l1 = cache_dados.hits + cache_dados.misses;
					unsigned long total_l2 = cache_unificada.hits + cache_unificada.misses;
					unsigned long misses_ram = cache_unificada.misses;
					unsigned long ciclos = cache_dados.hits * 1UL +
										  cache_unificada.hits * 10UL +
										  misses_ram * 100UL;

					hits_total[p][t] = cache_dados.hits + cache_unificada.hits;
					misses_total[p][t] = cache_dados.misses + cache_unificada.misses;

					ResultadoBench r;
					r.hr_l1 = total_l1 > 0 ? 100.0 * cache_dados.hits / total_l1 : 0.0;
					r.hr_l2 = total_l2 > 0 ? 100.0 * cache_unificada.hits / total_l2 : 0.0;
					r.ciclos = ciclos;

					if (p == 0)
						res_lru[t] = r;
					else
						res_hawk[t] = r;
				}
			}

			/* restaura politica que estava antes do benchmark */
			set_politica_l1(&cache_dados, cache_dados.politica_ativa);
			set_politica_l2(&cache_unificada, cache_unificada.politica_ativa);

			printf("\n╔═══════════════════════════════════════════════════════════════════════╗\n");
			printf("║              BENCHMARK COMPLETO — LRU vs HAWKEYE                     ║\n");
			printf("╠════════════════╦══════════════════════════════╦══════════════════════╣\n");
			printf("║ Trace          ║ LRU                          ║ HAWKEYE              ║\n");
			printf("║                ║ HR-L1  HR-L2  Ciclos    ms   ║ HR-L1  HR-L2  Ciclos    ms   ║\n");
			printf("╠════════════════╬══════════════════════════════╬══════════════════════╣\n");

			for (int t = 0; t < NUM_TRACES_BENCH; t++)
			{
				printf("║ %-14s ║ %5.1f%% %5.1f%% %-8lu %5.1fms ║ %5.1f%% %5.1f%% %-8lu %5.1fms ║\n",
					   nomes_traces[t],
					   res_lru[t].hr_l1, res_lru[t].hr_l2, res_lru[t].ciclos, tempo_ms[0][t],
					   res_hawk[t].hr_l1, res_hawk[t].hr_l2, res_hawk[t].ciclos, tempo_ms[1][t]);
			}

			printf("╚════════════════╩══════════════════════════════╩══════════════════════╝\n");

			for (int t = 0; t < NUM_TRACES_BENCH; t++)
			{
				double diff = res_hawk[t].hr_l2 - res_lru[t].hr_l2;
				if (diff > 0.5)
					printf("  [%s] Hawkeye ganhou %.1f%% de hit rate na L2\n", nomes_traces[t], diff);
				else if (diff < -0.5)
					printf("  [%s] LRU ganhou %.1f%% de hit rate na L2\n", nomes_traces[t], -diff);
				else
					printf("  [%s] Empate na L2 (diferenca < 0.5%%)\n", nomes_traces[t]);
			}

			printf("\n");
			for (int t = 0; t < NUM_TRACES_BENCH; t++)
			{
				printf("  [%s]\n", nomes_traces[t]);
				printf("    Hits totais  — LRU: %-10lu  HE: %lu\n",
					   hits_total[0][t], hits_total[1][t]);
				printf("    Misses totais— LRU: %-10lu  HE: %lu\n",
					   misses_total[0][t], misses_total[1][t]);
				printf("    Tempo        — LRU: %-8.2fms  HE: %.2fms\n",
					   tempo_ms[0][t], tempo_ms[1][t]);
			}
			#undef NUM_TRACES_BENCH
			break;
		}

		case 0:
			printf("Encerrando...\n");
			break;

		default:
			printf("Opcao invalida!\n");
		}

	} while (opcao != 0);

	return 0;
}