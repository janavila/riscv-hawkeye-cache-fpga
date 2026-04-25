#include "file_io.h"
#include <stdio.h>
#include <stdlib.h>

/* =========================================================
   SALVA VETOR EM ARQUIVO
   ========================================================= */

int salva_vetor_em_arquivo(const char *nome_arquivo, const int *vetor, size_t tamanho)
{
    /* Validacao  parametros */
    if (nome_arquivo == NULL || vetor == NULL)
    {
        printf("Erro: parametros invalidos em salva_vetor_em_arquivo.\n");
        return -1;
    }

    FILE *arquivo = fopen(nome_arquivo, "w");

    if (arquivo == NULL)
    {
        printf("Erro: nao foi possivel abrir o arquivo '%s' para escrita.\n", nome_arquivo);
        return -1;
    }

    for (size_t i = 0; i < tamanho; i++)
    {
        fprintf(arquivo, "%d\n", vetor[i]);
    }

    fclose(arquivo);

    printf("Vetor salvo com sucesso em '%s' (%zu elementos).\n", nome_arquivo, tamanho);
    return 0;
}

/* =========================================================
   LE VETOR DE ARQUIVO
   ========================================================= */

VetorInteiros le_vetor_de_arquivo(const char *nome_arquivo)
{
    VetorInteiros resultado;
    resultado.dados = NULL;
    resultado.tamanho = 0;

    if (nome_arquivo == NULL)
    {
        printf("Erro: nome de arquivo invalido.\n");
        return resultado;
    }

    FILE *arquivo = fopen(nome_arquivo, "r");

    if (arquivo == NULL)
    {
        printf("Erro: nao foi possivel abrir o arquivo '%s' para leitura.\n", nome_arquivo);
        return resultado;
    }

    /* --- 1a passagem: conta os numeros --- */
    int valor_temp;
    size_t contador = 0;

    while (fscanf(arquivo, "%d", &valor_temp) == 1)
    {
        contador++;
    }

    if (contador == 0)
    {
        printf("Aviso: arquivo '%s' esta vazio ou nao contem inteiros validos.\n", nome_arquivo);
        fclose(arquivo);
        return resultado;
    }

    /* --- Aloca vetor com tamanho exato --- */
    resultado.dados = (int *)malloc(contador * sizeof(int));

    if (resultado.dados == NULL)
    {
        printf("Erro: falha ao alocar memoria para %zu elementos.\n", contador);
        fclose(arquivo);
        return resultado;
    }

    /* --- 2a passagem: volta ao inicio e le os valores --- */
    rewind(arquivo);

    for (size_t i = 0; i < contador; i++)
    {
        fscanf(arquivo, "%d", &resultado.dados[i]);
    }

    resultado.tamanho = contador;

    fclose(arquivo);

    printf("Arquivo '%s' lido com sucesso (%zu elementos).\n", nome_arquivo, contador);
    return resultado;
}

/* =========================================================
   LIBERA VETOR
   ========================================================= */

void libera_vetor(VetorInteiros *v)
{
    if (v == NULL)
        return;

    if (v->dados != NULL)
    {
        free(v->dados);
        v->dados = NULL;
    }

    v->tamanho = 0;
}
