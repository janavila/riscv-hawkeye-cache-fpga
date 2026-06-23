// =============================================================================
// tb_hawkeye_proof.v
// -----------------------------------------------------------------------------
// Teste de prova interna do Hawkeye.
//
// Objetivo:
// - Rodar a hierarquia completa.
// - Usar dois PCs com comportamento diferente.
// - Monitorar sinais internos do Hawkeye:
//     sampler_hit
//     training_done
//     predictor_train_enable
//     predictor_train_up/down
//     prediction friendly/averse
//     fill friendly/averse
//
// ATENCAO:
// Este teste usa referencias hierarquicas internas:
//   dut.u_policy.hawkeye_core...
//   dut.u_policy...
//
// Se o nome da instancia da politica no cache_hierarchy_top nao for u_policy,
// troque "dut.u_policy" pelo nome correto.
// =============================================================================

`timescale 1ns/1ps

module tb_hawkeye_proof #(
    parameter TOTAL_ACCESSES  = 60000,
    parameter WARMUP_ACCESSES = 30000,
    parameter REPORT_EVERY    = 10000
);

    reg clk;
    reg rst;

    reg         req_valid;
    reg  [31:0] req_addr;
    reg  [31:0] req_pc;

    wire        done;
    wire        busy;

    wire        resp_l1_hit;
    wire        resp_l1_miss;
    wire        resp_l2_access;
    wire        resp_l2_hit;
    wire        resp_l2_miss;

    wire [31:0] l1_hit_count;
    wire [31:0] l1_miss_count;
    wire [31:0] l2_hit_count;
    wire [31:0] l2_miss_count;

    wire [2:0]  state_debug;

    localparam [31:0] PC_REUSE  = 32'h0000_AAAA;
    localparam [31:0] PC_STREAM = 32'h0000_BBBB;

    integer i;
    integer errors;
    integer timeout_counter;

    integer reuse_idx;
    integer stream_idx;

    reg [31:0] addr;
    reg [31:0] pc;

    reg is_reuse_access;
    reg is_stream_access;

    // =========================================================================
    // Contadores internos observados
    // =========================================================================
    integer pol_access_count;
    integer pol_fill_count;

    integer sampler_hit_count;
    integer training_done_count;
    integer sampler_update_count;

    integer predictor_train_count;
    integer predictor_train_up_count;
    integer predictor_train_down_count;

    integer train_reuse_up;
    integer train_reuse_down;
    integer train_stream_up;
    integer train_stream_down;

    integer pred_reuse_friendly;
    integer pred_reuse_averse;
    integer pred_stream_friendly;
    integer pred_stream_averse;

    integer fill_reuse_friendly;
    integer fill_reuse_averse;
    integer fill_reuse_unknown;

    integer fill_stream_friendly;
    integer fill_stream_averse;
    integer fill_stream_unknown;

    integer verify_pred_reuse_friendly;
    integer verify_pred_reuse_averse;
    integer verify_pred_stream_friendly;
    integer verify_pred_stream_averse;

    integer verify_fill_reuse_friendly;
    integer verify_fill_reuse_averse;
    integer verify_fill_stream_friendly;
    integer verify_fill_stream_averse;


    integer raw_prediction_valid_count;
    integer raw_prediction_friendly_count;
    integer raw_prediction_averse_count;

    integer effective_fill_friendly_count;
    integer effective_fill_averse_count;
    integer effective_fill_unknown_count;
    // =========================================================================
    // DUT
    // =========================================================================
    cache_hierarchy_top dut (
        .clk(clk),
        .rst(rst),

        .req_valid(req_valid),
        .req_addr(req_addr),
        .req_pc(req_pc),

        .done(done),
        .busy(busy),

        .resp_l1_hit(resp_l1_hit),
        .resp_l1_miss(resp_l1_miss),
        .resp_l2_access(resp_l2_access),
        .resp_l2_hit(resp_l2_hit),
        .resp_l2_miss(resp_l2_miss),

        .l1_hit_count(l1_hit_count),
        .l1_miss_count(l1_miss_count),
        .l2_hit_count(l2_hit_count),
        .l2_miss_count(l2_miss_count),

        .state_debug(state_debug)
    );

    // =========================================================================
    // Clock
    // =========================================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================================
    // Padrao de acesso
    // =========================================================================
    task choose_pattern;
        input integer idx;
        output [31:0] out_addr;
        output [31:0] out_pc;
        output out_is_reuse;
        output out_is_stream;

        integer local_reuse_phase;
        integer group_id;
        integer group_pos;
        integer way_pos;

        begin
            /*
                Acessos pares: PC_REUSE
                Acessos impares: PC_STREAM

                Fase de warmup:
                - PC_REUSE fica em 4 enderecos fixos.
                - PC_STREAM sempre endereco novo.

                Fase de verificacao:
                - PC_REUSE usa grupos novos de 4 enderecos, repetidos algumas vezes.
                  Isso força fills novos com PC_REUSE depois do treinamento.
                - PC_STREAM continua sempre endereco novo.
            */

            if ((idx % 2) == 0) begin
                out_is_reuse  = 1'b1;
                out_is_stream = 1'b0;
                out_pc        = PC_REUSE;

                if (idx < WARMUP_ACCESSES) begin
                    case (reuse_idx % 4)
                        0: out_addr = 32'h0000_0000;
                        1: out_addr = 32'h0000_0800;
                        2: out_addr = 32'h0000_1000;
                        default: out_addr = 32'h0000_1800;
                    endcase
                end
                else begin
                    local_reuse_phase = reuse_idx - (WARMUP_ACCESSES / 2);

                    group_id  = local_reuse_phase / 16;
                    group_pos = local_reuse_phase % 16;
                    way_pos   = group_pos % 4;

                    case (way_pos)
                        0: out_addr = 32'h0100_0000 + (group_id * 32'h0001_0000);
                        1: out_addr = 32'h0100_0800 + (group_id * 32'h0001_0000);
                        2: out_addr = 32'h0100_1000 + (group_id * 32'h0001_0000);
                        default: out_addr = 32'h0100_1800 + (group_id * 32'h0001_0000);
                    endcase
                end

                reuse_idx = reuse_idx + 1;
            end
            else begin
                out_is_reuse  = 1'b0;
                out_is_stream = 1'b1;
                out_pc        = PC_STREAM;

                // Streaming sem reuso: endereco novo a cada acesso.
                out_addr = 32'h2000_0000 + (stream_idx * 32'h0000_0040);

                stream_idx = stream_idx + 1;
            end
        end
    endtask

    // =========================================================================
    // Executa acesso
    // =========================================================================
    task do_access;
        input [31:0] a;
        input [31:0] p;

        begin
            @(posedge clk);
            req_addr  <= a;
            req_pc    <= p;
            req_valid <= 1'b1;

            @(posedge clk);
            req_valid <= 1'b0;

            timeout_counter = 0;

            while ((done !== 1'b1) && (timeout_counter < 2000)) begin
                @(posedge clk);
                timeout_counter = timeout_counter + 1;
            end

            if (done !== 1'b1) begin
                $display("[ERRO] TIMEOUT acesso=%0d addr=0x%08h pc=0x%08h state=%0d busy=%0d",
                         i, a, p, state_debug, busy);
                errors = errors + 1;
            end

            @(posedge clk);
        end
    endtask

        // =========================================================================
        // =========================================================================
        // Monitor interno do Hawkeye
        // =========================================================================
        always @(posedge clk) begin
            if (!rst) begin
                #1;
    
                // -------------------------------------------------------------
                // Acesso da politica vindo da L2
                // -------------------------------------------------------------
                if (dut.u_policy.pol_access) begin
                    pol_access_count = pol_access_count + 1;
    
                    if (dut.u_policy.hawkeye_sampler_hit_debug) begin
                        sampler_hit_count = sampler_hit_count + 1;
                    end
    
                    // Predicao no momento do acesso.
                    // Pode continuar zerada porque o predictor em RAM responde depois.
                    // A contagem correta esta no bloco por prediction_valid.
                    if (dut.u_policy.pol_pc == PC_REUSE) begin
                        if (dut.u_policy.hawkeye_friendly)
                            pred_reuse_friendly = pred_reuse_friendly + 1;
    
                        if (dut.u_policy.hawkeye_averse)
                            pred_reuse_averse = pred_reuse_averse + 1;
    
                        if (i >= WARMUP_ACCESSES) begin
                            if (dut.u_policy.hawkeye_friendly)
                                verify_pred_reuse_friendly = verify_pred_reuse_friendly + 1;
    
                            if (dut.u_policy.hawkeye_averse)
                                verify_pred_reuse_averse = verify_pred_reuse_averse + 1;
                        end
                    end
    
                    if (dut.u_policy.pol_pc == PC_STREAM) begin
                        if (dut.u_policy.hawkeye_friendly)
                            pred_stream_friendly = pred_stream_friendly + 1;
    
                        if (dut.u_policy.hawkeye_averse)
                            pred_stream_averse = pred_stream_averse + 1;
    
                        if (i >= WARMUP_ACCESSES) begin
                            if (dut.u_policy.hawkeye_friendly)
                                verify_pred_stream_friendly = verify_pred_stream_friendly + 1;
    
                            if (dut.u_policy.hawkeye_averse)
                                verify_pred_stream_averse = verify_pred_stream_averse + 1;
                        end
                    end
                end
    
                // -------------------------------------------------------------
                // Monitor correto da predicao.
                // Nao depende de pol_access, porque o predictor em RAM responde
                // com atraso.
                // -------------------------------------------------------------
                if (dut.u_policy.hawkeye_prediction_valid) begin
                    raw_prediction_valid_count = raw_prediction_valid_count + 1;
    
                    if (dut.u_policy.hawkeye_friendly)
                        raw_prediction_friendly_count = raw_prediction_friendly_count + 1;
    
                    if (dut.u_policy.hawkeye_averse)
                        raw_prediction_averse_count = raw_prediction_averse_count + 1;
                end
    
                // -------------------------------------------------------------
                // Training done
                // -------------------------------------------------------------
                if (dut.u_policy.hawkeye_training_done) begin
                    training_done_count = training_done_count + 1;
                end
    
                // -------------------------------------------------------------
                // Sampler update
                // -------------------------------------------------------------
                if (dut.u_policy.hawkeye_core.sampler_update_enable) begin
                    sampler_update_count = sampler_update_count + 1;
                end
    
                // -------------------------------------------------------------
                // Treino do predictor
                // -------------------------------------------------------------
                if (dut.u_policy.hawkeye_core.predictor_train_enable) begin
                    predictor_train_count = predictor_train_count + 1;
    
                    if (dut.u_policy.hawkeye_core.predictor_train_up)
                        predictor_train_up_count = predictor_train_up_count + 1;
    
                    if (dut.u_policy.hawkeye_core.predictor_train_down)
                        predictor_train_down_count = predictor_train_down_count + 1;
    
                    if (dut.u_policy.hawkeye_core.pc_train[31:0] == PC_REUSE) begin
                        if (dut.u_policy.hawkeye_core.predictor_train_up)
                            train_reuse_up = train_reuse_up + 1;
    
                        if (dut.u_policy.hawkeye_core.predictor_train_down)
                            train_reuse_down = train_reuse_down + 1;
                    end
    
                    if (dut.u_policy.hawkeye_core.pc_train[31:0] == PC_STREAM) begin
                        if (dut.u_policy.hawkeye_core.predictor_train_up)
                            train_stream_up = train_stream_up + 1;
    
                        if (dut.u_policy.hawkeye_core.predictor_train_down)
                            train_stream_down = train_stream_down + 1;
                    end
                end
    
                // -------------------------------------------------------------
                // Fill classificado pela predicao latched na politica
                // -------------------------------------------------------------
                if (dut.u_policy.pol_fill) begin
                    pol_fill_count = pol_fill_count + 1;
    
                    if (dut.u_policy.pol_pc == PC_REUSE) begin
                        if (dut.u_policy.pred_friendly_latched) begin
                            fill_reuse_friendly = fill_reuse_friendly + 1;
    
                            if (i >= WARMUP_ACCESSES)
                                verify_fill_reuse_friendly = verify_fill_reuse_friendly + 1;
                        end
                        else if (dut.u_policy.pred_averse_latched) begin
                            fill_reuse_averse = fill_reuse_averse + 1;
    
                            if (i >= WARMUP_ACCESSES)
                                verify_fill_reuse_averse = verify_fill_reuse_averse + 1;
                        end
                        else begin
                            fill_reuse_unknown = fill_reuse_unknown + 1;
                        end
                    end
    
                    if (dut.u_policy.pol_pc == PC_STREAM) begin
                        if (dut.u_policy.pred_friendly_latched) begin
                            fill_stream_friendly = fill_stream_friendly + 1;
    
                            if (i >= WARMUP_ACCESSES)
                                verify_fill_stream_friendly = verify_fill_stream_friendly + 1;
                        end
                        else if (dut.u_policy.pred_averse_latched) begin
                            fill_stream_averse = fill_stream_averse + 1;
    
                            if (i >= WARMUP_ACCESSES)
                                verify_fill_stream_averse = verify_fill_stream_averse + 1;
                        end
                        else begin
                            fill_stream_unknown = fill_stream_unknown + 1;
                        end
                    end
    
                    // ---------------------------------------------------------
                    // Monitor do fill efetivo usado pela politica
                    // ---------------------------------------------------------
                    if (dut.u_policy.fill_pred_valid_effective &&
                        dut.u_policy.fill_pred_friendly_effective) begin
                        
                        effective_fill_friendly_count =
                            effective_fill_friendly_count + 1;
                    end
                    else if (dut.u_policy.fill_pred_valid_effective &&
                             dut.u_policy.fill_pred_averse_effective) begin
                            
                        effective_fill_averse_count =
                            effective_fill_averse_count + 1;
                    end
                    else begin
                        effective_fill_unknown_count =
                            effective_fill_unknown_count + 1;
                    end
                end
            end
        end
        // =========================================================================
        // Teste principal
        // =========================================================================
        initial begin
            errors = 0;
    
            rst       = 1'b1;
            req_valid = 1'b0;
            req_addr  = 32'd0;
            req_pc    = 32'd0;
    
            reuse_idx  = 0;
            stream_idx = 0;
    
            pol_access_count = 0;
            pol_fill_count = 0;
    
            sampler_hit_count = 0;
            training_done_count = 0;
            sampler_update_count = 0;
    
            predictor_train_count = 0;
            predictor_train_up_count = 0;
            predictor_train_down_count = 0;
    
            train_reuse_up = 0;
            train_reuse_down = 0;
            train_stream_up = 0;
            train_stream_down = 0;
    
            pred_reuse_friendly = 0;
            pred_reuse_averse = 0;
            pred_stream_friendly = 0;
            pred_stream_averse = 0;
    
            fill_reuse_friendly = 0;
            fill_reuse_averse = 0;
            fill_reuse_unknown = 0;
    
            fill_stream_friendly = 0;
            fill_stream_averse = 0;
            fill_stream_unknown = 0;
    
            verify_pred_reuse_friendly = 0;
            verify_pred_reuse_averse = 0;
            verify_pred_stream_friendly = 0;
            verify_pred_stream_averse = 0;
    
            verify_fill_reuse_friendly = 0;
            verify_fill_reuse_averse = 0;
            verify_fill_stream_friendly = 0;
            verify_fill_stream_averse = 0;
            raw_prediction_valid_count    = 0;
            raw_prediction_friendly_count = 0;
            raw_prediction_averse_count   = 0;
    
            effective_fill_friendly_count = 0;
            effective_fill_averse_count   = 0;
            effective_fill_unknown_count  = 0;
    
            $display("=========================================================");
            $display(" TESTE HAWKEYE PROOF");
            $display(" TOTAL_ACCESSES=%0d", TOTAL_ACCESSES);
            $display(" WARMUP_ACCESSES=%0d", WARMUP_ACCESSES);
            $display(" REPORT_EVERY=%0d", REPORT_EVERY);
            $display("=========================================================");
    
            repeat (10) @(posedge clk);
            rst <= 1'b0;
    
            repeat (100) @(posedge clk);
    
            for (i = 0; i < TOTAL_ACCESSES; i = i + 1) begin
                choose_pattern(i, addr, pc, is_reuse_access, is_stream_access);
                do_access(addr, pc);
    
                if (((i + 1) % REPORT_EVERY) == 0) begin
                    $display("[PROGRESS] %0d/%0d | L1 h/m=%0d/%0d | L2 h/m=%0d/%0d",
                             i + 1, TOTAL_ACCESSES,
                             l1_hit_count, l1_miss_count,
                             l2_hit_count, l2_miss_count);
    
                    $display("  INTERNAL | pol_access=%0d fills=%0d sampler_hit=%0d train_done=%0d train=%0d up=%0d down=%0d",
                             pol_access_count,
                             pol_fill_count,
                             sampler_hit_count,
                             training_done_count,
                             predictor_train_count,
                             predictor_train_up_count,
                             predictor_train_down_count);
    
                    $display("  TRAIN   | reuse up/down=%0d/%0d | stream up/down=%0d/%0d",
                             train_reuse_up,
                             train_reuse_down,
                             train_stream_up,
                             train_stream_down);
    
                    $display("  PRED    | reuse F/A=%0d/%0d | stream F/A=%0d/%0d",
                             pred_reuse_friendly,
                             pred_reuse_averse,
                             pred_stream_friendly,
                             pred_stream_averse);
    
                    $display("  FILL    | reuse F/A/U=%0d/%0d/%0d | stream F/A/U=%0d/%0d/%0d",
                             fill_reuse_friendly,
                             fill_reuse_averse,
                             fill_reuse_unknown,
                             fill_stream_friendly,
                             fill_stream_averse,
                             fill_stream_unknown);
                end
            end
    
            $display("=========================================================");
            $display(" RESULTADO FINAL HAWKEYE PROOF");
            $display(" CPU acessos = %0d", TOTAL_ACCESSES);
            $display("");
            $display(" HIERARQUIA:");
            $display("   L1: hits=%0d misses=%0d soma=%0d",
                     l1_hit_count, l1_miss_count,
                     l1_hit_count + l1_miss_count);
            $display("   L2: hits=%0d misses=%0d soma=%0d",
                     l2_hit_count, l2_miss_count,
                     l2_hit_count + l2_miss_count);
            $display("");
            $display(" INTERNOS:");
            $display("   pol_access=%0d", pol_access_count);
            $display("   pol_fill=%0d", pol_fill_count);
            $display("   sampler_hit=%0d", sampler_hit_count);
            $display("   sampler_update=%0d", sampler_update_count);
            $display("   training_done=%0d", training_done_count);
            $display("   predictor_train=%0d up=%0d down=%0d",
                     predictor_train_count,
                     predictor_train_up_count,
                     predictor_train_down_count);
            $display("");
            $display(" TREINO POR PC:");
            $display("   REUSE  up=%0d down=%0d", train_reuse_up, train_reuse_down);
            $display("   STREAM up=%0d down=%0d", train_stream_up, train_stream_down);
            $display("");
            $display(" PREDICOES:");
            $display("   REUSE  friendly=%0d averse=%0d", pred_reuse_friendly, pred_reuse_averse);
            $display("   STREAM friendly=%0d averse=%0d", pred_stream_friendly, pred_stream_averse);
            $display("");
            $display(" PREDICOES APOS WARMUP:");
            $display("   REUSE  friendly=%0d averse=%0d", verify_pred_reuse_friendly, verify_pred_reuse_averse);
            $display("   STREAM friendly=%0d averse=%0d", verify_pred_stream_friendly, verify_pred_stream_averse);
            $display("");
            $display(" FILLS:");
            $display("   REUSE  friendly=%0d averse=%0d unknown=%0d",
                     fill_reuse_friendly, fill_reuse_averse, fill_reuse_unknown);
            $display("   STREAM friendly=%0d averse=%0d unknown=%0d",
                     fill_stream_friendly, fill_stream_averse, fill_stream_unknown);
            $display("");
            $display(" FILLS APOS WARMUP:");
            $display("   REUSE  friendly=%0d averse=%0d",
                     verify_fill_reuse_friendly, verify_fill_reuse_averse);
            $display("   STREAM friendly=%0d averse=%0d",
                     verify_fill_stream_friendly, verify_fill_stream_averse);
            $display("");
            $display(" PREDICOES RAW POR VALID:");
            $display("   prediction_valid=%0d friendly=%0d averse=%0d",
                     raw_prediction_valid_count,
                     raw_prediction_friendly_count,
                     raw_prediction_averse_count);
    
            $display("");
            $display(" FILLS EFETIVOS:");
            $display("   friendly=%0d averse=%0d unknown=%0d",
                     effective_fill_friendly_count,
                     effective_fill_averse_count,
                     effective_fill_unknown_count);
            $display("=========================================================");
    
            // Sanidade global
            if ((l1_hit_count + l1_miss_count) != TOTAL_ACCESSES) begin
                $display("[ERRO] L1 hits+misses diferente do total.");
                errors = errors + 1;
            end
    
            if ((l2_hit_count + l2_miss_count) != l1_miss_count) begin
                $display("[ERRO] L2 hits+misses diferente dos misses da L1.");
                errors = errors + 1;
            end
    
            if (sampler_update_count == 0) begin
                $display("[ERRO] sampler_update nunca ocorreu.");
                errors = errors + 1;
            end
    
            if (training_done_count == 0) begin
                $display("[ERRO] training_done nunca ocorreu.");
                errors = errors + 1;
            end
    
            if (predictor_train_count == 0) begin
                $display("[ERRO] predictor_train nunca ocorreu.");
                errors = errors + 1;
            end
    
            if (verify_fill_reuse_friendly <= verify_fill_reuse_averse) begin
                $display("[ALERTA] REUSE nao ficou majoritariamente FRIENDLY apos warmup.");
            end
            
            if (verify_fill_stream_averse <= verify_fill_stream_friendly) begin
                $display("[ALERTA] STREAM nao ficou majoritariamente AVERSE apos warmup.");
            end
            
            if (raw_prediction_valid_count == 0) begin
                $display("[ERRO] Predictor nunca gerou prediction_valid.");
                errors = errors + 1;
            end
            
            if ((raw_prediction_friendly_count + raw_prediction_averse_count) == 0) begin
                $display("[ERRO] Predictor gerou valid, mas nunca classificou friendly/averse.");
                errors = errors + 1;
            end
            
            if ((effective_fill_friendly_count + effective_fill_averse_count + effective_fill_unknown_count) != pol_fill_count) begin
                $display("[ERRO] Soma de fills efetivos diferente de pol_fill.");
                errors = errors + 1;
            end
    
            if (errors == 0) begin
                $display("[OK] Teste Hawkeye Proof terminou sem erros estruturais.");
            end
            else begin
                $display("[FALHOU] Teste Hawkeye Proof terminou com %0d erro(s).", errors);
            end
    
            $finish;
        end
    
endmodule  