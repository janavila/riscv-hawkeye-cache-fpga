#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include "cache.h"
#include "file_io.h"

/* =========================
   MAIN
   ========================= */

int main()
{
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
			printf("Digite um endereco de memoria: ");
			if (scanf("%u", &endereco) != 1)
			{
				printf("Entrada invalida!\n");
				while (getchar() != '\n')
					;
				break;
			}
			acessa_cache_unificada(&cache_unificada, endereco);
			break;

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
			acessa_hierarquia_memoria(&cache_dados, &cache_unificada, endereco);
			break;
		case 10: {
			char nome_arq;
			printf("Digite o nome do arquivo: ");
			scanf("%s", nome_arq);
			VetorInteiros v = le_vetor_de_arquivo(nome_arq);
			if (v.dados != NULL) {
				printf("Processando %zu endereços...\n", v.tamanho);
				for (size_t i = 0; i < v.tamanho; i++) {
					// Converte de int para unsigned int e acessa a hierarquia
					acessa_hierarquia_memoria(&cache_dados, &cache_unificada, (unsigned int)v.dados[i]);
				}
				libera_vetor(&v); // Importante para evitar vazamento de memória
			}
			break;
		}

		case 11: {
			int n;
			char nome_arq;
			printf("Quantos endereços aleatórios deseja gerar? ");
			if (scanf("%d", &n) != 1 || n <= 0) {
				printf("Quantidade inválida!\n");
				while (getchar() != '\n');
				break;
			}
			printf("Digite o nome do arquivo para salvar (ex: random_trace.txt): ");
			scanf("%s", nome_arq);
			// Aloca memória para os valores
			int *enderecos_aleatorios = (int *)malloc(n * sizeof(int));
			if (enderecos_aleatorios == NULL) {
				printf("Erro de memória!\n");
				break;
			}
			srand(time(NULL));
			for (int i = 0; i < n; i++) {
				// Gera endereços entre 0 e 65535
				enderecos_aleatorios[i] = rand() % 65536; 
			}
			if (salva_vetor_em_arquivo(nome_arq, enderecos_aleatorios, (size_t)n) == 0) {
				printf("%d endereços aleatórios foram gerados e salvos com sucesso!\n", n);
			}
			free(enderecos_aleatorios);
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