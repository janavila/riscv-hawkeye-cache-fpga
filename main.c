#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "cache.h"

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

		case 0:
			printf("Encerrando...\n");
			break;

		default:
			printf("Opcao invalida!\n");
		}

	} while (opcao != 0);

	return 0;
}