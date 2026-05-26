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

    /*
        access_valid permanece na interface por compatibilidade com o top-level,
        mas a escrita do sampler é comandada apenas por update_enable.

        Motivo:
        no hawkeye_top, update_enable vem depois de alguns ciclos,
        quando o controller termina o fluxo de treinamento.
        Nesse momento, access_valid já pode ter voltado para 0.
    */
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

    integer s;
    integer i;

    reg                         valid_table     [0:SAMPLER_SETS-1][0:SAMPLER_HIST-1];
    reg [SIGNATURE_BITS-1:0]    signature_table [0:SAMPLER_SETS-1][0:SAMPLER_HIST-1];
    reg [PC_BITS-1:0]           pc_table        [0:SAMPLER_SETS-1][0:SAMPLER_HIST-1];
    reg [TIME_BITS-1:0]         time_table      [0:SAMPLER_SETS-1][0:SAMPLER_HIST-1];
    reg [LRU_BITS-1:0]          lru_table       [0:SAMPLER_SETS-1][0:SAMPLER_HIST-1];

    reg [SAMPLER_HIST-1:0] valid_entries;
    reg [SAMPLER_HIST*SIGNATURE_BITS-1:0] signature_entries_flat;
    reg [SAMPLER_HIST*LRU_BITS-1:0]       lru_entries_flat;

    wire [POS_BITS-1:0] victim_pos;
    wire has_invalid;
    wire [SAMPLER_HIST-1:0] invalid_vector;

    /*
        Monta os barramentos achatados do set atual.
        Esses barramentos alimentam:
        - sampler_find_unit
        - sampler_victim_selector
    */
    always @(*) begin
        for (i = 0; i < SAMPLER_HIST; i = i + 1) begin
            valid_entries[i] =
                valid_table[sample_set][i];

            signature_entries_flat[i*SIGNATURE_BITS +: SIGNATURE_BITS] =
                signature_table[sample_set][i];

            lru_entries_flat[i*LRU_BITS +: LRU_BITS] =
                lru_table[sample_set][i];
        end
    end

    /*
        Procura se a assinatura atual já existe no sampler.
    */
    sampler_find_unit #(
        .SAMPLER_HIST(SAMPLER_HIST),
        .SIGNATURE_BITS(SIGNATURE_BITS),
        .POS_BITS(POS_BITS)
    ) find_unit (
        .signature_atual(signature_atual),
        .valid_entries(valid_entries),
        .signature_entries_flat(signature_entries_flat),

        .sampler_hit(sampler_hit),
        .sampler_pos(sampler_pos),
        .match_vector(match_vector_debug)
    );

    /*
        Escolhe onde gravar quando a assinatura ainda não existe.
        Prioridade:
        1. primeira entrada inválida;
        2. se todas válidas, maior LRU.
    */
    sampler_victim_selector #(
        .SAMPLER_HIST(SAMPLER_HIST),
        .LRU_BITS(LRU_BITS),
        .POS_BITS(POS_BITS)
    ) victim_selector (
        .valid_entries(valid_entries),
        .lru_entries_flat(lru_entries_flat),

        .victim_pos(victim_pos),
        .has_invalid(has_invalid),
        .invalid_vector(invalid_vector)
    );

    assign sampler_miss = ~sampler_hit;

    /*
        Se encontrou a assinatura, atualiza a própria posição.
        Se não encontrou, usa a vítima escolhida.
    */
    assign pos_write = sampler_hit ? sampler_pos : victim_pos;

    /*
        Dados anteriores salvos no sampler.
        Só fazem sentido quando sampler_hit = 1.
    */
    assign pc_anterior =
        sampler_hit ? pc_table[sample_set][sampler_pos] : {PC_BITS{1'b0}};

    assign previous_time =
        sampler_hit ? time_table[sample_set][sampler_pos] : {TIME_BITS{1'b0}};

    assign valid_entries_debug = valid_entries;

    /*
        Escrita/atualização do sampler.

        Correção importante:
        usamos apenas update_enable.

        Antes:
            if (access_valid && update_enable)

        Problema:
            no hawkeye_top, update_enable chega depois de vários ciclos,
            quando access_valid já voltou para 0.

        Agora:
            if (update_enable)

        Assim, quando o controller mandar atualizar, o sampler grava.
    */
    always @(posedge clk) begin
        if (reset) begin
            for (s = 0; s < SAMPLER_SETS; s = s + 1) begin
                for (i = 0; i < SAMPLER_HIST; i = i + 1) begin
                    valid_table[s][i]     <= 1'b0;
                    signature_table[s][i] <= {SIGNATURE_BITS{1'b0}};
                    pc_table[s][i]        <= {PC_BITS{1'b0}};
                    time_table[s][i]      <= {TIME_BITS{1'b0}};
                    lru_table[s][i]       <= {LRU_BITS{1'b0}};
                end
            end
        end
        else begin
            if (update_enable) begin
                for (i = 0; i < SAMPLER_HIST; i = i + 1) begin

                    /*
                        Posição escolhida para escrita:
                        - sampler_pos, se houve hit;
                        - victim_pos, se houve miss.
                    */
                    if (i == pos_write) begin
                        valid_table[sample_set][i]     <= 1'b1;
                        signature_table[sample_set][i] <= signature_atual;
                        pc_table[sample_set][i]        <= pc_atual;
                        time_table[sample_set][i]      <= current_time;
                        lru_table[sample_set][i]       <= {LRU_BITS{1'b0}};
                    end

                    /*
                        Envelhece as outras entradas válidas do mesmo set.
                    */
                    else if (valid_table[sample_set][i]) begin
                        if (lru_table[sample_set][i] < MAX_LRU)
                            lru_table[sample_set][i] <= lru_table[sample_set][i] + 1'b1;
                    end
                end
            end
        end
    end

endmodule   