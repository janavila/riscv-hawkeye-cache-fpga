// =============================================================================
// hawkeye_l2_policy.v
// -----------------------------------------------------------------------------
// Wrapper inicial da politica Hawkeye para a L2.
//
// Etapa atual:
// - Usa RRIP simples como politica de substituicao.
// - Instancia o Hawkeye Predictor.
// - O Predictor decide se o fill entra como friendly ou averse.
// - Ainda NAO usa Sampler nem OPTgen para treinar o Predictor.
// - Treino do Predictor fica desligado nesta etapa.
//
// Ideia:
// - Cada linha da L2 tem um RRPV de 3 bits.
// - Hit  -> RRPV da via = 0.
// - Fill friendly -> RRPV baixo.
// - Fill averse   -> RRPV alto.
// - Vitima -> escolhe primeira via com RRPV = 7.
// - Se nao houver RRPV = 7, envelhece o set ate aparecer uma vitima.
// =============================================================================

`timescale 1ns/1ps
`ifdef HAWKEYE_QUIET
`define HAWKEYE_PRINT if (0) $display
`else
`define HAWKEYE_PRINT $display
`endif

module hawkeye_l2_policy #(
    parameter SET_BITS   = 6,
    parameter NUM_SETS   = 64,
    parameter PC_WIDTH   = 32,
    parameter ADDR_WIDTH = 32,
    parameter WAYS       = 8,
    parameter WAY_BITS   = 3,
    parameter RRPV_BITS  = 3
)(
    input  wire                  clk,
    input  wire                  rst,

    // sinais vindos da L2
    input  wire [SET_BITS-1:0]   pol_set,
    input  wire [PC_WIDTH-1:0]   pol_pc,
    input  wire [ADDR_WIDTH-1:0] pol_addr,
    input  wire                  pol_access,
    input  wire                  pol_hit,
    input  wire [WAY_BITS-1:0]   pol_hit_way,
    input  wire                  pol_need_victim,
    input  wire                  pol_fill,
    input  wire [WAY_BITS-1:0]   pol_fill_way,

    // resposta para a L2
    output reg  [WAY_BITS-1:0]   pol_victim_way,
    output reg                   pol_victim_valid
);

    localparam [RRPV_BITS-1:0] RRPV_MAX      = {RRPV_BITS{1'b1}}; // 7
    localparam [RRPV_BITS-1:0] RRPV_HIT      = 3'd0;
    localparam [RRPV_BITS-1:0] RRPV_FRIENDLY = 3'd2;
    localparam [RRPV_BITS-1:0] RRPV_AVERSE   = 3'd6;

    // tabela RRPV: uma entrada por set/via
    reg [RRPV_BITS-1:0] rrpv_table [0:NUM_SETS-1][0:WAYS-1];

    reg pending_victim;
    reg [SET_BITS-1:0] pending_set;

    integer s;
    integer w;

     // -------------------------------------------------------------------------
    // Hawkeye completo: Predictor + Sampler + OPTgen + Training Controller
    // -------------------------------------------------------------------------
    wire hawkeye_prediction_valid;
    wire hawkeye_friendly;
    wire hawkeye_averse;
    wire hawkeye_training_busy;
    wire hawkeye_training_done;
    
    wire [7:0]  hawkeye_signature_debug;
    wire [5:0]  hawkeye_sample_set_debug;
    wire [31:0] hawkeye_current_time_debug;
    wire [6:0]  hawkeye_current_val_debug;
    wire [6:0]  hawkeye_prev_val_debug;
    wire        hawkeye_sampler_hit_debug;
    wire [2:0]  hawkeye_sampler_pos_debug;
    wire [3:0]  hawkeye_controller_state_debug;
    
    wire [63:0] pc_hawkeye_64;
    wire [63:0] block_addr_hawkeye_64;
    wire        access_miss_hawkeye;
    
    // A L2 usa PC/endereco de 32 bits.
    // O Hawkeye foi parametrizado com 64 bits, entao fazemos zero-extension.
    assign pc_hawkeye_64 = {32'd0, pol_pc};
    
    // IMPORTANTE:
    // pol_addr e endereco em bytes.
    // Como a L2 usa bloco de 64 bytes, removemos os 6 bits de offset.
    // Assim o Hawkeye recebe endereco de bloco, nao endereco de byte.
    assign block_addr_hawkeye_64 = {32'd0, (pol_addr >> 6)};
    
    assign access_miss_hawkeye = pol_access && !pol_hit;
    
    // Guardamos a predicao do acesso atual para usar depois no fill.
    reg pred_friendly_latched;
    reg pred_averse_latched;
    
    hawkeye_top hawkeye_core (
        .clk(clk),
        .reset(rst),
    
        .access_valid(pol_access),
        .pc(pc_hawkeye_64),
        .block_addr(block_addr_hawkeye_64),
        .set_index(pol_set),
        .access_miss(access_miss_hawkeye),
    
        // Capacidade efetiva inicial usada pelo OPTgen para L2 8-way.
        .optgen_cache_size(8'd8),
    
        .prediction_valid(hawkeye_prediction_valid),
        .friendly(hawkeye_friendly),
        .averse(hawkeye_averse),
    
        .training_busy(hawkeye_training_busy),
        .training_done(hawkeye_training_done),
    
        .signature_debug(hawkeye_signature_debug),
        .sample_set_debug(hawkeye_sample_set_debug),
        .current_time_debug(hawkeye_current_time_debug),
        .current_val_debug(hawkeye_current_val_debug),
        .prev_val_debug(hawkeye_prev_val_debug),
        .sampler_hit_debug(hawkeye_sampler_hit_debug),
        .sampler_pos_debug(hawkeye_sampler_pos_debug),
        .controller_state_debug(hawkeye_controller_state_debug)
    );
    // -------------------------------------------------------------------------
    // Logica combinacional para procurar vitima com RRPV maximo no set pendente
    // -------------------------------------------------------------------------
    reg has_rrpv_max;
    reg [WAY_BITS-1:0] rrpv_victim_way;

    always @(*) begin
        has_rrpv_max    = 1'b0;
        rrpv_victim_way = {WAY_BITS{1'b0}};

        for(w = 0; w < WAYS; w = w + 1) begin
            if(rrpv_table[pending_set][w] == RRPV_MAX && !has_rrpv_max) begin
                has_rrpv_max    = 1'b1;
                rrpv_victim_way = w[WAY_BITS-1:0];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Sequencial: atualizacao da politica
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if(rst) begin
            pending_victim        <= 1'b0;
            pending_set           <= {SET_BITS{1'b0}};
            pol_victim_way        <= {WAY_BITS{1'b0}};
            pol_victim_valid      <= 1'b0;

            pred_friendly_latched <= 1'b0;
            pred_averse_latched   <= 1'b0;

            for(s = 0; s < NUM_SETS; s = s + 1) begin
                for(w = 0; w < WAYS; w = w + 1) begin
                    rrpv_table[s][w] <= RRPV_MAX;
                end
            end
        end
        else begin
            // pulso de 1 ciclo
            pol_victim_valid <= 1'b0;
            if(hawkeye_training_done) begin
                `HAWKEYE_PRINT("[HAWKEYE_L2 t=%0t] TRAINING DONE: friendly=%0d averse=%0d sampler_hit=%0d state=%0d",
                         $time,
                         hawkeye_friendly,
                         hawkeye_averse,
                         hawkeye_sampler_hit_debug,
                         hawkeye_controller_state_debug);
            end

            // -------------------------------------------------------------
            // Acesso recebido da L2
            // -------------------------------------------------------------
             if(pol_access) begin
                 `HAWKEYE_PRINT("[HAWKEYE_L2 t=%0t] acesso: set=%0d pc=0x%08h addr=0x%08h hit=%0d hit_way=%0d",
                          $time, pol_set, pol_pc, pol_addr, pol_hit, pol_hit_way);

                                 // Guarda a predicao para usar no fill.
                 // Guarda a predicao gerada pelo hawkeye_top para usar no fill.
                pred_friendly_latched <= hawkeye_friendly;
                pred_averse_latched   <= hawkeye_averse;
                
                `HAWKEYE_PRINT("[HAWKEYE_L2 t=%0t] hawkeye_top: valid=%0d friendly=%0d averse=%0d sampler_hit=%0d state=%0d busy=%0d done=%0d sig=%0d sample_set=%0d time=%0d", $time, hawkeye_prediction_valid, hawkeye_friendly, hawkeye_averse, hawkeye_sampler_hit_debug, hawkeye_controller_state_debug, hawkeye_training_busy, hawkeye_training_done, hawkeye_signature_debug, hawkeye_sample_set_debug, hawkeye_current_time_debug);

                                 // Em hit, a linha foi reutilizada, entao fica protegida.
                 if(pol_hit) begin
                     rrpv_table[pol_set][pol_hit_way] <= RRPV_HIT;

                                     `HAWKEYE_PRINT("[HAWKEYE_L2 t=%0t] RRIP hit update: set=%0d way=%0d rrpv=0",
                              $time, pol_set, pol_hit_way);
                 end
            end             
            // -------------------------------------------------------------
            // Fill confirmado pela L2
            // -------------------------------------------------------------
            if(pol_fill) begin
                if(pred_friendly_latched) begin
                    rrpv_table[pol_set][pol_fill_way] <= RRPV_FRIENDLY;

                    `HAWKEYE_PRINT("[HAWKEYE_L2 t=%0t] fill FRIENDLY: set=%0d way=%0d addr=0x%08h rrpv=%0d",
                             $time, pol_set, pol_fill_way, pol_addr, RRPV_FRIENDLY);
                end
                else begin
                    rrpv_table[pol_set][pol_fill_way] <= RRPV_AVERSE;

                    `HAWKEYE_PRINT("[HAWKEYE_L2 t=%0t] fill AVERSE: set=%0d way=%0d addr=0x%08h rrpv=%0d",
                             $time, pol_set, pol_fill_way, pol_addr, RRPV_AVERSE);
                end
            end

            // -------------------------------------------------------------
            // Pedido de vitima vindo da L2
            // -------------------------------------------------------------
            if(pol_need_victim && !pending_victim) begin
                pending_victim <= 1'b1;
                pending_set    <= pol_set;

                `HAWKEYE_PRINT("[HAWKEYE_L2 t=%0t] pedido de vitima RRIP: set=%0d",
                         $time, pol_set);
            end

            // -------------------------------------------------------------
            // Enquanto ha pedido pendente, tenta encontrar RRPV maximo.
            // Se nao encontrar, envelhece o set.
            // -------------------------------------------------------------
            else if(pending_victim) begin
                if(has_rrpv_max) begin
                    pol_victim_way   <= rrpv_victim_way;
                    pol_victim_valid <= 1'b1;
                    pending_victim   <= 1'b0;

                    `HAWKEYE_PRINT("[HAWKEYE_L2 t=%0t] vitima RRIP pronta: set=%0d way=%0d",
                             $time, pending_set, rrpv_victim_way);
                end
                else begin
                    // Aging: aumenta RRPV de todas as vias do set pendente.
                    for(w = 0; w < WAYS; w = w + 1) begin
                        if(rrpv_table[pending_set][w] < RRPV_MAX)
                            rrpv_table[pending_set][w] <= rrpv_table[pending_set][w] + 1'b1;
                    end

                    `HAWKEYE_PRINT("[HAWKEYE_L2 t=%0t] aging RRIP no set=%0d",
                             $time, pending_set);
                end
            end
        end
    end

endmodule   