#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

/* =============================================================
   CONFIGURAÇÕES — ajustadas para a L2 de 32KB do simulador
   ============================================================= */
#define L2_SIZE_BYTES  (32 * 1024)                        /* 32KB = tamanho da L2 */
#define ARRAY_SIZE     (L2_SIZE_BYTES * 2 / sizeof(int))  /* 16384 ints = 64KB = 2x L2 */

/* =============================================================
   NORMALIZAÇÃO DE ENDEREÇO
   Subtrai o endereço base para que o trace comece próximo de 0,
   compatível com o intervalo que o simulador espera.
   ============================================================= */
#define NORM(ptr, base) ((unsigned int)((uintptr_t)(ptr) - (uintptr_t)(base)))

typedef struct Node {
    int data;
    struct Node *next;
} Node;

/* =============================================================
   BENCHMARK 1 — Streaming + HotSet
   Padrão: varre array grande (não cabe na cache) com um dado
   quente acessado frequentemente. Antagonista ao LRU.
   ============================================================= */
void run_streaming(int *array, volatile int *hot_data, FILE *trace)
{
    printf("Gerando trace: Streaming + HotSet...\n");

    void *base = (void *)array;

    for (int it = 0; it < 10; it++)
    {
        for (int i = 0; i < ARRAY_SIZE; i++)
        {

            fprintf(trace, "%u\n", NORM(&array[i], base));
            array[i] += i;

            if (i % 64 == 0)
            {
                fprintf(trace, "%u\n", NORM((void *)hot_data, base));
                *hot_data += array[i];
            }
        }
    }

    printf("  -> Streaming concluido.\n");
}

/* =============================================================
   BENCHMARK 2 — Convolução de Matriz 2D
   Padrão: reuso temporal em janela de 3 linhas. Amigável à cache
   se as linhas couberem. Interessante para comparar LRU vs Hawkeye
   em padrões com localidade espacial.
   ============================================================= */
void run_matrix_conv(int *img, int *out, FILE *trace)
{
    printf("Gerando trace: Matriz 2D - Convolucao...\n");

    void *base = (void *)img;
    int width  = 128;
    int height = ARRAY_SIZE / width;

    for (int y = 1; y < height - 1; y++)
    {
        for (int x = 1; x < width - 1; x++)
        {
            /* três leituras de img (linha acima, atual, abaixo) */
            fprintf(trace, "%u\n", NORM(&img[(y-1)*width + x], base));
            fprintf(trace, "%u\n", NORM(&img[ y   *width + x], base));
            fprintf(trace, "%u\n", NORM(&img[(y+1)*width + x], base));

            /* escrita em out */
            fprintf(trace, "%u\n", NORM(&out[y*width + x], base));

            out[y*width+x] = img[(y-1)*width+x]
                           + img[ y   *width+x]
                           + img[(y+1)*width+x];
        }
    }

    printf("  -> Convolucao concluida.\n");
}

/* =============================================================
   BENCHMARK 3 — Linked List Traversal
   Padrão: pointer chasing — acessos irregulares e imprevisíveis.
   Difícil para qualquer política de cache prever.
   ============================================================= */
void run_linked_list(Node *nodes, int count, FILE *trace)
{
    printf("Gerando trace: Linked List...\n");

    void *base = (void *)nodes;
    Node *curr = nodes;

    for (int i = 0; i < count * 50; i++)
    {
        /* acesso ao campo data do nó atual */
        fprintf(trace, "%u\n", NORM(&curr->data, base));
        curr->data += i;

        /* acesso ao ponteiro next (leitura para avançar) */
        fprintf(trace, "%u\n", NORM(&curr->next, base));
        curr = curr->next;
    }

    printf("  -> Linked list concluida.\n");
}

/* =============================================================
   BENCHMARK 4 — Pattern Search
   Padrão: estresse da L2 com comparações de bytes em posições
   variadas. Loop interno limitado a 16 (original era 64) para
   evitar trace excessivamente grande.
   ============================================================= */
void run_pattern_search(uint8_t *blob, int size, FILE *trace)
{
    printf("Gerando trace: Pattern Search...\n");

    void *base = (void *)blob;

    /* limite do loop interno reduzido para controlar tamanho do trace */
    int inner_limit = 16;

    for (int i = 1024; i < size; i++)
    {
        for (int j = 1; j < inner_limit; j++)
        {
            /* dois acessos: blob[i] e blob[i-j] */
            fprintf(trace, "%u\n", NORM(&blob[i],   base));
            fprintf(trace, "%u\n", NORM(&blob[i-j], base));

            if (blob[i] == blob[i-j])
            {
                blob[i]++;
                break;
            }
        }
    }

    printf("  -> Pattern search concluida.\n");
}

/* =============================================================
   MENU
   ============================================================= */
void print_menu()
{
    printf("\n========================================\n");
    printf("  GERADOR DE TRACE - BENCHMARKS CACHE\n");
    printf("========================================\n");
    printf("1. Streaming + HotSet\n");
    printf("2. Matrix Convolution\n");
    printf("3. Linked List Traversal\n");
    printf("4. Pattern Search\n");
    printf("5. Todos em sequencia (um arquivo por benchmark)\n");
    printf("0. Sair\n");
    printf("Escolha: ");
}

/* =============================================================
   MAIN
   ============================================================= */
int main()
{
    int choice = -1;
    volatile int hot_val = 0;

    /* alocação */
    int    *big_array = (int    *)calloc(ARRAY_SIZE,    sizeof(int));
    int    *out_array = (int    *)calloc(ARRAY_SIZE,    sizeof(int));
    uint8_t *blob     = (uint8_t *)malloc(L2_SIZE_BYTES);
    Node   *nodes     = (Node   *)malloc(2000 * sizeof(Node));

    if (!big_array || !out_array || !blob || !nodes)
    {
        printf("Erro de alocacao de memoria!\n");
        return 1;
    }

    /* inicializa linked list circular */
    for (int i = 0; i < 1999; i++) nodes[i].next = &nodes[i+1];
    nodes[1999].next = &nodes[0];

    /* inicializa blob com valores variados para o pattern search */
    for (int i = 0; i < L2_SIZE_BYTES; i++) blob[i] = (uint8_t)(i % 251);

    printf("Array size: %d elementos (%d KB)\n",
           ARRAY_SIZE, (int)(ARRAY_SIZE * sizeof(int) / 1024));
    printf("L2 size referencia: %d KB\n", L2_SIZE_BYTES / 1024);

    while (choice != 0)
    {
        print_menu();
        if (scanf("%d", &choice) != 1) break;

        FILE *trace = NULL;

        switch (choice)
        {
            case 1:
                trace = fopen("trace_streaming.txt", "w");
                if (!trace) { printf("Erro ao abrir arquivo!\n"); break; }
                run_streaming(big_array, &hot_val, trace);
                fclose(trace);
                printf("Trace salvo em: trace_streaming.txt\n");
                break;

            case 2:
                trace = fopen("trace_conv.txt", "w");
                if (!trace) { printf("Erro ao abrir arquivo!\n"); break; }
                run_matrix_conv(big_array, out_array, trace);
                fclose(trace);
                printf("Trace salvo em: trace_conv.txt\n");
                break;

            case 3:
                trace = fopen("trace_linkedlist.txt", "w");
                if (!trace) { printf("Erro ao abrir arquivo!\n"); break; }
                run_linked_list(nodes, 2000, trace);
                fclose(trace);
                printf("Trace salvo em: trace_linkedlist.txt\n");
                break;

            case 4:
                trace = fopen("trace_pattern.txt", "w");
                if (!trace) { printf("Erro ao abrir arquivo!\n"); break; }
                run_pattern_search(blob, L2_SIZE_BYTES, trace);
                fclose(trace);
                printf("Trace salvo em: trace_pattern.txt\n");
                break;

            case 5:
                /* gera um arquivo separado por benchmark */
                trace = fopen("trace_streaming.txt", "w");
                run_streaming(big_array, &hot_val, trace);
                fclose(trace);

                trace = fopen("trace_conv.txt", "w");
                run_matrix_conv(big_array, out_array, trace);
                fclose(trace);

                trace = fopen("trace_linkedlist.txt", "w");
                run_linked_list(nodes, 2000, trace);
                fclose(trace);

                trace = fopen("trace_pattern.txt", "w");
                run_pattern_search(blob, L2_SIZE_BYTES, trace);
                fclose(trace);

                printf("Todos os traces gerados.\n");
                break;

            case 0:
                printf("Encerrando.\n");
                break;

            default:
                printf("Opcao invalida!\n");
        }
    }

    free(big_array);
    free(out_array);
    free(nodes);
    free(blob);
    return 0;
}
