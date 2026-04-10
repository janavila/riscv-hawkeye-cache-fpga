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
	int opcao;
	unsigned int endereco;
	RequisicaoMemoria req;
	int set_escolhido;

	inicializa_cache_dados(&cache_dados);

	do
	{
		printf("\n====== MENU ======\n");
		printf("1 - Mostrar cache de dados inteira\n");
		printf("2 - Fazer requisicao de endereco\n");
		printf("3 - Acessar cache de dados\n");
		printf("4 - Mostrar um set especifico\n");
		printf("0 - Sair\n");
		printf("Opcao: ");
		scanf("%d", &opcao);

		switch (opcao)
		{
		case 1:
			imprime_cache_dados(&cache_dados);
			break;

		case 2:
			printf("Digite um endereco de memoria: ");
			scanf("%u", &endereco);
			req = requisita_endereco_dados(endereco);
			imprime_requisicao(&req);
			break;

		case 3:
			printf("Digite um endereco de memoria: ");
			scanf("%u", &endereco);
			acessa_cache_dados(&cache_dados, endereco);
			break;

		case 4:
			printf("Digite o numero do set: ");
			scanf("%d", &set_escolhido);
			imprime_set_dados(&cache_dados, set_escolhido);
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
