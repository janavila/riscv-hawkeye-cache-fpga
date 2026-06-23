// =============================================================================
// cache_l2.v
// -----------------------------------------------------------------------------
// Cache L2 unificada - traducao da CacheUnificada do  cache.h.
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
//      o Hawkeye for plugado, a politica pode levar varios ciclos
//      para responder qual via despejar (o OPTgen é multi-ciclo). Entao
//      desenhamos a L2 ja preparada para "esperar a politica responder".
//      Estados: IDLE -> LOOKUP -> (HIT_DONE | NEED_VICTIM -> ALLOCATE) -> DONE.
//
//  (2) INTERFACE DE POLITICA ABERTA.
//      A L2 NAO decide sozinha quem despejar. Ela expoe sinais para um modulo
//      externo de politica e recebe de volta a via vitima. Hoje ligamos um
//      LRU simples (placeholder); Trocamos pelo hawkeye_top depois,
//      SEM mexer neste arquivo.
//
// O QUE ARMAZENA (igual ao C, sem dados reais):
//   - valid[set][via], tag[set][via]  : estado das linhas
//   - hit_count / miss_count          : contadores
//   metadados de substituicao (idade LRU, ou estado Hawkeye) ficam NO MODULO
//   DE POLITICA, nao aqui. Isso e proposital: mantem a L2 agnostica.
// =============================================================================
//
//`timescale 1ns/1ps
//
//module cache_l2 #(
//    parameter ADDR_WIDTH  = 32,
//    parameter OFFSET_BITS = 6,    // log2(64 bytes por bloco)
//    parameter INDEX_BITS  = 6,    // log2(64 conjuntos)
//    parameter NUM_SETS    = 64,
//    parameter TAG_BITS    = 20,   // 32 - 6 - 6
//    parameter WAYS        = 8,    // associatividade
//    parameter WAY_BITS    = 3     // log2(8) = bits para indexar uma via
//)(
//    input  wire                  clk,
//    input  wire                  rst,
//
//    // ------ Interface de requisicao (handshake simples) ------
//    // O testbench (ou a L1, depois) poe req_valid=1 com endereco e pc.
//    // A L2 responde com 'done' por 1 ciclo quando termina, junto de hit/miss.
//    input  wire                  req_valid,
//    input  wire [ADDR_WIDTH-1:0] req_addr,
//    input  wire [ADDR_WIDTH-1:0] req_pc,     // pseudo_pc (usado pela politica)
//    output reg                   done,       // pulso: acesso concluido
//    output reg                   hit,        // resultado do acesso
//    output reg                   miss,
//
//    // ======================================================================
//    // INTERFACE DE POLITICA (o "contrato" com o Hawkeye)
//    // ----------------------------------------------------------------------
//    // SAIDAS da L2 para o modulo de politica:
//    output reg  [INDEX_BITS-1:0] pol_set,       // conjunto sendo acessado
//    output reg  [ADDR_WIDTH-1:0] pol_pc,        // pc do acesso
//    output reg                   pol_access,    // pulso: houve um acesso
//    output reg                   pol_hit,       // o acesso foi hit?
//    output reg  [WAY_BITS-1:0]   pol_hit_way,   // se hit, em qual via
//    output reg                   pol_need_victim,// pulso: preciso de uma vitima
//    output reg  [ADDR_WIDTH-1:0]  pol_addr,
//    output reg                   pol_fill,
//    output reg  [WAY_BITS-1:0]   pol_fill_way,
//    // ENTRADA vinda do modulo de politica:
//    input  wire [WAY_BITS-1:0]   pol_victim_way, // via que a politica mandou despejar
//    input  wire                  pol_victim_valid, // 1 quando pol_victim_way esta valido
//    // ======================================================================
//
//    // ------ Contadores ------
//    output reg  [31:0]           hit_count,
//    output reg  [31:0]           miss_count
//);
//
//    // =========================================================================
//    // Decomposicao do endereco (offset/index/tag) - so fios, igual a L1.
//    // =========================================================================
//    wire [INDEX_BITS-1:0] index = req_addr[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
//    wire [TAG_BITS-1:0]   tag   = req_addr[ADDR_WIDTH-1 : OFFSET_BITS + INDEX_BITS];
//
//    // =========================================================================
//    // Armazenamento: arrays 2D [conjunto][via].
//    // Em Verilog-2001, arrays multidimensionais de reg sao validos para
//    // simulacao/sintese no Icarus. Cada elemento e o valid/tag de uma via.
//    // =========================================================================
//    reg                valid_arr [0:NUM_SETS-1][0:WAYS-1];
//    reg [TAG_BITS-1:0] tag_arr   [0:NUM_SETS-1][0:WAYS-1];
//
//    // =========================================================================
//    // Busca combinacional em paralelo nas 8 vias.
//    // Geramos um vetor hit_vec de 8 bits (1 bit por via). Em hardware, sao
//    // 8 comparadores operando ao mesmo tempo. O laco abaixo esta dentro de
//    // always @(*) - ele NAO e sequencial no tempo, e apenas uma forma compacta
//    // de descrever 8 comparadores identicos (o sintetizador "desenrola" o laco).
//    // =========================================================================
//    reg [WAYS-1:0]     hit_vec;     // hit_vec[w] = 1 se a via w deu hit
//    reg                any_hit;     // OR de todos os bits de hit_vec
//    reg [WAY_BITS-1:0] hit_way_idx; // indice da via que deu hit
//
//    integer w;
//    always @(*) begin
//        hit_vec     = {WAYS{1'b0}};
//        any_hit     = 1'b0;
//        hit_way_idx = {WAY_BITS{1'b0}};
//        for (w = 0; w < WAYS; w = w + 1) begin
//            if (valid_arr[index][w] && (tag_arr[index][w] == tag)) begin
//                hit_vec[w]  = 1'b1;
//                any_hit     = 1'b1;
//                hit_way_idx = w[WAY_BITS-1:0];
//            end
//        end
//    end
//    // registradores que "congelam" o acesso enquanto a FSM trabalha
//    reg [INDEX_BITS-1:0] cur_index;
//    reg [TAG_BITS-1:0]   cur_tag;
//    reg                  cur_hit;
//    reg [WAY_BITS-1:0]   cur_hit_way;
//    reg [WAY_BITS-1:0]   target_way;   // via onde vamos instalar (miss)
//    // Detecta primeira via invalida usando o acesso congelado.
//    // Importante para FSM multi-ciclo: usa cur_index, nao index direto de req_addr.
//    reg                has_invalid_cur;
//    reg [WAY_BITS-1:0] invalid_way_cur;
//    integer k;
//    always @(*) begin
//        has_invalid_cur = 1'b0;
//        invalid_way_cur = {WAY_BITS{1'b0}};
//    
//        for (k = WAYS-1; k >= 0; k = k - 1) begin
//            if (!valid_arr[cur_index][k]) begin
//                has_invalid_cur = 1'b1;
//                invalid_way_cur = k[WAY_BITS-1:0];
//            end
//        end
//    end
//
//    // =========================================================================
//    // FSM: estados do acesso.
//    // -------------------------------------------------------------------------
//    //  IDLE        : espera req_valid.
//    //  LOOKUP      : busca foi feita (combinacional); decide hit ou miss.
//    //                Em hit: vai direto finalizar. Em miss: pede vitima.
//    //  WAIT_VICTIM : aguarda a politica devolver a vitima. Hoje o LRU responde
//    //                no mesmo ciclo, mas deixamos um estado dedicado para,
//    //                quando o Hawkeye multi-ciclo entrar, bastar esperar mais
//    //                ciclos aqui (e so adicionar um sinal pol_victim_valid).
//    //  ALLOCATE    : instala o bloco na via (invalida ou vitima).
//    //  FINISH      : pulsa done/hit/miss por 1 ciclo e volta a IDLE.
//    // =========================================================================
//    localparam IDLE        = 3'd0;
//    localparam LOOKUP      = 3'd1;
//    localparam WAIT_VICTIM = 3'd2;
//    localparam ALLOCATE    = 3'd3;
//    localparam FINISH      = 3'd4;
//
//    reg [2:0] estado;
//
//    integer s, v;
//    always @(posedge clk) begin
//        if (rst) begin
//            estado          <= IDLE;
//            done            <= 1'b0;
//            hit             <= 1'b0;
//            miss            <= 1'b0;
//            hit_count       <= 32'd0;
//            miss_count      <= 32'd0;
//            pol_access      <= 1'b0;
//            pol_need_victim <= 1'b0;
//            pol_hit         <= 1'b0;
//            pol_addr        <= 0;
//            pol_set     <= 0;
//            pol_pc      <= 0;
//            pol_hit_way <= 0;
//            pol_fill      <= 1'b0;
//            pol_fill_way  <= 0;
//            pol_fill        <= 1'b0;
//            cur_index   <= 0;
//            cur_tag     <= 0;
//            cur_hit     <= 0;
//            cur_hit_way <= 0;
//            target_way  <= 0;
//            // zera armazenamento (igual inicializa_cache_unificada)
//            for (s = 0; s < NUM_SETS; s = s + 1)
//                for (v = 0; v < WAYS; v = v + 1) begin
//                    valid_arr[s][v] <= 1'b0;
//                    tag_arr[s][v]   <= {TAG_BITS{1'b0}};
//                end
//        end
//        else begin
//            // por padrao, pulsos ficam baixos (so sobem 1 ciclo quando preciso)
//            done            <= 1'b0;
//            pol_access      <= 1'b0;
//            pol_need_victim <= 1'b0;
//            pol_fill        <= 1'b0;
//
//            case (estado)
//                // ---------------------------------------------------------
//                IDLE: begin
//                    hit  <= 1'b0;
//                    miss <= 1'b0;
//                    if (req_valid) begin
//                        // congela o acesso atual
//                        cur_index   <= index;
//                        cur_tag     <= tag;
//                        cur_hit     <= any_hit;
//                        cur_hit_way <= hit_way_idx;
//                        // informa a politica que houve um acesso
//                        pol_set     <= index;
//                        pol_pc      <= req_pc;
//                        pol_hit     <= any_hit;
//                        pol_hit_way <= hit_way_idx;
//                        pol_access  <= 1'b1;       // pulso de acesso
//                        estado      <= LOOKUP;
//                        pol_addr <= req_addr;
//                    end
//                end
//                // ---------------------------------------------------------
//                LOOKUP: begin
//                    if (cur_hit) begin
//                        // HIT: nao precisa de vitima, contabiliza e finaliza
//                        hit_count <= hit_count + 32'd1;
//                        estado    <= FINISH;
//                        hit       <= 1'b1;
//                        miss      <= 1'b0;
//                    end
//                    else begin
//                        // MISS: contabiliza e decide onde instalar
//                        miss_count <= miss_count + 32'd1;
//                       if (has_invalid_cur) begin
//                            // ha via livre no set congelado: instala nela, sem pedir vitima
//                            target_way <= invalid_way_cur;
//                            estado     <= ALLOCATE;
//                        end
//                        else begin
//                            // set cheio: pede vitima a politica
//                            pol_need_victim <= 1'b1;   // pulso
//                            estado          <= WAIT_VICTIM;
//                        end
//                        hit  <= 1'b0;
//                        miss <= 1'b1;
//                    end
//                end
//                // ---------------------------------------------------------
//                WAIT_VICTIM: begin
//                    // A politica LRU placeholder responde combinacionalmente,
//                    // entao pol_victim_way ja esta valido aqui. Quando o
//                    // Hawkeye multi-ciclo entrar, este estado podera esperar
//                    // um 'pol_victim_valid' antes de seguir.
//                    if (pol_victim_valid) begin
//                        target_way <= pol_victim_way;
//                        estado     <= ALLOCATE;
//                    end
//                end
//                // ---------------------------------------------------------
//                ALLOCATE: begin
//                    // instala o novo bloco na via alvo
//                    valid_arr[cur_index][target_way] <= 1'b1;
//                    tag_arr[cur_index][target_way]   <= cur_tag;
//
//                    // avisa a politica qual via foi preenchida
//                    pol_fill     <= 1'b1;
//                    pol_fill_way <= target_way;
//                    estado <= FINISH;
//                end
//                // ---------------------------------------------------------
//                FINISH: begin
//                    done   <= 1'b1;     // pulso de conclusao
//                    estado <= IDLE;
//                end
//                // ---------------------------------------------------------
//                default: estado <= IDLE;
//            endcase
//        end
//    end
//
//endmodule
// ===== fim do cache_l2.v =====
//

// =============================================================================
// cache_l2.v
// -----------------------------------------------------------------------------
// Cache L2 unificada com tags/valids em RAM embarcada.
//
// Otimizacao:
// - Antes: valid_arr[set][way] e tag_arr[set][way] viravam registradores.
// - Agora: uma RAM guarda a linha inteira do set.
//
// Cada set guarda todas as vias:
//   line_ram[set] = {valid/tag de todas as vias}
//
// Largura da linha:
//   WAYS * (1 + TAG_BITS)
//   8 * (1 + 20) = 168 bits
//
// Profundidade:
//   NUM_SETS = 64
//
// Total lógico:
//   64 * 168 = 10.752 bits
//
// Observacao:
// - A leitura da RAM e sincrona.
// - Portanto, a L2 ganha um estado READ antes do LOOKUP.
// - O reset nao limpa a RAM diretamente; existe estado INIT que escreve zeros
//   em todos os sets apos o reset.
// =============================================================================
`timescale 1ns/1ps

module cache_l2 #(
    parameter ADDR_WIDTH  = 32,
    parameter OFFSET_BITS = 6,
    parameter INDEX_BITS  = 6,
    parameter NUM_SETS    = 64,
    parameter TAG_BITS    = 20,
    parameter WAYS        = 8,
    parameter WAY_BITS    = 3
)(
    input  wire                  clk,
    input  wire                  rst,

    input  wire                  req_valid,
    input  wire [ADDR_WIDTH-1:0] req_addr,
    input  wire [ADDR_WIDTH-1:0] req_pc,

    output reg                   done,
    output reg                   hit,
    output reg                   miss,

    output reg  [INDEX_BITS-1:0] pol_set,
    output reg  [ADDR_WIDTH-1:0] pol_pc,
    output reg                   pol_access,
    output reg                   pol_hit,
    output reg  [WAY_BITS-1:0]   pol_hit_way,
    output reg                   pol_need_victim,
    output reg  [ADDR_WIDTH-1:0] pol_addr,
    output reg                   pol_fill,
    output reg  [WAY_BITS-1:0]   pol_fill_way,

    input  wire [WAY_BITS-1:0]   pol_victim_way,
    input  wire                  pol_victim_valid,

    output reg  [31:0]           hit_count,
    output reg  [31:0]           miss_count
);

    // =========================================================================
    // Decomposicao do endereco
    // =========================================================================
    wire [INDEX_BITS-1:0] index =
        req_addr[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];

    wire [TAG_BITS-1:0] tag =
        req_addr[ADDR_WIDTH-1 : OFFSET_BITS + INDEX_BITS];

    // =========================================================================
    // Formato da linha da RAM
    // Cada via: {valid(1), tag(TAG_BITS)} = ENTRY_BITS bits
    // Linha completa: WAYS * ENTRY_BITS bits
    // =========================================================================
    localparam ENTRY_BITS = TAG_BITS + 1;
    localparam LINE_BITS  = WAYS * ENTRY_BITS;

    // =========================================================================
    // Registradores do acesso atual
    // =========================================================================
    reg [ADDR_WIDTH-1:0] cur_addr;
    reg [ADDR_WIDTH-1:0] cur_pc;
    reg [INDEX_BITS-1:0] cur_index;
    reg [TAG_BITS-1:0]   cur_tag;
    reg                  cur_hit;
    reg [WAY_BITS-1:0]   cur_hit_way;
    reg [WAY_BITS-1:0]   target_way;

    // =========================================================================
    // FSM
    // =========================================================================
    localparam INIT        = 3'd0;
    localparam IDLE        = 3'd1;
    localparam READ        = 3'd2;
    localparam LOOKUP      = 3'd3;
    localparam WAIT_VICTIM = 3'd4;
    localparam ALLOCATE    = 3'd5;
    localparam FINISH      = 3'd6;

    reg [2:0]            estado;
    reg [INDEX_BITS-1:0] init_addr;

    // =========================================================================
    // Sinais de controle da RAM
    // =========================================================================
    wire [LINE_BITS-1:0] line_q;
    reg                  line_we;
    reg [INDEX_BITS-1:0] line_wr_addr;
    reg [LINE_BITS-1:0]  line_wr_data;
    reg [INDEX_BITS-1:0] line_rd_addr;

    // =========================================================================
    // RAM dual-port da L2
    // Porta A: escrita  |  Porta B: leitura
    // =========================================================================
    altsyncram #(
        .operation_mode                     ("DUAL_PORT"),
        .width_a                            (LINE_BITS),
        .widthad_a                          (INDEX_BITS),
        .numwords_a                         (NUM_SETS),
        .width_b                            (LINE_BITS),
        .widthad_b                          (INDEX_BITS),
        .numwords_b                         (NUM_SETS),
        .address_reg_b                      ("CLOCK0"),
        .outdata_reg_b                      ("UNREGISTERED"),
        .read_during_write_mode_mixed_ports ("OLD_DATA"),
        .ram_block_type                     ("AUTO"),
        .intended_device_family             ("Cyclone III")
    ) l2_line_ram (
        .clock0         (clk),
        .address_a      (line_wr_addr),
        .data_a         (line_wr_data),
        .wren_a         (line_we),
        .q_a            (),
        .address_b      (line_rd_addr),
        .data_b         ({LINE_BITS{1'b0}}),
        .wren_b         (1'b0),
        .q_b            (line_q),
        .aclr0          (1'b0),  .aclr1          (1'b0),
        .addressstall_a (1'b0),  .addressstall_b (1'b0),
        .byteena_a      (1'b1),  .byteena_b      (1'b1),
        .clock1         (1'b1),  .clocken0       (1'b1),
        .clocken1       (1'b1),  .clocken2       (1'b1),
        .clocken3       (1'b1),  .eccstatus      (),
        .rden_a         (1'b1),  .rden_b         (1'b1)
    );

    // =========================================================================
    // Busca combinacional nas vias usando a linha lida da RAM
    // =========================================================================
    reg [WAYS-1:0]     hit_vec;
    reg                any_hit;
    reg [WAY_BITS-1:0] hit_way_idx;
    reg                has_invalid_cur;
    reg [WAY_BITS-1:0] invalid_way_cur;
    reg                way_valid;
    reg [TAG_BITS-1:0] way_tag;

    integer w;

    always @(*) begin
        hit_vec         = {WAYS{1'b0}};
        any_hit         = 1'b0;
        hit_way_idx     = {WAY_BITS{1'b0}};
        has_invalid_cur = 1'b0;
        invalid_way_cur = {WAY_BITS{1'b0}};

        for (w = 0; w < WAYS; w = w + 1) begin
            way_tag   = line_q[w*ENTRY_BITS +: TAG_BITS];
            way_valid = line_q[w*ENTRY_BITS + TAG_BITS];

            if (way_valid && (way_tag == cur_tag)) begin
                hit_vec[w]  = 1'b1;
                any_hit     = 1'b1;
                hit_way_idx = w[WAY_BITS-1:0];
            end

            if (!way_valid && !has_invalid_cur) begin
                has_invalid_cur = 1'b1;
                invalid_way_cur = w[WAY_BITS-1:0];
            end
        end
    end

    // =========================================================================
    // Controle combinacional da RAM (unico bloco always para line_wr_data)
    //
    // CORRECAO: line_wr_data tinha dois drivers (INIT e ALLOCATE em blocos
    // always separados). Unificados aqui num unico always @(*).
    // =========================================================================
    integer u;

    always @(*) begin
        line_we      = 1'b0;
        line_wr_addr = cur_index;
        line_wr_data = line_q;  // default: linha atual (para ALLOCATE sobrescrever via)

        if (estado == INIT) begin
            // Inicializacao: escreve zeros em init_addr
            line_we      = 1'b1;
            line_wr_addr = init_addr;
            line_wr_data = {LINE_BITS{1'b0}};
        end
        else if (estado == ALLOCATE) begin
            // Allocate: copia linha atual e atualiza a via alvo
            line_we      = 1'b1;
            line_wr_addr = cur_index;
            line_wr_data = line_q;  // comeca com a linha atual

            for (u = 0; u < WAYS; u = u + 1) begin
                if (u[WAY_BITS-1:0] == target_way) begin
                    line_wr_data[u*ENTRY_BITS +: TAG_BITS] = cur_tag;
                    line_wr_data[u*ENTRY_BITS + TAG_BITS]  = 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // FSM sequencial
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            estado          <= INIT;
            init_addr       <= {INDEX_BITS{1'b0}};

            done            <= 1'b0;
            hit             <= 1'b0;
            miss            <= 1'b0;

            hit_count       <= 32'd0;
            miss_count      <= 32'd0;

            pol_set         <= {INDEX_BITS{1'b0}};
            pol_pc          <= {ADDR_WIDTH{1'b0}};
            pol_addr        <= {ADDR_WIDTH{1'b0}};
            pol_access      <= 1'b0;
            pol_hit         <= 1'b0;
            pol_hit_way     <= {WAY_BITS{1'b0}};
            pol_need_victim <= 1'b0;
            pol_fill        <= 1'b0;
            pol_fill_way    <= {WAY_BITS{1'b0}};

            cur_addr        <= {ADDR_WIDTH{1'b0}};
            cur_pc          <= {ADDR_WIDTH{1'b0}};
            cur_index       <= {INDEX_BITS{1'b0}};
            cur_tag         <= {TAG_BITS{1'b0}};
            cur_hit         <= 1'b0;
            cur_hit_way     <= {WAY_BITS{1'b0}};
            target_way      <= {WAY_BITS{1'b0}};

            line_rd_addr    <= {INDEX_BITS{1'b0}};
        end
        else begin
            done            <= 1'b0;
            pol_access      <= 1'b0;
            pol_need_victim <= 1'b0;
            pol_fill        <= 1'b0;

            case (estado)

                INIT: begin
                    if (init_addr == NUM_SETS-1) begin
                        init_addr <= {INDEX_BITS{1'b0}};
                        estado    <= IDLE;
                    end
                    else begin
                        init_addr <= init_addr + 1'b1;
                    end
                end

                IDLE: begin
                    hit  <= 1'b0;
                    miss <= 1'b0;

                    if (req_valid) begin
                        cur_addr     <= req_addr;
                        cur_pc       <= req_pc;
                        cur_index    <= index;
                        cur_tag      <= tag;
                        line_rd_addr <= index;
                        estado       <= READ;
                    end
                end

                READ: begin
                    estado <= LOOKUP;
                end

                LOOKUP: begin
                    cur_hit     <= any_hit;
                    cur_hit_way <= hit_way_idx;

                    pol_set     <= cur_index;
                    pol_pc      <= cur_pc;
                    pol_addr    <= cur_addr;
                    pol_hit     <= any_hit;
                    pol_hit_way <= hit_way_idx;
                    pol_access  <= 1'b1;

                    if (any_hit) begin
                        hit_count <= hit_count + 32'd1;
                        hit       <= 1'b1;
                        miss      <= 1'b0;
                        estado    <= FINISH;
                    end
                    else begin
                        miss_count <= miss_count + 32'd1;
                        hit        <= 1'b0;
                        miss       <= 1'b1;

                        if (has_invalid_cur) begin
                            target_way <= invalid_way_cur;
                            estado     <= ALLOCATE;
                        end
                        else begin
                            pol_need_victim <= 1'b1;
                            estado          <= WAIT_VICTIM;
                        end
                    end
                end

                WAIT_VICTIM: begin
                    if (pol_victim_valid) begin
                        target_way <= pol_victim_way;
                        estado     <= ALLOCATE;
                    end
                end

                ALLOCATE: begin
                    // line_we e line_wr_data sao controlados combinacionalmente
                    pol_set      <= cur_index;
                    pol_pc       <= cur_pc;
                    pol_addr     <= cur_addr;
                    pol_fill     <= 1'b1;
                    pol_fill_way <= target_way;
                    estado       <= FINISH;
                end

                FINISH: begin
                    done   <= 1'b1;
                    estado <= IDLE;
                end

                default: estado <= INIT;
            endcase
        end
    end

endmodule   