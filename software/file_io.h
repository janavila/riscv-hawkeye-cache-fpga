#ifndef FILE_IO_H
#define FILE_IO_H

#include <stddef.h>

typedef struct
{
   unsigned int endereco;
   unsigned long pseudo_pc;
} AcessoTrace;

typedef struct
{
   AcessoTrace *dados;
   size_t tamanho;
} VetorAcessos;

int salva_vetor_em_arquivo(const char *nome_arquivo, const AcessoTrace *vetor, size_t tamanho);
VetorAcessos le_vetor_de_arquivo(const char *nome_arquivo);
void libera_vetor(VetorAcessos *v);

#endif