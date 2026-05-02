#include "file_io.h"
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>

/* =========================================================
   SALVA VETOR EM ARQUIVO
   ========================================================= */

int salva_vetor_em_arquivo(const char *nome_arquivo, const AcessoTrace *vetor, size_t tamanho)
{
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
        fprintf(arquivo, "%u %lu\n", vetor[i].endereco, vetor[i].pseudo_pc);
    }

    fclose(arquivo);

    printf("Vetor salvo com sucesso em '%s' (%lu elementos).\n",
           nome_arquivo, (unsigned long)tamanho);
    return 0;
}
/* =========================================================
   LE VETOR DE ARQUIVO
   ========================================================= */

VetorAcessos le_vetor_de_arquivo(const char *nome_arquivo)
{
    VetorAcessos resultado;
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

    char linha[256];
    size_t contador = 0;

    /* --- 1a passagem: conta linhas válidas --- */
    while (fgets(linha, sizeof(linha), arquivo) != NULL)
    {
        char *p = linha;
        while (*p && isspace((unsigned char)*p))
            p++;

        if (*p == '\0' || *p == '#')
            continue;

        unsigned int endereco;
        unsigned long pseudo_pc;

        if (sscanf(p, "%u %lu", &endereco, &pseudo_pc) == 2)
            contador++;
    }

    if (contador == 0)
    {
        printf("Aviso: arquivo '%s' nao contem acessos validos.\n", nome_arquivo);
        fclose(arquivo);
        return resultado;
    }

    resultado.dados = (AcessoTrace *)malloc(contador * sizeof(AcessoTrace));
    if (resultado.dados == NULL)
    {
        printf("Erro: falha ao alocar memoria para %lu elementos.\n", (unsigned long)contador);
        fclose(arquivo);
        return resultado;
    }

    rewind(arquivo);
    size_t idx = 0;

    /* --- 2a passagem: lê endereco + pseudo_pc --- */
    while (fgets(linha, sizeof(linha), arquivo) != NULL && idx < contador)
    {
        char *p = linha;
        while (*p && isspace((unsigned char)*p))
            p++;

        if (*p == '\0' || *p == '#')
            continue;

        unsigned int endereco;
        unsigned long pseudo_pc;

        if (sscanf(p, "%u %lu", &endereco, &pseudo_pc) == 2)
        {
            resultado.dados[idx].endereco = endereco;
            resultado.dados[idx].pseudo_pc = pseudo_pc;
            idx++;
        }
    }

    resultado.tamanho = idx;
    fclose(arquivo);

    printf("Arquivo '%s' lido com sucesso (%lu acessos, comentarios ignorados).\n",
           nome_arquivo, (unsigned long)idx);

    return resultado;
}
/* =========================================================
   LIBERA VETOR
   ========================================================= */

void libera_vetor(VetorAcessos *v)
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
