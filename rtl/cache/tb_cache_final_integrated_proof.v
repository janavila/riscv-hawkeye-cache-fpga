// =============================================================================
// tb_cache_final_integrated_proof.v
// -----------------------------------------------------------------------------
// Teste final integrado ajustado.
//
// FASE 1A - L1 LRU thrashing:
//   - 8 enderecos no mesmo set L1, 3 voltas.
//   - Esperado: todas as voltas com 8 misses.
//
// FASE 1B - L1 LRU controle positivo:
//   - 2 enderecos no mesmo set L1, 3 voltas.
//   - Esperado: primeira volta misses, voltas seguintes hits.
//
// FASE 2 - Warmup L2 Hawkeye:
//   - PC_REUSE usa 4 enderecos fixos.
//   - PC_STREAM usa enderecos crescentes com stride 0x40.
//   - Esse padrao e o mesmo tipo que funcionou no tb_hawkeye_proof,
//     gerando treino down e predicoes averse para streaming.
//
// FASE 3 - Prova de eviccao L2:
//   - Depois do warmup, monta um set-alvo da L2:
//       4 linhas REUSE no mesmo set L2.
//       4 linhas STREAM no mesmo set L2.
//   - Depois pressiona esse mesmo set com 9 linhas novas usando PC_STREAM.
//   - Proba REUSE e STREAM antigos.
//   - Esperado:
//       REUSE tende a permanecer mais protegido.
//       STREAM antigo tende a ser evictado.
// =============================================================================

`timescale 1ns/1ps

module tb_cache_final_integrated_proof #(
    parameter WARMUP_PAIRS       = 30000,
    parameter REPORT_EVERY       = 5000,
    parameter RETEST_AFTER_RESET = 1,

    parameter MIN_REUSE_HITS_AFTER_EVICT    = 2,
    parameter MIN_STREAM_MISSES_AFTER_EVICT = 3
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

    wire [2:0] state_debug;

    localparam [31:0] PC_L1     = 32'h0000_1111;
    localparam [31:0] PC_REUSE  = 32'h0000_AAAA;
    localparam [31:0] PC_STREAM = 32'h0000_BBBB;
    localparam [31:0] PC_EVICT  = 32'h0000_CCCC;

    // L1: bloco 32 B, 64 sets => mesmo set L1 = 32*64 = 2048 = 0x800.
    localparam [31:0] BASE_L1_THRASH = 32'h0800_0000;
    localparam [31:0] BASE_L1_2WAY   = 32'h0900_0000;

    // L2: bloco 64 B, 64 sets => mesmo set L2 = 64*64 = 4096 = 0x1000.
    localparam [31:0] BASE_REUSE_WARMUP  = 32'h1000_0000;
    localparam [31:0] BASE_STREAM_WARMUP = 32'h2000_0000;

    localparam [31:0] BASE_TARGET_REUSE  = 32'h3000_0000;
    localparam [31:0] BASE_TARGET_STREAM = 32'h4000_0000;
    localparam [31:0] BASE_TARGET_EVICT  = 32'h5000_0000;

    integer i;
    integer j;
    integer errors;
    integer timeout_counter;

    reg [31:0] l1h_before;
    reg [31:0] l1m_before;
    reg [31:0] l2h_before;
    reg [31:0] l2m_before;

    reg [31:0] dl1h;
    reg [31:0] dl1m;
    reg [31:0] dl2h;
    reg [31:0] dl2m;

    integer loop_idx;
    integer phase_hits;
    integer phase_misses;
    integer loop_hits [0:2];
    integer loop_misses [0:2];

    integer pol_access_count;
    integer pol_fill_count;

    integer sampler_hit_count;
    integer sampler_update_count;
    integer training_done_count;

    integer predictor_train_count;
    integer predictor_train_up_count;
    integer predictor_train_down_count;

    integer raw_prediction_valid_count;
    integer raw_prediction_friendly_count;
    integer raw_prediction_averse_count;

    integer fill_reuse_friendly;
    integer fill_reuse_averse;
    integer fill_reuse_unknown;

    integer fill_stream_friendly;
    integer fill_stream_averse;
    integer fill_stream_unknown;

    integer effective_fill_friendly_count;
    integer effective_fill_averse_count;
    integer effective_fill_unknown_count;

    integer reuse_probe_l2_hits;
    integer reuse_probe_l2_misses;
    integer stream_probe_l2_hits;
    integer stream_probe_l2_misses;

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

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================================
    // Enderecos
    // =========================================================================
    function [31:0] addr_l1_thrash;
        input integer idx;
        begin
            addr_l1_thrash = BASE_L1_THRASH + (idx * 32'h0000_0800);
        end
    endfunction

    function [31:0] addr_l1_2way;
        input integer idx;
        begin
            addr_l1_2way = BASE_L1_2WAY + (idx * 32'h0000_0800);
        end
    endfunction

    function [31:0] addr_reuse_warmup;
        input integer idx;
        begin
            addr_reuse_warmup = BASE_REUSE_WARMUP + ((idx % 4) * 32'h0000_1000);
        end
    endfunction

    function [31:0] addr_stream_warmup;
        input integer idx;
        begin
            // IMPORTANTE:
            // stride 0x40 = 64 bytes = 1 bloco L2.
            // Esse padrao espalha pelos sets e foi o que gerou down/averse
            // no tb_hawkeye_proof.
            addr_stream_warmup = BASE_STREAM_WARMUP + (idx * 32'h0000_0040);
        end
    endfunction

    function [31:0] addr_target_reuse;
        input integer idx;
        begin
            addr_target_reuse = BASE_TARGET_REUSE + ((idx % 4) * 32'h0000_1000);
        end
    endfunction

    function [31:0] addr_target_stream;
        input integer idx;
        begin
            addr_target_stream = BASE_TARGET_STREAM + ((idx % 4) * 32'h0000_1000);
        end
    endfunction

    function [31:0] addr_target_evict;
        input integer idx;
        begin
            addr_target_evict = BASE_TARGET_EVICT + (idx * 32'h0000_1000);
        end
    endfunction

    // =========================================================================
    // Reset
    // =========================================================================
    task apply_reset;
        begin
            rst       = 1'b1;
            req_valid = 1'b0;
            req_addr  = 32'd0;
            req_pc    = 32'd0;

            repeat (10) @(posedge clk);
            rst <= 1'b0;

            repeat (150) @(posedge clk);
        end
    endtask

    // =========================================================================
    // Acesso CPU
    // =========================================================================
    task do_access;
        input [31:0] a;
        input [31:0] p;

        begin
            l1h_before = l1_hit_count;
            l1m_before = l1_miss_count;
            l2h_before = l2_hit_count;
            l2m_before = l2_miss_count;

            @(posedge clk);
            req_addr  <= a;
            req_pc    <= p;
            req_valid <= 1'b1;

            @(posedge clk);
            req_valid <= 1'b0;

            timeout_counter = 0;

            while ((done !== 1'b1) && (timeout_counter < 3000)) begin
                @(posedge clk);
                timeout_counter = timeout_counter + 1;
            end

            if (done !== 1'b1) begin
                $display("[ERRO] TIMEOUT addr=0x%08h pc=0x%08h state=%0d busy=%0d",
                         a, p, state_debug, busy);
                errors = errors + 1;
            end

            #1;

            dl1h = l1_hit_count  - l1h_before;
            dl1m = l1_miss_count - l1m_before;
            dl2h = l2_hit_count  - l2h_before;
            dl2m = l2_miss_count - l2m_before;

            @(posedge clk);
        end
    endtask

    // =========================================================================
    // Monitor Hawkeye
    // =========================================================================
    always @(posedge clk) begin
        if (!rst) begin
            #1;

            if (dut.u_policy.pol_access) begin
                pol_access_count = pol_access_count + 1;

                if (dut.u_policy.hawkeye_sampler_hit_debug)
                    sampler_hit_count = sampler_hit_count + 1;
            end

            if (dut.u_policy.hawkeye_core.sampler_update_enable)
                sampler_update_count = sampler_update_count + 1;

            if (dut.u_policy.hawkeye_training_done)
                training_done_count = training_done_count + 1;

            if (dut.u_policy.hawkeye_core.predictor_train_enable) begin
                predictor_train_count = predictor_train_count + 1;

                if (dut.u_policy.hawkeye_core.predictor_train_up)
                    predictor_train_up_count = predictor_train_up_count + 1;

                if (dut.u_policy.hawkeye_core.predictor_train_down)
                    predictor_train_down_count = predictor_train_down_count + 1;
            end

            if (dut.u_policy.hawkeye_prediction_valid) begin
                raw_prediction_valid_count = raw_prediction_valid_count + 1;

                if (dut.u_policy.hawkeye_friendly)
                    raw_prediction_friendly_count = raw_prediction_friendly_count + 1;

                if (dut.u_policy.hawkeye_averse)
                    raw_prediction_averse_count = raw_prediction_averse_count + 1;
            end

            if (dut.u_policy.pol_fill) begin
                pol_fill_count = pol_fill_count + 1;

                if (dut.u_policy.pol_pc == PC_REUSE) begin
                    if (dut.u_policy.pred_friendly_latched)
                        fill_reuse_friendly = fill_reuse_friendly + 1;
                    else if (dut.u_policy.pred_averse_latched)
                        fill_reuse_averse = fill_reuse_averse + 1;
                    else
                        fill_reuse_unknown = fill_reuse_unknown + 1;
                end

                if (dut.u_policy.pol_pc == PC_STREAM) begin
                    if (dut.u_policy.pred_friendly_latched)
                        fill_stream_friendly = fill_stream_friendly + 1;
                    else if (dut.u_policy.pred_averse_latched)
                        fill_stream_averse = fill_stream_averse + 1;
                    else
                        fill_stream_unknown = fill_stream_unknown + 1;
                end

                if (dut.u_policy.fill_pred_valid_effective &&
                    dut.u_policy.fill_pred_friendly_effective) begin
                    effective_fill_friendly_count = effective_fill_friendly_count + 1;
                end
                else if (dut.u_policy.fill_pred_valid_effective &&
                         dut.u_policy.fill_pred_averse_effective) begin
                    effective_fill_averse_count = effective_fill_averse_count + 1;
                end
                else begin
                    effective_fill_unknown_count = effective_fill_unknown_count + 1;
                end
            end
        end
    end

    // =========================================================================
    // Zera monitores
    // =========================================================================
    task clear_monitor_counters;
        begin
            pol_access_count = 0;
            pol_fill_count = 0;

            sampler_hit_count = 0;
            sampler_update_count = 0;
            training_done_count = 0;

            predictor_train_count = 0;
            predictor_train_up_count = 0;
            predictor_train_down_count = 0;

            raw_prediction_valid_count = 0;
            raw_prediction_friendly_count = 0;
            raw_prediction_averse_count = 0;

            fill_reuse_friendly = 0;
            fill_reuse_averse = 0;
            fill_reuse_unknown = 0;

            fill_stream_friendly = 0;
            fill_stream_averse = 0;
            fill_stream_unknown = 0;

            effective_fill_friendly_count = 0;
            effective_fill_averse_count = 0;
            effective_fill_unknown_count = 0;
        end
    endtask

    // =========================================================================
    // Fase 1A
    // =========================================================================
    task phase1a_l1_thrashing;
        begin
            $display("");
            $display("=========================================================");
            $display(" FASE 1A - L1 LRU THRASHING");
            $display("=========================================================");

            apply_reset();

            for (loop_idx = 0; loop_idx < 3; loop_idx = loop_idx + 1) begin
                phase_hits = 0;
                phase_misses = 0;

                for (j = 0; j < 8; j = j + 1) begin
                    do_access(addr_l1_thrash(j), PC_L1);
                    phase_hits   = phase_hits   + dl1h;
                    phase_misses = phase_misses + dl1m;
                end

                loop_hits[loop_idx]   = phase_hits;
                loop_misses[loop_idx] = phase_misses;

                $display("[L1 THRASH] volta=%0d | L1 hits=%0d misses=%0d",
                         loop_idx + 1, phase_hits, phase_misses);
            end

            if (loop_misses[0] != 8 || loop_misses[1] != 8 || loop_misses[2] != 8) begin
                $display("[ERRO] L1 thrashing nao gerou 8 misses em todas as voltas.");
                errors = errors + 1;
            end
            else begin
                $display("[OK] Fase 1A passou.");
            end
        end
    endtask

    // =========================================================================
    // Fase 1B
    // =========================================================================
    task phase1b_l1_2way_positive;
        begin
            $display("");
            $display("=========================================================");
            $display(" FASE 1B - L1 LRU CONTROLE POSITIVO");
            $display("=========================================================");

            apply_reset();

            for (loop_idx = 0; loop_idx < 3; loop_idx = loop_idx + 1) begin
                phase_hits = 0;
                phase_misses = 0;

                for (j = 0; j < 2; j = j + 1) begin
                    do_access(addr_l1_2way(j), PC_L1);
                    phase_hits   = phase_hits   + dl1h;
                    phase_misses = phase_misses + dl1m;
                end

                loop_hits[loop_idx]   = phase_hits;
                loop_misses[loop_idx] = phase_misses;

                $display("[L1 2WAY] volta=%0d | L1 hits=%0d misses=%0d",
                         loop_idx + 1, phase_hits, phase_misses);
            end

            if (loop_misses[0] != 2) begin
                $display("[ERRO] L1 2-way: primeira volta deveria ter 2 misses.");
                errors = errors + 1;
            end

            if (loop_hits[1] != 2 || loop_hits[2] != 2) begin
                $display("[ERRO] L1 2-way: voltas 2 e 3 deveriam ter 2 hits.");
                errors = errors + 1;
            end

            if (loop_misses[0] == 2 && loop_hits[1] == 2 && loop_hits[2] == 2) begin
                $display("[OK] Fase 1B passou.");
            end
        end
    endtask

    // =========================================================================
    // Fase 2
    // =========================================================================
    task phase2_warmup_hawkeye;
        input integer run_id;
        begin
            $display("");
            $display("=========================================================");
            $display(" FASE 2 - WARMUP L2 HAWKEYE AJUSTADO | run=%0d", run_id);
            $display(" WARMUP_PAIRS=%0d", WARMUP_PAIRS);
            $display(" STREAM warmup usa stride 0x40 para gerar down/averse");
            $display("=========================================================");

            clear_monitor_counters();

            for (i = 0; i < WARMUP_PAIRS; i = i + 1) begin
                do_access(addr_reuse_warmup(i), PC_REUSE);
                do_access(addr_stream_warmup(i), PC_STREAM);

                if (((i + 1) % REPORT_EVERY) == 0) begin
                    $display("[WARMUP %0d] pair=%0d/%0d | L1 h/m=%0d/%0d | L2 h/m=%0d/%0d | pred valid=%0d F/A=%0d/%0d | train=%0d up/down=%0d/%0d",
                             run_id,
                             i + 1,
                             WARMUP_PAIRS,
                             l1_hit_count,
                             l1_miss_count,
                             l2_hit_count,
                             l2_miss_count,
                             raw_prediction_valid_count,
                             raw_prediction_friendly_count,
                             raw_prediction_averse_count,
                             predictor_train_count,
                             predictor_train_up_count,
                             predictor_train_down_count);
                end
            end

            $display("[WARMUP FINAL] pred valid=%0d friendly=%0d averse=%0d train=%0d up=%0d down=%0d",
                     raw_prediction_valid_count,
                     raw_prediction_friendly_count,
                     raw_prediction_averse_count,
                     predictor_train_count,
                     predictor_train_up_count,
                     predictor_train_down_count);

            if (raw_prediction_valid_count == 0) begin
                $display("[ERRO] Warmup: predictor nunca gerou prediction_valid.");
                errors = errors + 1;
            end

            if (raw_prediction_averse_count == 0) begin
                $display("[ERRO] Warmup: predictor nao gerou nenhuma predicao averse.");
                errors = errors + 1;
            end

            if (predictor_train_down_count == 0) begin
                $display("[ERRO] Warmup: nao houve treino down.");
                errors = errors + 1;
            end
        end
    endtask

    // =========================================================================
    // Fase 3
    // =========================================================================
    task phase3_l2_eviction_proof;
        input integer run_id;
        begin
            $display("");
            $display("=========================================================");
            $display(" FASE 3 - PROVA DE EVICCAO L2 HAWKEYE AJUSTADA | run=%0d", run_id);
            $display(" Monta set-alvo com REUSE friendly e STREAM averse, depois pressiona.");
            $display("=========================================================");

            reuse_probe_l2_hits = 0;
            reuse_probe_l2_misses = 0;
            stream_probe_l2_hits = 0;
            stream_probe_l2_misses = 0;

            // -----------------------------------------------------------------
            // Monta set-alvo:
            // 4 REUSE e 4 STREAM no mesmo set L2.
            // -----------------------------------------------------------------
            for (j = 0; j < 4; j = j + 1) begin
                do_access(addr_target_reuse(j), PC_REUSE);
            end

            for (j = 0; j < 4; j = j + 1) begin
                do_access(addr_target_stream(j), PC_STREAM);
            end

            // Reacessa REUSE para reforcar protecao/hit update.
            for (j = 0; j < 4; j = j + 1) begin
                do_access(addr_target_reuse(j), PC_REUSE);
            end

            // -----------------------------------------------------------------
            // Pressiona o mesmo set L2 com 9 linhas novas STREAM.
            // -----------------------------------------------------------------
            for (j = 0; j < 9; j = j + 1) begin
                do_access(addr_target_evict((run_id * 100) + j), PC_STREAM);
            end

            // Probe REUSE.
            for (j = 0; j < 4; j = j + 1) begin
                do_access(addr_target_reuse(j), PC_REUSE);

                reuse_probe_l2_hits   = reuse_probe_l2_hits   + dl2h;
                reuse_probe_l2_misses = reuse_probe_l2_misses + dl2m;

                $display("[PROBE REUSE] j=%0d addr=0x%08h | dL1 h/m=%0d/%0d dL2 h/m=%0d/%0d",
                         j, addr_target_reuse(j), dl1h, dl1m, dl2h, dl2m);
            end

            // Probe STREAM antigo.
            for (j = 0; j < 4; j = j + 1) begin
                do_access(addr_target_stream(j), PC_STREAM);

                stream_probe_l2_hits   = stream_probe_l2_hits   + dl2h;
                stream_probe_l2_misses = stream_probe_l2_misses + dl2m;

                $display("[PROBE STREAM] j=%0d addr=0x%08h | dL1 h/m=%0d/%0d dL2 h/m=%0d/%0d",
                         j, addr_target_stream(j), dl1h, dl1m, dl2h, dl2m);
            end

            $display("");
            $display("[EVICT RESULT run=%0d]", run_id);
            $display("  REUSE  probe L2 hits=%0d misses=%0d", reuse_probe_l2_hits, reuse_probe_l2_misses);
            $display("  STREAM probe L2 hits=%0d misses=%0d", stream_probe_l2_hits, stream_probe_l2_misses);
            $display("  Fills REUSE  F/A/U=%0d/%0d/%0d", fill_reuse_friendly, fill_reuse_averse, fill_reuse_unknown);
            $display("  Fills STREAM F/A/U=%0d/%0d/%0d", fill_stream_friendly, fill_stream_averse, fill_stream_unknown);
            $display("  Effective fills F/A/U=%0d/%0d/%0d",
                     effective_fill_friendly_count,
                     effective_fill_averse_count,
                     effective_fill_unknown_count);

            if (reuse_probe_l2_hits < MIN_REUSE_HITS_AFTER_EVICT) begin
                $display("[ERRO] REUSE nao foi suficientemente protegido na L2.");
                $display("       hits=%0d minimo=%0d", reuse_probe_l2_hits, MIN_REUSE_HITS_AFTER_EVICT);
                errors = errors + 1;
            end
            else begin
                $display("[OK] REUSE protegido apos pressao de eviccao.");
            end

            if (stream_probe_l2_misses < MIN_STREAM_MISSES_AFTER_EVICT) begin
                $display("[ERRO] STREAM antigo nao foi suficientemente evictado.");
                $display("       misses=%0d minimo=%0d", stream_probe_l2_misses, MIN_STREAM_MISSES_AFTER_EVICT);
                errors = errors + 1;
            end
            else begin
                $display("[OK] STREAM antigo evictado apos pressao.");
            end

            if (fill_reuse_friendly <= fill_reuse_averse) begin
                $display("[ERRO] REUSE nao ficou majoritariamente friendly.");
                errors = errors + 1;
            end

            if (fill_stream_averse <= fill_stream_friendly) begin
                $display("[ERRO] STREAM nao ficou majoritariamente averse.");
                errors = errors + 1;
            end
        end
    endtask

    // =========================================================================
    // Sumario final
    // =========================================================================
    task final_summary;
        begin
            $display("");
            $display("=========================================================");
            $display(" RESULTADO FINAL - CACHE FINAL INTEGRATED PROOF AJUSTADO");
            $display("=========================================================");
            $display(" L1 total: hits=%0d misses=%0d soma=%0d",
                     l1_hit_count, l1_miss_count, l1_hit_count + l1_miss_count);
            $display(" L2 total: hits=%0d misses=%0d soma=%0d",
                     l2_hit_count, l2_miss_count, l2_hit_count + l2_miss_count);
            $display("");
            $display(" Hawkeye:");
            $display("   pol_access=%0d pol_fill=%0d", pol_access_count, pol_fill_count);
            $display("   sampler_update=%0d sampler_hit_debug=%0d training_done=%0d",
                     sampler_update_count, sampler_hit_count, training_done_count);
            $display("   predictor_train=%0d up=%0d down=%0d",
                     predictor_train_count,
                     predictor_train_up_count,
                     predictor_train_down_count);
            $display("   prediction_valid=%0d friendly=%0d averse=%0d",
                     raw_prediction_valid_count,
                     raw_prediction_friendly_count,
                     raw_prediction_averse_count);
            $display("");
            $display(" Fills por PC:");
            $display("   REUSE  friendly=%0d averse=%0d unknown=%0d",
                     fill_reuse_friendly, fill_reuse_averse, fill_reuse_unknown);
            $display("   STREAM friendly=%0d averse=%0d unknown=%0d",
                     fill_stream_friendly, fill_stream_averse, fill_stream_unknown);
            $display("");
            $display(" Fills efetivos:");
            $display("   friendly=%0d averse=%0d unknown=%0d",
                     effective_fill_friendly_count,
                     effective_fill_averse_count,
                     effective_fill_unknown_count);
            $display("=========================================================");

            if ((l1_hit_count + l1_miss_count) == 0) begin
                $display("[ERRO] Nenhum acesso contado na L1.");
                errors = errors + 1;
            end

            if ((l2_hit_count + l2_miss_count) != l1_miss_count) begin
                $display("[ERRO] L2 hits+misses diferente dos misses da L1.");
                errors = errors + 1;
            end

            if (errors == 0) begin
                $display("[OK] TESTE FINAL INTEGRADO AJUSTADO PASSOU.");
            end
            else begin
                $display("[FALHOU] TESTE FINAL INTEGRADO AJUSTADO terminou com %0d erro(s).", errors);
            end
        end
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    initial begin
        errors = 0;

        rst       = 1'b1;
        req_valid = 1'b0;
        req_addr  = 32'd0;
        req_pc    = 32'd0;

        clear_monitor_counters();

        $display("=========================================================");
        $display(" TB CACHE FINAL INTEGRATED PROOF AJUSTADO");
        $display(" WARMUP_PAIRS=%0d", WARMUP_PAIRS);
        $display(" REPORT_EVERY=%0d", REPORT_EVERY);
        $display(" RETEST_AFTER_RESET=%0d", RETEST_AFTER_RESET);
        $display("=========================================================");

        phase1a_l1_thrashing();
        phase1b_l1_2way_positive();

        apply_reset();
        clear_monitor_counters();
        phase2_warmup_hawkeye(1);
        phase3_l2_eviction_proof(1);

        if (RETEST_AFTER_RESET != 0) begin
            $display("");
            $display("=========================================================");
            $display(" FASE 4 - RESET E RETESTE HAWKEYE");
            $display("=========================================================");

            apply_reset();
            clear_monitor_counters();
            phase2_warmup_hawkeye(2);
            phase3_l2_eviction_proof(2);
        end

        final_summary();

        $finish;
    end

endmodule   