#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

/* =============================================================
   CONFIGURACOES — ajustadas para a L2 de 32KB do simulador
   =============================================================
   Working set de 4x L2 garante que NENHUMA politica consiga
   manter tudo na cache. Cada bloco do array compete com 4 outros
   pelo mesmo set da L2. LRU vira reativo; Hawkeye pode proteger
   seletivamente baseado no PC.
   ============================================================= */
#define L2_SIZE_BYTES (32 * 1024)
#define ARRAY_SIZE (L2_SIZE_BYTES * 4 / sizeof(int))  /* 4x L2 = 32K ints = 128KB */

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
   BENCHMARK 1 — Streaming + Hot Conflitante
   ---------------------------------------------------------
   16 blocos hot espacados de 4096 bytes — todos no set 0 da L2.
   Associatividade 8 < 16 → LRU faz thrashing no set.
   Hawkeye com PC=102 marcado friendly deve protege-los.
     PC=101: streaming averse (4x L2)
     PC=102: hot region conflitante — friendly
   ============================================================= */
void run_streaming(int *array, FILE *trace)
{
    printf("Gerando trace: Streaming + Hot Conflitante...\n");
    void *base = (void *)array;

    #define HOT_BLOCKS 16
    unsigned int hot_addrs[HOT_BLOCKS];
    unsigned int hot_base = (unsigned int)(ARRAY_SIZE * sizeof(int));
    for (int k = 0; k < HOT_BLOCKS; k++)
        hot_addrs[k] = hot_base + (unsigned int)(k * 4096);

    for (int it = 0; it < 20; it++)
    {
        for (size_t i = 0; i < ARRAY_SIZE; i++)
        {
            /* PC=101: streaming sobre array 4x L2 — averse */
            fprintf(trace, "%u %lu\n", NORM(&array[i], base), 101UL);
            array[i] += (int)i;

            /* PC=102: hot region (16 blocos mesmo set) — friendly */
            if (i % 64 == 0) {
                int k = (int)((i / 64) % HOT_BLOCKS);
                fprintf(trace, "%u %lu\n", hot_addrs[k], 102UL);
            }
        }
    }
    #undef HOT_BLOCKS
    printf("  -> Streaming + Hot Conflitante concluido.\n");
}

/* =============================================================
   BENCHMARK 2 — Convolucao Stride Patologico
   ---------------------------------------------------------
   width=1024 ints = 4096 bytes = 1 ciclo de set da L2.
   Linhas adjacentes caem no MESMO set → conflito direto entre
   y-1, y, y+1. LRU nao consegue manter as 3 simultaneamente.
     PC=201: linha y-1 — ja vista (reuso)
     PC=202: linha y   — vista na iteracao anterior
     PC=203: linha y+1 — primeira vez (sera reusada nas 2 prox)
     PC=204: escrita saida — averse, never-reused
   ============================================================= */
void run_matrix_conv(int *img, int *out, FILE *trace)
{
    printf("Gerando trace: Convolucao Multi-Pass...\n");
    void *base = (void *)img;

    int width = 64;
    int height = 64;
    int passadas = 8;

    if (width * height > (int)ARRAY_SIZE) {
        printf("ERRO: imagem maior que ARRAY_SIZE\n");
        return;
    }

    for (int it = 0; it < passadas; it++)
    {
        for (int y = 1; y < height - 1; y++)
        {
            for (int x = 0; x < width; x++)
            {
                /* PC=201: linha y-1 — reusada nas passadas seguintes (friendly) */
                fprintf(trace, "%u %lu\n", NORM(&img[(y - 1) * width + x], base), 201UL);

                /* PC=202: linha y — reusada nas passadas seguintes (friendly) */
                fprintf(trace, "%u %lu\n", NORM(&img[y * width + x], base), 202UL);

                /* PC=203: linha y+1 — reusada nas passadas seguintes (friendly) */
                fprintf(trace, "%u %lu\n", NORM(&img[(y + 1) * width + x], base), 203UL);

                /* PC=204: escrita de saida em regiao distante — averse, never-reused */
                unsigned int out_addr = (unsigned int)(ARRAY_SIZE * sizeof(int) * 4
                                                       + (y * width + x) * sizeof(int));
                fprintf(trace, "%u %lu\n", out_addr, 204UL);

                out[y * width + x] =
                    img[(y - 1) * width + x] +
                    img[y * width + x] +
                    img[(y + 1) * width + x];
            }
        }
    }
    printf("  -> Convolucao Multi-Pass concluida.\n");
}

/* =============================================================
   BENCHMARK 3 — Linked List Embaralhada com Hot Path
   ---------------------------------------------------------
   Fisher-Yates determinístico destrói localidade espacial.
   Traversal pseudo-aleatório → LRU nao consegue prever nada.
   Hot subset (nos 0..7) revisitado via PC=303 a cada 16 passos.
     PC=301: dado do no — quase sempre averse (cold)
     PC=302: ponteiro next — averse
     PC=303: revisita hot subset — friendly
   ============================================================= */
void run_linked_list(Node *nodes, int count, FILE *trace)
{
    printf("Gerando trace: Linked List Embaralhada (Hot 64)...\n");
    void *base = (void *)nodes;

    /* Fisher-Yates deterministico — destroi locality espacial */
    int *perm = (int *)malloc(count * sizeof(int));
    for (int i = 0; i < count; i++) perm[i] = i;
    unsigned int seed = 12345;
    for (int i = count - 1; i > 0; i--) {
        seed = seed * 1103515245u + 12345u;
        int j = (int)((seed >> 16) % (unsigned)(i + 1));
        int tmp = perm[i]; perm[i] = perm[j]; perm[j] = tmp;
    }
    for (int i = 0; i < count - 1; i++)
        nodes[perm[i]].next = &nodes[perm[i + 1]];
    nodes[perm[count - 1]].next = &nodes[perm[0]];

    int hot_subset_size = 64;
    int total_iter = count * 3;

    Node *curr = &nodes[perm[0]];
    for (int i = 0; i < total_iter; i++)
    {
        /* PC=301: dado do no atual — averse (random cold) */
        fprintf(trace, "%u %lu\n", NORM(&curr->data, base), 301UL);
        curr->data += i;

        /* PC=302: ponteiro next — averse */
        fprintf(trace, "%u %lu\n", NORM(&curr->next, base), 302UL);

        /* PC=303: revisita hot subset a cada 4 acessos — friendly forte */
        if (i % 4 == 0) {
            int hot_idx = (i / 4) % hot_subset_size;
            fprintf(trace, "%u %lu\n", NORM(&nodes[hot_idx].data, base), 303UL);
        }

        curr = curr->next;
    }

    free(perm);
    printf("  -> Linked list concluida.\n");
}

/* =============================================================
   BENCHMARK 4 — Pattern Search Conflitante
   ---------------------------------------------------------
   Tabela de padroes: 24 entradas espacadas por 4096 bytes —
   todas no MESMO set da L2 que parte do blob. 24 > 8-way →
   LRU nao cabe. PC=402 deve ser marcado friendly pelo Hawkeye.
     PC=401: leitura sequencial do blob — averse
     PC=402: lookup tabela conflitante — friendly
     PC=403: comparacao com posicao anterior — semi-friendly
   ============================================================= */
void run_pattern_search(uint8_t *blob, int size, FILE *trace)
{
    printf("Gerando trace: Pattern Search Conflitante...\n");
    void *base = (void *)blob;

    #define PATTERN_ENTRIES 24
    int pattern_offset = size / 2;
    int inner_limit = PATTERN_ENTRIES;
    int step = 64;

    for (int i = 1024; i < size - inner_limit * 64; i += step)
    {
        for (int j = 1; j <= inner_limit; j++)  /* j começa em 1 — evita comparacao trivial blob[i]==blob[i] */
        {
            /* PC=401: leitura sequencial do blob — averse */
            fprintf(trace, "%u %lu\n", NORM(&blob[i], base), 401UL);

            /* PC=402: lookup na tabela conflitante — friendly */
            unsigned int pattern_addr = (unsigned int)(pattern_offset + (j - 1) * 4096);
            fprintf(trace, "%u %lu\n", pattern_addr, 402UL);

            /* PC=403: comparacao com posicao anterior — semi-friendly */
            int back = i - j * 64;
            if (back >= 0)
                fprintf(trace, "%u %lu\n", NORM(&blob[back], base), 403UL);

            /* Match nao-trivial: break esporadico cria variabilidade sem matar o loop */
            if (back >= 0 && blob[i] == blob[back]) {
                blob[i] = (uint8_t)((blob[i] + 1) % 251);
                break;
            }
        }
    }
    #undef PATTERN_ENTRIES
    printf("  -> Pattern search conflitante concluida.\n");
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
    printf("  Array size    : %d KB (4x L2)\n",
           (int)(ARRAY_SIZE * sizeof(int) / 1024));
    printf("========================================\n");
    printf("1. Streaming + Hot Conflitante\n");
    printf("2. Convolucao Stride Patologico\n");
    printf("3. Linked List Embaralhada\n");
    printf("4. Pattern Search Conflitante\n");
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

    int *big_array = (int *)calloc(ARRAY_SIZE, sizeof(int));
    int *out_array = (int *)calloc(ARRAY_SIZE, sizeof(int));
    uint8_t *blob = (uint8_t *)malloc(L2_SIZE_BYTES * 4);
    Node *nodes = (Node *)malloc(32000 * sizeof(Node));

    if (!big_array || !out_array || !blob || !nodes)
    {
        printf("Erro de alocacao de memoria!\n");
        free(big_array);
        free(out_array);
        free(blob);
        free(nodes);
        return 1;
    }

    /* linked list circular com 32000 nos */
    for (int i = 0; i < 31999; i++)
        nodes[i].next = &nodes[i + 1];
    nodes[31999].next = &nodes[0];

    /* blob com valores variados */
    for (int i = 0; i < L2_SIZE_BYTES * 4; i++)
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
            run_streaming(big_array, trace);
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
            run_linked_list(nodes, 32000, trace);
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
            run_pattern_search(blob, L2_SIZE_BYTES * 4, trace);
            fclose(trace);
            printf("Trace salvo em: trace_pattern.txt\n");
            break;

        case 5:
            trace = fopen("trace_streaming.txt", "w");
            if (trace)
            {
                run_streaming(big_array, trace);
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
                run_linked_list(nodes, 32000, trace);
                fclose(trace);
            }

            trace = fopen("trace_pattern.txt", "w");
            if (trace)
            {
                run_pattern_search(blob, L2_SIZE_BYTES * 4, trace);
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
