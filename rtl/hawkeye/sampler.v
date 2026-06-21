//module sampler #(
//    parameter SAMPLER_SETS   = 64,
//    parameter SAMPLER_HIST   = 8,
//    parameter SET_BITS       = 6,
//    parameter POS_BITS       = 3,
//    parameter SIGNATURE_BITS = 8,
//    parameter PC_BITS        = 64,
//    parameter TIME_BITS      = 32,
//    parameter LRU_BITS       = 4
//)(
//    input  wire                         clk,
//    input  wire                         reset,
//
//    /*
//        access_valid permanece na interface por compatibilidade com o top-level,
//        mas a escrita do sampler Ã© comandada apenas por update_enable.
//
//        Motivo:
//        no hawkeye_top, update_enable vem depois de alguns ciclos,
//        quando o controller termina o fluxo de treinamento.
//        Nesse momento, access_valid jÃ¡ pode ter voltado para 0.
//    */
//    input  wire                         access_valid,
//    input  wire                         update_enable,
//
//    input  wire [SET_BITS-1:0]          sample_set,
//    input  wire [SIGNATURE_BITS-1:0]    signature_atual,
//    input  wire [PC_BITS-1:0]           pc_atual,
//    input  wire [TIME_BITS-1:0]         current_time,
//
//    output wire                         sampler_hit,
//    output wire                         sampler_miss,
//    output wire [POS_BITS-1:0]          sampler_pos,
//    output wire [POS_BITS-1:0]          pos_write,
//    output wire [PC_BITS-1:0]           pc_anterior,
//    output wire [TIME_BITS-1:0]         previous_time,
//
//    output wire [SAMPLER_HIST-1:0]      match_vector_debug,
//    output wire [SAMPLER_HIST-1:0]      valid_entries_debug
//);
//
//    localparam [LRU_BITS-1:0] MAX_LRU = {LRU_BITS{1'b1}};
//
//    integer s;
//    integer i;
//
//    reg                         valid_table     [0:SAMPLER_SETS-1][0:SAMPLER_HIST-1];
//    reg [SIGNATURE_BITS-1:0]    signature_table [0:SAMPLER_SETS-1][0:SAMPLER_HIST-1];
//    reg [PC_BITS-1:0]           pc_table        [0:SAMPLER_SETS-1][0:SAMPLER_HIST-1];
//    reg [TIME_BITS-1:0]         time_table      [0:SAMPLER_SETS-1][0:SAMPLER_HIST-1];
//    reg [LRU_BITS-1:0]          lru_table       [0:SAMPLER_SETS-1][0:SAMPLER_HIST-1];
//
//    reg [SAMPLER_HIST-1:0] valid_entries;
//    reg [SAMPLER_HIST*SIGNATURE_BITS-1:0] signature_entries_flat;
//    reg [SAMPLER_HIST*LRU_BITS-1:0]       lru_entries_flat;
//
//    wire [POS_BITS-1:0] victim_pos;
//    wire has_invalid;
//    wire [SAMPLER_HIST-1:0] invalid_vector;
//
//    /*
//        Monta os barramentos achatados do set atual.
//        Esses barramentos alimentam:
//        - sampler_find_unit
//        - sampler_victim_selector
//    */
//    always @(*) begin
//        for (i = 0; i < SAMPLER_HIST; i = i + 1) begin
//            valid_entries[i] =
//                valid_table[sample_set][i];
//
//            signature_entries_flat[i*SIGNATURE_BITS +: SIGNATURE_BITS] =
//                signature_table[sample_set][i];
//
//            lru_entries_flat[i*LRU_BITS +: LRU_BITS] =
//                lru_table[sample_set][i];
//        end
//    end
//
//    /*
//        Procura se a assinatura atual jÃ¡ existe no sampler.
//    */
//    sampler_find_unit #(
//        .SAMPLER_HIST(SAMPLER_HIST),
//        .SIGNATURE_BITS(SIGNATURE_BITS),
//        .POS_BITS(POS_BITS)
//    ) find_unit (
//        .signature_atual(signature_atual),
//        .valid_entries(valid_entries),
//        .signature_entries_flat(signature_entries_flat),
//
//        .sampler_hit(sampler_hit),
//        .sampler_pos(sampler_pos),
//        .match_vector(match_vector_debug)
//    );
//
//    /*
//        Escolhe onde gravar quando a assinatura ainda nÃ£o existe.
//        Prioridade:
//        1. primeira entrada invÃ¡lida;
//        2. se todas vÃ¡lidas, maior LRU.
//    */
//    sampler_victim_selector #(
//        .SAMPLER_HIST(SAMPLER_HIST),
//        .LRU_BITS(LRU_BITS),
//        .POS_BITS(POS_BITS)
//    ) victim_selector (
//        .valid_entries(valid_entries),
//        .lru_entries_flat(lru_entries_flat),
//
//        .victim_pos(victim_pos),
//        .has_invalid(has_invalid),
//        .invalid_vector(invalid_vector)
//    );
//
//    assign sampler_miss = ~sampler_hit;
//
//    /*
//        Se encontrou a assinatura, atualiza a prÃ³pria posiÃ§Ã£o.
//        Se nÃ£o encontrou, usa a vÃ­tima escolhida.
//    */
//    assign pos_write = sampler_hit ? sampler_pos : victim_pos;
//
//    /*
//        Dados anteriores salvos no sampler.
//        SÃ³ fazem sentido quando sampler_hit = 1.
//    */
//    assign pc_anterior =
//        sampler_hit ? pc_table[sample_set][sampler_pos] : {PC_BITS{1'b0}};
//
//    assign previous_time =
//        sampler_hit ? time_table[sample_set][sampler_pos] : {TIME_BITS{1'b0}};
//
//    assign valid_entries_debug = valid_entries;
//
//    /*
//        Escrita/atualizaÃ§Ã£o do sampler.
//
//        CorreÃ§Ã£o importante:
//        usamos apenas update_enable.
//
//        Antes:
//            if (access_valid && update_enable)
//
//        Problema:
//            no hawkeye_top, update_enable chega depois de vÃ¡rios ciclos,
//            quando access_valid jÃ¡ voltou para 0.
//
//        Agora:
//            if (update_enable)
//
//        Assim, quando o controller mandar atualizar, o sampler grava.
//    */
//    always @(posedge clk) begin
//        if (reset) begin
//            for (s = 0; s < SAMPLER_SETS; s = s + 1) begin
//                for (i = 0; i < SAMPLER_HIST; i = i + 1) begin
//                    valid_table[s][i]     <= 1'b0;
//                    signature_table[s][i] <= {SIGNATURE_BITS{1'b0}};
//                    pc_table[s][i]        <= {PC_BITS{1'b0}};
//                    time_table[s][i]      <= {TIME_BITS{1'b0}};
//                    lru_table[s][i]       <= {LRU_BITS{1'b0}};
//                end
//            end
//        end
//        else begin
//            if (update_enable) begin
//                for (i = 0; i < SAMPLER_HIST; i = i + 1) begin
//
//                    /*
//                        PosiÃ§Ã£o escolhida para escrita:
//                        - sampler_pos, se houve hit;
//                        - victim_pos, se houve miss.
//                    */
//                    if (i == pos_write) begin
//                        valid_table[sample_set][i]     <= 1'b1;
//                        signature_table[sample_set][i] <= signature_atual;
//                        pc_table[sample_set][i]        <= pc_atual;
//                        time_table[sample_set][i]      <= current_time;
//                        lru_table[sample_set][i]       <= {LRU_BITS{1'b0}};
//                    end
//
//                    /*
//                        Envelhece as outras entradas vÃ¡lidas do mesmo set.
//                    */
//                    else if (valid_table[sample_set][i]) begin
//                        if (lru_table[sample_set][i] < MAX_LRU)
//                            lru_table[sample_set][i] <= lru_table[sample_set][i] + 1'b1;
//                    end
//                end
//            end
//        end
//    end
//
//endmodule   

`timescale 1ns/1ps

// =============================================================================
// sampler.v
// -----------------------------------------------------------------------------
// Sampler Hawkeye com altsyncram instanciado explicitamente.
//
// Por que instanciar diretamente:
//   O Quartus 13 nao infere RAM quando ha logica combinacional complexa
//   no caminho de escrita (loops for montando vetores). A instanciacao
//   direta de altsyncram garante o uso de blocos embarcados.
//
// Estrutura de memorias:
//   Uma RAM Simple Dual-Port por campo (valid, signature, pc, time, lru).
//   Largura = SAMPLER_HIST * bits_do_campo (todas as vias num unico endereco).
//   Profundidade = SAMPLER_SETS = 64.
//
//   valid_ram     : 64 x  8 bits
//   signature_ram : 64 x 64 bits
//   pc_ram        : 64 x 512 bits  (cascateia blocos automaticamente)
//   time_ram      : 64 x 256 bits
//   lru_ram       : 64 x  32 bits
//
// Pipeline:
//   Ciclo N   : endereo sample_set na porta de leitura (porta B).
//   Ciclo N+1 : dado disponivel; find_unit e victim_selector operam.
//               Sinais de controle registrados para alinhamento.
//   Ciclo N+1 : escrita na porta A com update_enable_r e sample_set_r.
// =============================================================================

module sampler #(
    parameter SAMPLER_SETS   = 64,
    parameter SAMPLER_HIST   = 8,
    parameter SET_BITS       = 6,
    parameter POS_BITS       = 3,
    parameter SIGNATURE_BITS = 8,
    parameter PC_BITS        = 64,
    parameter TIME_BITS      = 32,
    parameter LRU_BITS       = 4
)(
    input  wire                         clk,
    input  wire                         reset,

    input  wire                         access_valid,
    input  wire                         update_enable,

    input  wire [SET_BITS-1:0]          sample_set,
    input  wire [SIGNATURE_BITS-1:0]    signature_atual,
    input  wire [PC_BITS-1:0]           pc_atual,
    input  wire [TIME_BITS-1:0]         current_time,

    output wire                         sampler_hit,
    output wire                         sampler_miss,
    output wire [POS_BITS-1:0]          sampler_pos,
    output wire [POS_BITS-1:0]          pos_write,
    output wire [PC_BITS-1:0]           pc_anterior,
    output wire [TIME_BITS-1:0]         previous_time,

    output wire [SAMPLER_HIST-1:0]      match_vector_debug,
    output wire [SAMPLER_HIST-1:0]      valid_entries_debug
);

    localparam [LRU_BITS-1:0] MAX_LRU = {LRU_BITS{1'b1}};

    // =========================================================================
    // Registradores de pipeline: alinhamento com leitura sincrona da RAM
    // =========================================================================

    reg [SET_BITS-1:0]       sample_set_r;
    reg [SIGNATURE_BITS-1:0] signature_atual_r;
    reg [PC_BITS-1:0]        pc_atual_r;
    reg [TIME_BITS-1:0]      current_time_r;
    reg                      update_enable_r;
    reg                      access_valid_r;

    always @(posedge clk) begin
        if (reset) begin
            sample_set_r      <= {SET_BITS{1'b0}};
            signature_atual_r <= {SIGNATURE_BITS{1'b0}};
            pc_atual_r        <= {PC_BITS{1'b0}};
            current_time_r    <= {TIME_BITS{1'b0}};
            update_enable_r   <= 1'b0;
            access_valid_r    <= 1'b0;
        end
        else begin
            sample_set_r      <= sample_set;
            signature_atual_r <= signature_atual;
            pc_atual_r        <= pc_atual;
            current_time_r    <= current_time;
            update_enable_r   <= update_enable;
            access_valid_r    <= access_valid;
        end
    end

    // =========================================================================
    // Saidas de leitura das RAMs (porta B  leitura sincrona com saida
    // nao-registrada, pois o altsyncram ja registra o endereco internamente
    // com ADDRESS_REG_B = CLOCK0)
    // =========================================================================

    wire [SAMPLER_HIST-1:0]                valid_q;
    wire [SAMPLER_HIST*SIGNATURE_BITS-1:0] signature_q;
    wire [SAMPLER_HIST*PC_BITS-1:0]        pc_q;
    wire [SAMPLER_HIST*TIME_BITS-1:0]      time_q;
    wire [SAMPLER_HIST*LRU_BITS-1:0]       lru_q;

    // =========================================================================
    // Sinais de escrita (porta A)
    // Montados combinacionalmente a partir dos dados lidos (ciclo N+1)
    // e escritos no mesmo ciclo via update_enable_r.
    // =========================================================================

    wire [POS_BITS-1:0]     victim_pos;
    wire                    has_invalid;
    wire [SAMPLER_HIST-1:0] invalid_vector;
    wire                    raw_hit;
    wire [POS_BITS-1:0]     raw_pos;

    assign sampler_hit  = access_valid_r & raw_hit;
    assign sampler_miss = access_valid_r & ~raw_hit;
    assign sampler_pos  = raw_pos;
    assign pos_write    = raw_hit ? raw_pos : victim_pos;

    assign pc_anterior   = raw_hit ? pc_q  [raw_pos*PC_BITS   +: PC_BITS]   : {PC_BITS{1'b0}};
    assign previous_time = raw_hit ? time_q[raw_pos*TIME_BITS +: TIME_BITS] : {TIME_BITS{1'b0}};

    assign valid_entries_debug = valid_q;

    // =========================================================================
    // Find unit
    // =========================================================================

    sampler_find_unit #(
        .SAMPLER_HIST   (SAMPLER_HIST),
        .SIGNATURE_BITS (SIGNATURE_BITS),
        .POS_BITS       (POS_BITS)
    ) find_unit (
        .signature_atual        (signature_atual_r),
        .valid_entries          (valid_q),
        .signature_entries_flat (signature_q),
        .sampler_hit            (raw_hit),
        .sampler_pos            (raw_pos),
        .match_vector           (match_vector_debug)
    );

    // =========================================================================
    // Victim selector
    // =========================================================================

    sampler_victim_selector #(
        .SAMPLER_HIST (SAMPLER_HIST),
        .LRU_BITS     (LRU_BITS),
        .POS_BITS     (POS_BITS)
    ) victim_selector (
        .valid_entries    (valid_q),
        .lru_entries_flat (lru_q),
        .victim_pos       (victim_pos),
        .has_invalid      (has_invalid),
        .invalid_vector   (invalid_vector)
    );

    // =========================================================================
    // Construcao dos dados de escrita (combinacional)
    //
    // Para cada campo, montamos o vetor completo de SAMPLER_HIST vias.
    // A via pos_write recebe os novos dados; as demais mantem ou envelhecem.
    // =========================================================================

    integer w;

    reg [SAMPLER_HIST-1:0]                wr_valid;
    reg [SAMPLER_HIST*SIGNATURE_BITS-1:0] wr_signature;
    reg [SAMPLER_HIST*PC_BITS-1:0]        wr_pc;
    reg [SAMPLER_HIST*TIME_BITS-1:0]      wr_time;
    reg [SAMPLER_HIST*LRU_BITS-1:0]       wr_lru;

    always @(*) begin
        for (w = 0; w < SAMPLER_HIST; w = w + 1) begin
            if (w[POS_BITS-1:0] == pos_write) begin
                wr_valid[w]                                    = 1'b1;
                wr_signature[w*SIGNATURE_BITS +: SIGNATURE_BITS] = signature_atual_r;
                wr_pc       [w*PC_BITS        +: PC_BITS]        = pc_atual_r;
                wr_time     [w*TIME_BITS       +: TIME_BITS]      = current_time_r;
                wr_lru      [w*LRU_BITS        +: LRU_BITS]       = {LRU_BITS{1'b0}};
            end
            else if (valid_q[w]) begin
                wr_valid[w]                                    = 1'b1;
                wr_signature[w*SIGNATURE_BITS +: SIGNATURE_BITS] =
                    signature_q[w*SIGNATURE_BITS +: SIGNATURE_BITS];
                wr_pc   [w*PC_BITS   +: PC_BITS]   = pc_q  [w*PC_BITS   +: PC_BITS];
                wr_time [w*TIME_BITS +: TIME_BITS] = time_q[w*TIME_BITS +: TIME_BITS];
                wr_lru  [w*LRU_BITS  +: LRU_BITS] =
                    (lru_q[w*LRU_BITS +: LRU_BITS] < MAX_LRU)
                    ? lru_q[w*LRU_BITS +: LRU_BITS] + 1'b1
                    : MAX_LRU;
            end
            else begin
                wr_valid[w]                                    = 1'b0;
                wr_signature[w*SIGNATURE_BITS +: SIGNATURE_BITS] =
                    signature_q[w*SIGNATURE_BITS +: SIGNATURE_BITS];
                wr_pc   [w*PC_BITS   +: PC_BITS]   = pc_q  [w*PC_BITS   +: PC_BITS];
                wr_time [w*TIME_BITS +: TIME_BITS] = time_q[w*TIME_BITS +: TIME_BITS];
                wr_lru  [w*LRU_BITS  +: LRU_BITS] = lru_q [w*LRU_BITS  +: LRU_BITS];
            end
        end
    end

    // =========================================================================
    // altsyncram: valid_ram  (8 bits largura, 64 entradas)
    // =========================================================================

    altsyncram #(
        .operation_mode              ("DUAL_PORT"),
        .width_a                     (SAMPLER_HIST),
        .widthad_a                   (SET_BITS),
        .numwords_a                  (SAMPLER_SETS),
        .width_b                     (SAMPLER_HIST),
        .widthad_b                   (SET_BITS),
        .numwords_b                  (SAMPLER_SETS),
        .address_reg_b               ("CLOCK0"),
        .outdata_reg_b               ("UNREGISTERED"),
        .read_during_write_mode_mixed_ports ("OLD_DATA"),
        .ram_block_type              ("AUTO"),
        .intended_device_family      ("Cyclone III")
    ) valid_ram (
        .clock0    (clk),
        .address_a (sample_set_r),
        .data_a    (wr_valid),
        .wren_a    (update_enable_r),
        .address_b (sample_set),
        .q_b       (valid_q),
        .wren_b    (1'b0),
        .q_a       (),
        .aclr0     (1'b0), .aclr1     (1'b0),
        .addressstall_a (1'b0), .addressstall_b (1'b0),
        .byteena_a (1'b1), .byteena_b (1'b1),
        .clock1    (1'b1), .clocken0  (1'b1),
        .clocken1  (1'b1), .clocken2  (1'b1), .clocken3 (1'b1),
        .data_b    ({SAMPLER_HIST{1'b0}}),
        .eccstatus (), .rden_a (1'b1), .rden_b (1'b1)
    );

    // =========================================================================
    // altsyncram: signature_ram  (64 bits largura, 64 entradas)
    // =========================================================================

    altsyncram #(
        .operation_mode              ("DUAL_PORT"),
        .width_a                     (SAMPLER_HIST*SIGNATURE_BITS),
        .widthad_a                   (SET_BITS),
        .numwords_a                  (SAMPLER_SETS),
        .width_b                     (SAMPLER_HIST*SIGNATURE_BITS),
        .widthad_b                   (SET_BITS),
        .numwords_b                  (SAMPLER_SETS),
        .address_reg_b               ("CLOCK0"),
        .outdata_reg_b               ("UNREGISTERED"),
        .read_during_write_mode_mixed_ports ("OLD_DATA"),
        .ram_block_type              ("AUTO"),
        .intended_device_family      ("Cyclone III")
    ) signature_ram (
        .clock0    (clk),
        .address_a (sample_set_r),
        .data_a    (wr_signature),
        .wren_a    (update_enable_r),
        .address_b (sample_set),
        .q_b       (signature_q),
        .wren_b    (1'b0),
        .q_a       (),
        .aclr0     (1'b0), .aclr1     (1'b0),
        .addressstall_a (1'b0), .addressstall_b (1'b0),
        .byteena_a (1'b1), .byteena_b (1'b1),
        .clock1    (1'b1), .clocken0  (1'b1),
        .clocken1  (1'b1), .clocken2  (1'b1), .clocken3 (1'b1),
        .data_b    ({SAMPLER_HIST*SIGNATURE_BITS{1'b0}}),
        .eccstatus (), .rden_a (1'b1), .rden_b (1'b1)
    );

    // =========================================================================
    // altsyncram: pc_ram  (512 bits largura, 64 entradas)
    // =========================================================================

    altsyncram #(
        .operation_mode              ("DUAL_PORT"),
        .width_a                     (SAMPLER_HIST*PC_BITS),
        .widthad_a                   (SET_BITS),
        .numwords_a                  (SAMPLER_SETS),
        .width_b                     (SAMPLER_HIST*PC_BITS),
        .widthad_b                   (SET_BITS),
        .numwords_b                  (SAMPLER_SETS),
        .address_reg_b               ("CLOCK0"),
        .outdata_reg_b               ("UNREGISTERED"),
        .read_during_write_mode_mixed_ports ("OLD_DATA"),
        .ram_block_type              ("AUTO"),
        .intended_device_family      ("Cyclone III")
    ) pc_ram (
        .clock0    (clk),
        .address_a (sample_set_r),
        .data_a    (wr_pc),
        .wren_a    (update_enable_r),
        .address_b (sample_set),
        .q_b       (pc_q),
        .wren_b    (1'b0),
        .q_a       (),
        .aclr0     (1'b0), .aclr1     (1'b0),
        .addressstall_a (1'b0), .addressstall_b (1'b0),
        .byteena_a (1'b1), .byteena_b (1'b1),
        .clock1    (1'b1), .clocken0  (1'b1),
        .clocken1  (1'b1), .clocken2  (1'b1), .clocken3 (1'b1),
        .data_b    ({SAMPLER_HIST*PC_BITS{1'b0}}),
        .eccstatus (), .rden_a (1'b1), .rden_b (1'b1)
    );

    // =========================================================================
    // altsyncram: time_ram  (256 bits largura, 64 entradas)
    // =========================================================================

    altsyncram #(
        .operation_mode              ("DUAL_PORT"),
        .width_a                     (SAMPLER_HIST*TIME_BITS),
        .widthad_a                   (SET_BITS),
        .numwords_a                  (SAMPLER_SETS),
        .width_b                     (SAMPLER_HIST*TIME_BITS),
        .widthad_b                   (SET_BITS),
        .numwords_b                  (SAMPLER_SETS),
        .address_reg_b               ("CLOCK0"),
        .outdata_reg_b               ("UNREGISTERED"),
        .read_during_write_mode_mixed_ports ("OLD_DATA"),
        .ram_block_type              ("AUTO"),
        .intended_device_family      ("Cyclone III")
    ) time_ram (
        .clock0    (clk),
        .address_a (sample_set_r),
        .data_a    (wr_time),
        .wren_a    (update_enable_r),
        .address_b (sample_set),
        .q_b       (time_q),
        .wren_b    (1'b0),
        .q_a       (),
        .aclr0     (1'b0), .aclr1     (1'b0),
        .addressstall_a (1'b0), .addressstall_b (1'b0),
        .byteena_a (1'b1), .byteena_b (1'b1),
        .clock1    (1'b1), .clocken0  (1'b1),
        .clocken1  (1'b1), .clocken2  (1'b1), .clocken3 (1'b1),
        .data_b    ({SAMPLER_HIST*TIME_BITS{1'b0}}),
        .eccstatus (), .rden_a (1'b1), .rden_b (1'b1)
    );

    // =========================================================================
    // altsyncram: lru_ram  (32 bits largura, 64 entradas)
    // =========================================================================

    altsyncram #(
        .operation_mode              ("DUAL_PORT"),
        .width_a                     (SAMPLER_HIST*LRU_BITS),
        .widthad_a                   (SET_BITS),
        .numwords_a                  (SAMPLER_SETS),
        .width_b                     (SAMPLER_HIST*LRU_BITS),
        .widthad_b                   (SET_BITS),
        .numwords_b                  (SAMPLER_SETS),
        .address_reg_b               ("CLOCK0"),
        .outdata_reg_b               ("UNREGISTERED"),
        .read_during_write_mode_mixed_ports ("OLD_DATA"),
        .ram_block_type              ("AUTO"),
        .intended_device_family      ("Cyclone III")
    ) lru_ram (
        .clock0    (clk),
        .address_a (sample_set_r),
        .data_a    (wr_lru),
        .wren_a    (update_enable_r),
        .address_b (sample_set),
        .q_b       (lru_q),
        .wren_b    (1'b0),
        .q_a       (),
        .aclr0     (1'b0), .aclr1     (1'b0),
        .addressstall_a (1'b0), .addressstall_b (1'b0),
        .byteena_a (1'b1), .byteena_b (1'b1),
        .clock1    (1'b1), .clocken0  (1'b1),
        .clocken1  (1'b1), .clocken2  (1'b1), .clocken3 (1'b1),
        .data_b    ({SAMPLER_HIST*LRU_BITS{1'b0}}),
        .eccstatus (), .rden_a (1'b1), .rden_b (1'b1)
    );

endmodule