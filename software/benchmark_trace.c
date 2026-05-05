#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

/* =============================================================
   CONFIGURACOES — ajustadas para a L2 de 32KB do simulador
   =============================================================
   MUDANCA 1: Array reduzido de 2x para 1.5x o tamanho da L2.
   Com 2x havia thrashing total — nem o Hawkeye conseguia salvar
   nada porque nao havia espaco para nenhuma politica preservar
   dados uteis. Com 1.5x existe pressao real de cache mas ainda
   ha espaco para o Hawkeye proteger os dados quentes (hot set),
   criando o cenario ideal para ele se diferenciar do LRU.
   ============================================================= */
#define L2_SIZE_BYTES (32 * 1024)
#define ARRAY_SIZE (L2_SIZE_BYTES * 3 / 2 / sizeof(int)) /* 1.5x L2 = 12288 ints = 48KB */

/* =============================================================
   NORMALIZACAO DE ENDERECO
   Subtrai o endereco base para que o trace comece proximo de 0.
   ============================================================= */
#define NORM(ptr, base) ((unsigned int)((uintptr_t)(ptr) - (uintptr_t)(base)))

typedef struct Node
{
    int data;
    struct Node *next;
} Node;

/* =============================================================
   BENCHMARK 1 — Streaming + HotSet
   ---------------------------------------------------------
   MUDANCA 2: hot_data acessado a cada 8 iteracoes (era 64).
   Com frequencia 1/64, o OPTgen raramente observava reuso do
   hot_data dentro da sua janela de 128 slots — o preditor nao
   aprendia que PC=102 e cache-friendly. Com frequencia 1/8,
   o hot_data aparece ~1500 vezes por iteracao do loop externo,
   o OPTgen detecta claramente o reuso e o preditor aprende
   a separar:
     PC=101 (array streaming) → cache-averse  → RRPV=7 → evictado
     PC=102 (hot_data)        → cache-friendly → RRPV=0 → preservado
   Esse e o cenario classico onde o Hawkeye supera o LRU.

   MUDANCA 3: 20 iteracoes externas (era 10).
   Mais iteracoes dao mais tempo para o preditor convergir e
   para as diferencas de politica acumularem.
   ============================================================= */
void run_streaming(int *array, volatile int *hot_data, FILE *trace)
{
    printf("Gerando trace: Streaming + HotSet...\n");
    printf("  Array: %d KB | L2: %d KB | Hot freq: 1/8\n",
           (int)(ARRAY_SIZE * sizeof(int) / 1024), L2_SIZE_BYTES / 1024);

    void *base = (void *)array;

    /* MUDANCA 3: 20 iteracoes para dar mais tempo ao preditor convergir */
    for (int it = 0; it < 20; it++)
    {
        for (size_t i = 0; i < ARRAY_SIZE; i++)
        {
            /* PC=101: streaming sobre o array grande — cache-averse */
            fprintf(trace, "%u %lu\n", NORM(&array[i], base), 101UL);
            array[i] += (int)i;

            /* MUDANCA 2: hot_data acessado a cada 8 (era 64)
               PC=102: acesso recorrente ao dado quente — cache-friendly */
            if (i % 1024 == 0)
            {
                fprintf(trace, "%u %lu\n", (unsigned int)(ARRAY_SIZE * sizeof(int)), 102UL);
                *hot_data += array[i];
            }
        }
    }

    printf("  -> Streaming concluido.\n");
}

/* =============================================================
   BENCHMARK 2 — Convolucao de Matriz 2D + Thrashing controlado
   ---------------------------------------------------------
   MUDANCA 4: adicionado um segundo array de saida maior para
   criar pressao adicional na cache e forcao o Hawkeye a tomar
   decisoes mais dificeis. Tambem foram separados os PCs de
   leitura (201,202,203) e escrita (204) para o preditor ter
   sinais mais ricos.

   MUDANCA 5: largura reduzida de 128 para 64 elementos.
   Linhas menores aumentam o numero de linhas de cache
   necessarias por iteracao da janela, tornando o problema
   de substituicao mais interessante.
   ============================================================= */
void run_matrix_conv(int *img, int *out, FILE *trace)
{
    printf("Gerando trace: Matriz 2D - Convolucao...\n");

    void *base = (void *)img;

    /* MUDANCA 5: width=64 (era 128) — mais linhas, mais pressao na cache */
    int width = 64;
    int height = (int)(ARRAY_SIZE / (size_t)width);

    for (int y = 1; y < height - 1; y++)
    {
        for (int x = 1; x < width - 1; x++)
        {
            /* Leituras da janela 3x1 — tendem a ter reuso (cache-friendly) */
            fprintf(trace, "%u %lu\n", NORM(&img[(y - 1) * width + x], base), 201UL);
            fprintf(trace, "%u %lu\n", NORM(&img[y * width + x], base), 202UL);
            fprintf(trace, "%u %lu\n", NORM(&img[(y + 1) * width + x], base), 203UL);

            /* Escrita do resultado — sem reuso imediato (cache-averse) */
            fprintf(trace, "%u %lu\n", NORM(&out[y * width + x], base), 204UL);

            out[y * width + x] =
                img[(y - 1) * width + x] +
                img[y * width + x] +
                img[(y + 1) * width + x];
        }
    }

    printf("  -> Convolucao concluida.\n");
}

/* =============================================================
   BENCHMARK 3 — Linked List com Hot Registers
   ---------------------------------------------------------
   MUDANCA 6: adicionado um "registro quente" acessado a cada
   no da lista. Isso cria dois padroes bem distintos:
     PC=301: pointer chasing irregular — cache-averse
     PC=302: next pointer — acessado sequencialmente, misto
     PC=303: registro quente — altamente reutilizado, friendly
   O preditor Hawkeye consegue aprender que PC=303 merece ficar
   na cache mesmo quando a lista tenta expulsa-lo.
   ============================================================= */
void run_linked_list(Node *nodes, int count, FILE *trace)
{
    printf("Gerando trace: Linked List + Hot Register...\n");

    void *base = (void *)nodes;
    Node *curr = nodes;

    /* MUDANCA 6: registro quente separado — acessado em todo no */
    volatile int hot_register = 0;

    for (int i = 0; i < count * 50; i++)
    {
        /* PC=301: acesso ao dado do no atual — pointer chasing */
        fprintf(trace, "%u %lu\n", NORM(&curr->data, base), 301UL);
        curr->data += i;

        /* PC=302: leitura do ponteiro next para avancar */
        fprintf(trace, "%u %lu\n", NORM(&curr->next, base), 302UL);

        /* PC=303: acesso ao registro quente — reutilizado em todo no
           Offset fixo a partir da base para normalizar o endereco */
        fprintf(trace, "%u %lu\n", (unsigned int)(count * sizeof(Node)), 303UL);
        hot_register += curr->data;

        curr = curr->next;
    }

    (void)hot_register;
    printf("  -> Linked list concluida.\n");
}

/* =============================================================
   BENCHMARK 4 — Pattern Search com PCs distintos
   ---------------------------------------------------------
   MUDANCA 7: adicionado pseudo-PC separado para o acesso
   de leitura atual (PC=401) vs acesso de comparacao anterior
   (PC=402). O acesso atual e quase sequencial (tende a ser
   averse pois raramente reutiliza). O acesso anterior tem
   localidade espacial curta (tende a ser friendly).
   Isso da ao preditor sinais mais ricos do que um PC unico.

   MUDANCA 8: loop externo comeca em 512 (era 1024) para
   gerar mais acessos e dar mais tempo ao preditor convergir.
   ============================================================= */
void run_pattern_search(uint8_t *blob, int size, FILE *trace)
{
    printf("Gerando trace: Pattern Search...\n");

    void *base = (void *)blob;

    int inner_limit = 16;

    /* MUDANCA 8: comeca em 512 para gerar mais acessos */
    for (int i = 512; i < size; i++)
    {
        for (int j = 1; j < inner_limit; j++)
        {
            /* PC=401: leitura do byte atual — quase sequencial, averse */
            fprintf(trace, "%u %lu\n", NORM(&blob[i], base), 401UL);

            /* PC=402: leitura do byte anterior — localidade curta, friendly */
            fprintf(trace, "%u %lu\n", NORM(&blob[i - j], base), 402UL);

            if (blob[i] == blob[i - j])
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
    printf("  L2 referencia : %d KB\n", L2_SIZE_BYTES / 1024);
    printf("  Array size    : %d KB (1.5x L2)\n",
           (int)(ARRAY_SIZE * sizeof(int) / 1024));
    printf("========================================\n");
    printf("1. Streaming + HotSet  (melhor para Hawkeye)\n");
    printf("2. Matrix Convolution\n");
    printf("3. Linked List + Hot Register\n");
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

    int *big_array = (int *)calloc(ARRAY_SIZE, sizeof(int));
    int *out_array = (int *)calloc(ARRAY_SIZE, sizeof(int));
    uint8_t *blob = (uint8_t *)malloc(L2_SIZE_BYTES * 2);
    Node *nodes = (Node *)malloc(8000 * sizeof(Node));

    if (!big_array || !out_array || !blob || !nodes)
    {
        printf("Erro de alocacao de memoria!\n");
        free(big_array);
        free(out_array);
        free(blob);
        free(nodes);
        return 1;
    }

    /* linked list circular */
    for (int i = 0; i < 7999; i++)
        nodes[i].next = &nodes[i + 1];
    nodes[7999].next = &nodes[0];

    /* blob com valores variados */
    for (int i = 0; i < L2_SIZE_BYTES * 2; i++)
        blob[i] = (uint8_t)(i % 251);

    while (choice != 0)
    {
        print_menu();
        if (scanf("%d", &choice) != 1)
            break;

        FILE *trace = NULL;

        switch (choice)
        {
        case 1:
            trace = fopen("trace_streaming.txt", "w");
            if (!trace)
            {
                printf("Erro ao abrir arquivo!\n");
                break;
            }
            run_streaming(big_array, &hot_val, trace);
            fclose(trace);
            printf("Trace salvo em: trace_streaming.txt\n");
            break;

        case 2:
            trace = fopen("trace_conv.txt", "w");
            if (!trace)
            {
                printf("Erro ao abrir arquivo!\n");
                break;
            }
            run_matrix_conv(big_array, out_array, trace);
            fclose(trace);
            printf("Trace salvo em: trace_conv.txt\n");
            break;

        case 3:
            trace = fopen("trace_linkedlist.txt", "w");
            if (!trace)
            {
                printf("Erro ao abrir arquivo!\n");
                break;
            }
            run_linked_list(nodes, 8000, trace);
            fclose(trace);
            printf("Trace salvo em: trace_linkedlist.txt\n");
            break;

        case 4:
            trace = fopen("trace_pattern.txt", "w");
            if (!trace)
            {
                printf("Erro ao abrir arquivo!\n");
                break;
            }
            run_pattern_search(blob, L2_SIZE_BYTES * 2, trace);
            fclose(trace);
            printf("Trace salvo em: trace_pattern.txt\n");
            break;

        case 5:
            trace = fopen("trace_streaming.txt", "w");
            if (trace)
            {
                run_streaming(big_array, &hot_val, trace);
                fclose(trace);
            }

            trace = fopen("trace_conv.txt", "w");
            if (trace)
            {
                run_matrix_conv(big_array, out_array, trace);
                fclose(trace);
            }

            trace = fopen("trace_linkedlist.txt", "w");
            if (trace)
            {
                run_linked_list(nodes, 8000, trace);
                fclose(trace);
            }

            trace = fopen("trace_pattern.txt", "w");
            if (trace)
            {
                run_pattern_search(blob, L2_SIZE_BYTES * 2, trace);
                fclose(trace);
            }

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