#include "file_io.h"
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h> 

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

    char linha[256];
    size_t contador = 0;
 
    /* --- 1a passagem: conta linhas válidas (não comentário, não vazia) --- */
    while (fgets(linha, sizeof(linha), arquivo) != NULL)
    {
        /* encontra o primeiro caractere não-espaço da linha */
        char *p = linha;
        while (*p && isspace((unsigned char)*p)) p++;
 
        /* pula linha vazia ou comentário */
        if (*p == '\0' || *p == '#') continue;
 
        /* verifica se a linha contém um inteiro válido */
        int valor;
        if (sscanf(p, "%d", &valor) == 1)
            contador++;
    }
 
    if (contador == 0)
    {
        printf("Aviso: arquivo '%s' nao contem enderecos validos.\n", nome_arquivo);
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
 
    /* --- 2a passagem: relê e armazena os valores --- */
    rewind(arquivo);
    size_t idx = 0;
 
    while (fgets(linha, sizeof(linha), arquivo) != NULL && idx < contador)
    {
        char *p = linha;
        while (*p && isspace((unsigned char)*p)) p++;
 
        if (*p == '\0' || *p == '#') continue;
 
        int valor;
        if (sscanf(p, "%d", &valor) == 1)
            resultado.dados[idx++] = valor;
    }
 
    resultado.tamanho = idx;
    fclose(arquivo);
 
    printf("Arquivo '%s' lido com sucesso (%zu enderecos, comentarios ignorados).\n",
           nome_arquivo, resultado.tamanho);
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
