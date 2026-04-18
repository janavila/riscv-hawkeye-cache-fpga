#ifndef FILE_IO_H
#define FILE_IO_H

#include <stddef.h>

typedef struct
{
    int *dados;     
    size_t tamanho; /* elementos lidos */
} VetorInteiros;

/*
   Salva um vetor de inteiros em um arquivo texto,
   um valor por linha.
*/
int salva_vetor_em_arquivo(const char *nome_arquivo, const int *vetor, size_t tamanho);

VetorInteiros le_vetor_de_arquivo(const char *nome_arquivo);

/*
   Libera a memoria alocada dentro de um VetorInteiros.
*/
void libera_vetor(VetorInteiros *v);

#endif /* FILE_IO_H */
