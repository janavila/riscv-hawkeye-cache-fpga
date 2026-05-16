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

			/* salva politicas originais para restaurar ao final */
			PoliticaL1 pol_l1_orig = cache_dados.politica_ativa;
			PoliticaL2 pol_l2_orig = cache_unificada.politica_ativa;

			/* cria arquivo de log com timestamp */
			time_t agora = time(NULL);
			struct tm *t_tm = localtime(&agora);
			char nome_log[128];
			snprintf(nome_log, sizeof(nome_log),
			         "resultados_benchmark_%04d%02d%02d_%02d%02d%02d.txt",
			         t_tm->tm_year + 1900, t_tm->tm_mon + 1, t_tm->tm_mday,
			         t_tm->tm_hour, t_tm->tm_min, t_tm->tm_sec);
			FILE *log_fp = fopen(nome_log, "w");
			if (!log_fp) {
				printf("ERRO: nao foi possivel criar arquivo de log %s\n", nome_log);
				break;
			}
			fprintf(log_fp, "=== BENCHMARK COMPLETO — %s", asctime(t_tm));
			fprintf(log_fp, "Configuracoes testadas: LRU+LRU, HE+HE, LRU+HE\n");
			fprintf(log_fp, "Traces: streaming, conv, linkedlist, pattern\n\n");
			fflush(log_fp);

			typedef struct {
				double hr_l1;
				double hr_l2;
				unsigned long ciclos;
				unsigned long l1_acessos;
				unsigned long l1_hits;
				unsigned long l1_misses;
				unsigned long l2_acessos;
				unsigned long l2_hits;
				unsigned long l2_misses;
				unsigned long hits_totais;
				unsigned long misses_totais;
				double tempo_ms_val;
			} ResultadoBench;

			#define NUM_CONFIGS 3
			PoliticaL1 pols_l1[NUM_CONFIGS] = {
				POLITICA_L1_LRU,
				POLITICA_L1_HAWKEYE,
				POLITICA_L1_LRU
			};
			PoliticaL2 pols_l2[NUM_CONFIGS] = {
				POLITICA_L2_LRU,
				POLITICA_L2_HAWKEYE,
				POLITICA_L2_HAWKEYE
			};
			const char *nome_config[NUM_CONFIGS] = {
				"LRU+LRU",
				"HE+HE",
				"LRU+HE"
			};
			ResultadoBench res[NUM_CONFIGS][NUM_TRACES_BENCH];

			/* loop externo: trace; interno: politica — grava apos cada par */
			for (int tb = 0; tb < NUM_TRACES_BENCH; tb++)
			{
				for (int p = 0; p < NUM_CONFIGS; p++)
				{
					inicializa_cache_dados(&cache_dados);
					inicializa_cache_unificada(&cache_unificada);
					set_politica_l1(&cache_dados, pols_l1[p]);
					set_politica_l2(&cache_unificada, pols_l2[p]);
					cache_dados.hits = 0;
					cache_dados.misses = 0;
					cache_unificada.hits = 0;
					cache_unificada.misses = 0;

					VetorAcessos v = le_vetor_de_arquivo(nomes_traces[tb]);

					tempo_t t_ini;
					tempo_inicio(&t_ini);

					if (v.dados != NULL) {
						for (size_t i = 0; i < v.tamanho; i++) {
							acessa_hierarquia_memoria(&cache_dados,
							                          &cache_unificada,
							                          v.dados[i].endereco,
							                          v.dados[i].pseudo_pc);
						}
						libera_vetor(&v);
					}

					double ms = tempo_decorrido_ms(&t_ini);

					unsigned long tot_l1   = cache_dados.hits + cache_dados.misses;
					unsigned long tot_l2   = cache_unificada.hits + cache_unificada.misses;
					unsigned long miss_ram = cache_unificada.misses;
					unsigned long ciclos   = cache_dados.hits * 1UL +
					                         cache_unificada.hits * 10UL +
					                         miss_ram * 100UL;

					ResultadoBench r;
					r.hr_l1         = tot_l1 > 0 ? 100.0 * cache_dados.hits / tot_l1 : 0.0;
					r.hr_l2         = tot_l2 > 0 ? 100.0 * cache_unificada.hits / tot_l2 : 0.0;
					r.ciclos        = ciclos;
					r.l1_acessos    = tot_l1;
					r.l1_hits       = cache_dados.hits;
					r.l1_misses     = cache_dados.misses;
					r.l2_acessos    = tot_l2;
					r.l2_hits       = cache_unificada.hits;
					r.l2_misses     = cache_unificada.misses;
					r.hits_totais   = cache_dados.hits + cache_unificada.hits;
					r.misses_totais = cache_dados.misses + cache_unificada.misses;
					r.tempo_ms_val  = ms;

					res[p][tb] = r;

					printf("  [%s] HR-L1=%.2f%% HR-L2=%.2f%% ciclos=%lu (%.1fs)\n",
					       nome_config[p], r.hr_l1, r.hr_l2, r.ciclos, ms / 1000.0);
				}

				/* grava resultado deste trace imediatamente */
				fprintf(log_fp, "----- TRACE: %s -----\n", nomes_traces[tb]);
				for (int p = 0; p < NUM_CONFIGS; p++) {
					ResultadoBench *rp = &res[p][tb];
					fprintf(log_fp, "%s:\n", nome_config[p]);
					fprintf(log_fp, "  L1 acessos=%lu hits=%lu misses=%lu HR=%.2f%%\n",
					        rp->l1_acessos, rp->l1_hits, rp->l1_misses, rp->hr_l1);
					fprintf(log_fp, "  L2 acessos=%lu hits=%lu misses=%lu HR=%.2f%%\n",
					        rp->l2_acessos, rp->l2_hits, rp->l2_misses, rp->hr_l2);
					fprintf(log_fp, "  Total hits=%lu misses=%lu tempo_ms=%.2f ciclos=%lu\n",
					        rp->hits_totais, rp->misses_totais, rp->tempo_ms_val, rp->ciclos);
				}
				double delta_hehe   = res[1][tb].hr_l2 - res[0][tb].hr_l2;
				double delta_hibrid = res[2][tb].hr_l2 - res[0][tb].hr_l2;
				fprintf(log_fp, "Delta HR-L2 (HE+HE  vs LRU+LRU): %+.2f%%\n", delta_hehe);
				fprintf(log_fp, "Delta HR-L2 (LRU+HE vs LRU+LRU): %+.2f%%\n\n", delta_hibrid);
				fflush(log_fp);
#ifndef _WIN32
				fsync(fileno(log_fp));
#endif
			}

			printf("\n=== TABELA RESUMO ===\n");
			printf("%-25s %-10s %-10s %-10s %-10s %-12s\n",
			       "Trace", "Config", "HR-L1", "HR-L2", "Ciclos", "Tempo(ms)");
			fprintf(log_fp, "\n=== TABELA RESUMO ===\n");
			fprintf(log_fp, "%-25s %-10s %-10s %-10s %-10s %-12s\n",
			        "Trace", "Config", "HR-L1", "HR-L2", "Ciclos", "Tempo(ms)");

			for (int tb = 0; tb < NUM_TRACES_BENCH; tb++) {
				for (int p = 0; p < NUM_CONFIGS; p++) {
					ResultadoBench *rp = &res[p][tb];
					printf("%-25s %-10s %6.2f%%   %6.2f%%   %-10lu %-12.2f\n",
					       nomes_traces[tb], nome_config[p],
					       rp->hr_l1, rp->hr_l2, rp->ciclos, rp->tempo_ms_val);
					fprintf(log_fp, "%-25s %-10s %6.2f%%   %6.2f%%   %-10lu %-12.2f\n",
					        nomes_traces[tb], nome_config[p],
					        rp->hr_l1, rp->hr_l2, rp->ciclos, rp->tempo_ms_val);
				}
				printf("%-25s %-10s\n", "", "---");
				fprintf(log_fp, "%-25s %-10s\n", "", "---");
			}
			{
				time_t agora_fim = time(NULL);
				fprintf(log_fp, "Concluido em: %s", asctime(localtime(&agora_fim)));
			}
			fclose(log_fp);
			printf("\nResultados salvos em: %s\n", nome_log);

			/* restaura politicas originais */
			set_politica_l1(&cache_dados, pol_l1_orig);
			set_politica_l2(&cache_unificada, pol_l2_orig);

			#undef NUM_TRACES_BENCH
			#undef NUM_CONFIGS
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