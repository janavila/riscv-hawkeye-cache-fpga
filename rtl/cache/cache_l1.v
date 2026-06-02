// =============================================================================
// cache_l1.v
// -----------------------------------------------------------------------------
// Cache L1 de dados - traducao direta da CacheDados do cache.h / lru.c.
//
// PARAMETROS (do cache.h):
//   CACHE_DADOS_SIZE_BYTES = 4096
//   BLOCK_SIZE_DADOS_BYTES = 32      -> offset = 5 bits  (2^5 = 32)
//   ASSOCIATIVITY_DADOS    = 2       -> 1 bit de LRU por conjunto
//   NUM_LINES_DADOS = 4096/32 = 128
//   NUM_SETS_DADOS  = 128/2   = 64   -> indice = 6 bits  (2^6 = 64)
//   tag = 32 - 6 - 5 = 21 bits
//
// MODELO DE HARDWARE: single-cycle (combinacional para a busca).
//   - No mesmo ciclo em que um acesso valido chega, o modulo decide hit/miss,
//     escolhe a via (hit ou vitima por LRU) e, na borda de clock, atualiza
//     o armazenamento e os contadores. Isto espelha o comportamento do C,
//     onde cada chamada de consulta_cache_dados resolve tudo de uma vez.
//
// O QUE ESTE MODULO ARMAZENA (igual ao C - sem dados reais):
//   - valid[set][via]      : linha valida?            (LinhaCache.valid)
//   - tag_array[set][via]  : tag armazenada           (LinhaCache.tag)
//   - lru_estado[set]      : ultima via usada (0 ou 1)(SetCacheDados.lru_estado[0])
//   - hits / misses        : contadores               (CacheDados.hits/misses)
//
// IMPORTANTE SOBRE A POLITICA LRU DE 2 VIAS:
//   lru.c faz:
//     atualizaLru: lru_estado[0] = linha_acessada
//     aplicaLru  : vitima = 1 - lru_estado[0]  (despeja a OUTRA via)
//   Ou seja: a via "mais recente" e guardada; a vitima e sempre a outra.
//   Traduzimos exatamente isso.
// =============================================================================

`timescale 1ns/1ps

module cache_l1 #(
    // Parametros com valores default vindos do cache.h. Deixar como parametros
    parameter ADDR_WIDTH   = 32,   // largura do endereco (unsigned int no C)
    parameter OFFSET_BITS  = 5,    // log2(32 bytes por bloco)
    parameter INDEX_BITS   = 6,    // log2(64 conjuntos)
    parameter NUM_SETS     = 64,   // 2^INDEX_BITS
    parameter TAG_BITS     = 21    // ADDR_WIDTH - INDEX_BITS - OFFSET_BITS
)(
    input  wire                  clk,
    input  wire                  rst,        // reset sincrono, ativo alto

    // ------ Interface de requisicao ------
    input  wire                  req_valid,  // 1 = ha um acesso valido neste ciclo
    input  wire [ADDR_WIDTH-1:0] req_addr,   // endereco do acesso

    // ------ Resultado (combinacional, valido no mesmo ciclo) ------
    output wire                  hit,        // 1 = acerto na L1
    output wire                  miss,       // 1 = erro na L1 (= req_valid & ~hit)

    // ------ Contadores (espelham CacheDados.hits / .misses) ------
    output reg  [31:0]           hit_count,
    output reg  [31:0]           miss_count
);

    // =========================================================================
    // 1) DECOMPOSICAO DO ENDERECO
    // -------------------------------------------------------------------------
    // Layout do endereco (do bit mais alto para o mais baixo):
    //   [ TAG (21) | INDICE (6) | OFFSET (5) ]
    // =========================================================================
    wire [OFFSET_BITS-1:0] offset = req_addr[OFFSET_BITS-1 : 0];
    wire [INDEX_BITS-1:0]  index  = req_addr[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
    wire [TAG_BITS-1:0]    tag    = req_addr[ADDR_WIDTH-1 : OFFSET_BITS + INDEX_BITS];
    // (offset nao e usado para hit/miss, mas fica aqui para documentar o layout)

    // =========================================================================
    // 2) ARMAZENAMENTO (os arrays da cache)
    // -------------------------------------------------------------------------
    // Cada array tem NUM_SETS posicoes (uma por conjunto). Como ha 2 vias,
    // declaramos os arrays "por via" (via 0 e via 1) para deixar o paralelismo
    // explicito e o codigo legivel. Poderiamos usar arrays 2D, mas com 2 vias
    // a forma abaixo e mais clara.
    // =========================================================================
    reg                 valid0 [0:NUM_SETS-1];   // valido da via 0
    reg                 valid1 [0:NUM_SETS-1];   // valido da via 1
    reg [TAG_BITS-1:0]  tag0   [0:NUM_SETS-1];   // tag da via 0
    reg [TAG_BITS-1:0]  tag1   [0:NUM_SETS-1];   // tag da via 1
    reg                 lru    [0:NUM_SETS-1];   // ultima via usada (0 ou 1)

    // =========================================================================
    // 3) BUSCA (LOOKUP) - COMBINACIONAL, EM PARALELO NAS 2 VIAS
    // -------------------------------------------------------------------------
    // hit_way0 = a via 0 esta valida E tag bate?
    // hit_way1 = idem para a via 1.
    // =========================================================================
    wire hit_way0 = valid0[index] && (tag0[index] == tag);
    wire hit_way1 = valid1[index] && (tag1[index] == tag);

    wire        lookup_hit = hit_way0 || hit_way1;     // deu hit em alguma via?
    wire        hit_way    = hit_way1;                 // qual via deu hit (0 ou 1)
                                                       // se hit_way1=1 -> via 1, senao via 0

    // Saidas combinacionais. So vale como hit/miss se houver acesso valido.
    assign hit  = req_valid && lookup_hit;
    assign miss = req_valid && !lookup_hit;

    // =========================================================================
    // 4) ESCOLHA DA VIA A ATUALIZAR
    // -------------------------------------------------------------------------
    // - Em hit:  atualizamos a via que deu hit (vira a "mais recente").
    // - Em miss: a vitima e escolhida pelo LRU. Com 2 vias, o lru.c diz:
    //              vitima = 1 - lru_estado[0]
    //            ou seja, a via que NAO foi a ultima usada.
    //            (Se ainda houver via invalida, normalmente preferimos preencher
    //             a invalida primeiro - tratamos isso abaixo para fidelidade.)
    //
    // Se a via 0 esta invalida usamos a 0,
    // senao se a via 1 esta invalida usamos a 1, senao aplicamos LRU.
    // =========================================================================
    wire victim_lru = ~lru[index];          // 1 - lru_estado[0], em 1 bit e o NOT

    wire        has_invalid = !valid0[index] || !valid1[index];
    wire        invalid_way = !valid0[index] ? 1'b0 : 1'b1;  // primeira via invalida

    // via que sera escrita neste acesso (em hit ou em miss)
    wire chosen_way = lookup_hit ? hit_way
                                 : (has_invalid ? invalid_way : victim_lru);

    // =========================================================================
    // 5) ATUALIZACAO SINCRONA (na borda de clock)
    // -------------------------------------------------------------------------
    // Tudo que MUDA ESTADO acontece aqui, com "<=", na borda de subida.
    // Isto inclui: preencher tag/valid numa via (em miss), atualizar o bit LRU
    // (em qualquer acesso valido), e incrementar hit_count/miss_count.
    // =========================================================================
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            // Zera todo o estado.Aqui fazemos para a simulacao comecar limpa, igual ao
            // inicializa_cache_dados do C.
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                valid0[i] <= 1'b0;
                valid1[i] <= 1'b0;
                tag0[i]   <= {TAG_BITS{1'b0}};
                tag1[i]   <= {TAG_BITS{1'b0}};
                lru[i]    <= 1'b0;
            end
            hit_count  <= 32'd0;
            miss_count <= 32'd0;
        end
        else if (req_valid) begin
            // ---- contadores ----
            if (lookup_hit) hit_count  <= hit_count  + 32'd1;
            else            miss_count <= miss_count + 32'd1;

            // ---- em miss, instala o bloco na via escolhida ----
            // (em hit nao mexemos em tag/valid; a linha ja esta la)
            if (!lookup_hit) begin
                if (chosen_way == 1'b0) begin
                    valid0[index] <= 1'b1;
                    tag0[index]   <= tag;
                end else begin
                    valid1[index] <= 1'b1;
                    tag1[index]   <= tag;
                end
            end

            // ---- atualiza LRU: a via acessada vira a "mais recente" ----
            // Espelha atualizaLru: lru_estado[0] = linha_acessada.
            lru[index] <= chosen_way;
        end
    end

endmodule
// ===== fim do cache_l1.v =====
