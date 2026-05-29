// =============================================================================
// cache_l2.v
// -----------------------------------------------------------------------------
// Cache L2 unificada - traducao da CacheUnificada do seu cache.h.
//
// PARAMETROS (do cache.h):
//   CACHE_UNIFICADA_SIZE_BYTES = 32768
//   BLOCK_SIZE_UNIFICADA_BYTES = 64     -> offset = 6 bits  (2^6 = 64)
//   ASSOCIATIVITY_UNIFICADA    = 8      -> 8 vias
//   NUM_LINES_UNIFICADA = 32768/64 = 512
//   NUM_SETS_UNIFICADA  = 512/8    = 64 -> indice = 6 bits  (2^6 = 64)
//   tag = 32 - 6 - 6 = 20 bits
//
// DUAS DECISOES DE ARQUITETURA (conforme combinado):
//
//  (1) MODELO FSM (multi-ciclo), NAO single-cycle.
//      Diferente da L1, a L2 e uma maquina de estados. Por que? Porque quando
//      o Hawkeye do seu colega for plugado, a politica pode levar varios ciclos
//      para responder qual via despejar (o OPTgen dele e multi-ciclo). Entao
//      desenhamos a L2 ja preparada para "esperar a politica responder".
//      Estados: IDLE -> LOOKUP -> (HIT_DONE | NEED_VICTIM -> ALLOCATE) -> DONE.
//
//  (2) INTERFACE DE POLITICA ABERTA.
//      A L2 NAO decide sozinha quem despejar. Ela expoe sinais para um modulo
//      externo de politica e recebe de volta a via vitima. Hoje ligamos um
//      LRU simples (placeholder); seu colega troca pelo hawkeye_top depois,
//      SEM mexer neste arquivo.
//
// O QUE ARMAZENA (igual ao C, sem dados reais):
//   - valid[set][via], tag[set][via]  : estado das linhas
//   - hit_count / miss_count          : contadores
//   metadados de substituicao (idade LRU, ou estado Hawkeye) ficam NO MODULO
//   DE POLITICA, nao aqui. Isso e proposital: mantem a L2 agnostica.
// =============================================================================

`timescale 1ns/1ps

module cache_l2 #(
    parameter ADDR_WIDTH  = 32,
    parameter OFFSET_BITS = 6,    // log2(64 bytes por bloco)
    parameter INDEX_BITS  = 6,    // log2(64 conjuntos)
    parameter NUM_SETS    = 64,
    parameter TAG_BITS    = 20,   // 32 - 6 - 6
    parameter WAYS        = 8,    // associatividade
    parameter WAY_BITS    = 3     // log2(8) = bits para indexar uma via
)(
    input  wire                  clk,
    input  wire                  rst,

    // ------ Interface de requisicao (handshake simples) ------
    // O testbench (ou a L1, depois) poe req_valid=1 com endereco e pc.
    // A L2 responde com 'done' por 1 ciclo quando termina, junto de hit/miss.
    input  wire                  req_valid,
    input  wire [ADDR_WIDTH-1:0] req_addr,
    input  wire [ADDR_WIDTH-1:0] req_pc,     // pseudo_pc (usado pela politica)
    output reg                   done,       // pulso: acesso concluido
    output reg                   hit,        // resultado do acesso
    output reg                   miss,

    // ======================================================================
    // INTERFACE DE POLITICA (o "contrato" com o Hawkeye do colega)
    // ----------------------------------------------------------------------
    // SAIDAS da L2 para o modulo de politica:
    output reg  [INDEX_BITS-1:0] pol_set,       // conjunto sendo acessado
    output reg  [ADDR_WIDTH-1:0] pol_pc,        // pc do acesso
    output reg                   pol_access,    // pulso: houve um acesso
    output reg                   pol_hit,       // o acesso foi hit?
    output reg  [WAY_BITS-1:0]   pol_hit_way,   // se hit, em qual via
    output reg                   pol_need_victim,// pulso: preciso de uma vitima
    // ENTRADA vinda do modulo de politica:
    input  wire [WAY_BITS-1:0]   pol_victim_way, // via que a politica mandou despejar
    // ======================================================================

    // ------ Contadores ------
    output reg  [31:0]           hit_count,
    output reg  [31:0]           miss_count
);

    // =========================================================================
    // Decomposicao do endereco (offset/index/tag) - so fios, igual a L1.
    // =========================================================================
    wire [INDEX_BITS-1:0] index = req_addr[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
    wire [TAG_BITS-1:0]   tag   = req_addr[ADDR_WIDTH-1 : OFFSET_BITS + INDEX_BITS];

    // =========================================================================
    // Armazenamento: arrays 2D [conjunto][via].
    // Em Verilog-2001, arrays multidimensionais de reg sao validos para
    // simulacao/sintese no Icarus. Cada elemento e o valid/tag de uma via.
    // =========================================================================
    reg                valid_arr [0:NUM_SETS-1][0:WAYS-1];
    reg [TAG_BITS-1:0] tag_arr   [0:NUM_SETS-1][0:WAYS-1];

    // =========================================================================
    // Busca combinacional em paralelo nas 8 vias.
    // Geramos um vetor hit_vec de 8 bits (1 bit por via). Em hardware, sao
    // 8 comparadores operando ao mesmo tempo. O laco abaixo esta dentro de
    // always @(*) - ele NAO e sequencial no tempo, e apenas uma forma compacta
    // de descrever 8 comparadores identicos (o sintetizador "desenrola" o laco).
    // =========================================================================
    // NOTA sobre warnings do Icarus ("@* is sensitive to all 512 words..."):
    // Sao BENIGNOS. O Icarus apenas avisa que, como lemos valid_arr[index][..]
    // dentro de um @(*), ele reavalia o bloco se QUALQUER palavra do array mudar
    // (em vez de so a linha 'index'). Nao afeta correcao nem sintese; e so uma
    // questao de eficiencia da simulacao. Se for exigido zero-warning, basta
    // copiar a linha [index] para um vetor local antes da busca - refatoracao
    // mecanica. Mantido assim por clareza didatica.
    reg [WAYS-1:0]     hit_vec;     // hit_vec[w] = 1 se a via w deu hit
    reg                any_hit;     // OR de todos os bits de hit_vec
    reg [WAY_BITS-1:0] hit_way_idx; // indice da via que deu hit

    integer w;
    always @(*) begin
        hit_vec     = {WAYS{1'b0}};
        any_hit     = 1'b0;
        hit_way_idx = {WAY_BITS{1'b0}};
        for (w = 0; w < WAYS; w = w + 1) begin
            if (valid_arr[index][w] && (tag_arr[index][w] == tag)) begin
                hit_vec[w]  = 1'b1;
                any_hit     = 1'b1;
                hit_way_idx = w[WAY_BITS-1:0];
            end
        end
    end

    // Detecta primeira via invalida (preenchemos vazias antes de despejar).
    reg                has_invalid;
    reg [WAY_BITS-1:0] invalid_way;
    integer k;
    always @(*) begin
        has_invalid = 1'b0;
        invalid_way = {WAY_BITS{1'b0}};
        for (k = WAYS-1; k >= 0; k = k - 1) begin
            if (!valid_arr[index][k]) begin
                has_invalid = 1'b1;
                invalid_way = k[WAY_BITS-1:0];
            end
        end
    end

    // =========================================================================
    // FSM: estados do acesso.
    // -------------------------------------------------------------------------
    //  IDLE        : espera req_valid.
    //  LOOKUP      : busca foi feita (combinacional); decide hit ou miss.
    //                Em hit: vai direto finalizar. Em miss: pede vitima.
    //  WAIT_VICTIM : aguarda a politica devolver a vitima. Hoje o LRU responde
    //                no mesmo ciclo, mas deixamos um estado dedicado para,
    //                quando o Hawkeye multi-ciclo entrar, bastar esperar mais
    //                ciclos aqui (e so adicionar um sinal pol_victim_valid).
    //  ALLOCATE    : instala o bloco na via (invalida ou vitima).
    //  FINISH      : pulsa done/hit/miss por 1 ciclo e volta a IDLE.
    // =========================================================================
    localparam IDLE        = 3'd0;
    localparam LOOKUP      = 3'd1;
    localparam WAIT_VICTIM = 3'd2;
    localparam ALLOCATE    = 3'd3;
    localparam FINISH      = 3'd4;

    reg [2:0] estado;

    // registradores que "congelam" o acesso enquanto a FSM trabalha
    reg [INDEX_BITS-1:0] cur_index;
    reg [TAG_BITS-1:0]   cur_tag;
    reg                  cur_hit;
    reg [WAY_BITS-1:0]   cur_hit_way;
    reg [WAY_BITS-1:0]   target_way;   // via onde vamos instalar (miss)

    integer s, v;
    always @(posedge clk) begin
        if (rst) begin
            estado          <= IDLE;
            done            <= 1'b0;
            hit             <= 1'b0;
            miss            <= 1'b0;
            hit_count       <= 32'd0;
            miss_count      <= 32'd0;
            pol_access      <= 1'b0;
            pol_need_victim <= 1'b0;
            pol_hit         <= 1'b0;
            // zera armazenamento (igual inicializa_cache_unificada)
            for (s = 0; s < NUM_SETS; s = s + 1)
                for (v = 0; v < WAYS; v = v + 1) begin
                    valid_arr[s][v] <= 1'b0;
                    tag_arr[s][v]   <= {TAG_BITS{1'b0}};
                end
        end
        else begin
            // por padrao, pulsos ficam baixos (so sobem 1 ciclo quando preciso)
            done            <= 1'b0;
            pol_access      <= 1'b0;
            pol_need_victim <= 1'b0;

            case (estado)
                // ---------------------------------------------------------
                IDLE: begin
                    hit  <= 1'b0;
                    miss <= 1'b0;
                    if (req_valid) begin
                        // congela o acesso atual
                        cur_index   <= index;
                        cur_tag     <= tag;
                        cur_hit     <= any_hit;
                        cur_hit_way <= hit_way_idx;
                        // informa a politica que houve um acesso
                        pol_set     <= index;
                        pol_pc      <= req_pc;
                        pol_hit     <= any_hit;
                        pol_hit_way <= hit_way_idx;
                        pol_access  <= 1'b1;       // pulso de acesso
                        estado      <= LOOKUP;
                    end
                end
                // ---------------------------------------------------------
                LOOKUP: begin
                    if (cur_hit) begin
                        // HIT: nao precisa de vitima, contabiliza e finaliza
                        hit_count <= hit_count + 32'd1;
                        estado    <= FINISH;
                        hit       <= 1'b1;
                        miss      <= 1'b0;
                    end
                    else begin
                        // MISS: contabiliza e decide onde instalar
                        miss_count <= miss_count + 32'd1;
                        if (has_invalid) begin
                            // ha via livre: instala nela, sem pedir vitima
                            target_way <= invalid_way;
                            estado     <= ALLOCATE;
                        end
                        else begin
                            // set cheio: pede vitima a politica
                            pol_need_victim <= 1'b1;   // pulso
                            estado          <= WAIT_VICTIM;
                        end
                        hit  <= 1'b0;
                        miss <= 1'b1;
                    end
                end
                // ---------------------------------------------------------
                WAIT_VICTIM: begin
                    // A politica LRU placeholder responde combinacionalmente,
                    // entao pol_victim_way ja esta valido aqui. Quando o
                    // Hawkeye multi-ciclo entrar, este estado podera esperar
                    // um 'pol_victim_valid' antes de seguir.
                    target_way <= pol_victim_way;
                    estado     <= ALLOCATE;
                end
                // ---------------------------------------------------------
                ALLOCATE: begin
                    // instala o novo bloco na via alvo
                    valid_arr[cur_index][target_way] <= 1'b1;
                    tag_arr[cur_index][target_way]   <= cur_tag;
                    estado <= FINISH;
                end
                // ---------------------------------------------------------
                FINISH: begin
                    done   <= 1'b1;     // pulso de conclusao
                    estado <= IDLE;
                end
                // ---------------------------------------------------------
                default: estado <= IDLE;
            endcase
        end
    end

endmodule
// ===== fim do cache_l2.v =====
