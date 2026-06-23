// =============================================================================
// tb_hierarchy_top_ramp_quiet.v
// -----------------------------------------------------------------------------
// Teste progressivo QUIET da hierarquia completa otimizada com RAM.
//
// Objetivo:
// - Rodar cargas grandes: 100K, 200K, 300K acessos.
// - Nao imprimir cada acesso individual.
// - Imprimir somente progresso a cada REPORT_EVERY.
// - Validar sanidade dos contadores ao final.
//
// Validacoes:
// - L1 hits + L1 misses = TOTAL_ACCESSES.
// - L2 hits + L2 misses = L1 misses.
// - L2 deve ter hits.
// - L2 deve ter misses.
// - Nao pode dar timeout.
// =============================================================================

`timescale 1ns/1ps

module tb_hierarchy_top_ramp_quiet #(
    parameter TOTAL_ACCESSES = 100000,
    parameter REPORT_EVERY   = 10000
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

    integer i;
    integer errors;
    integer timeout_counter;

    reg [31:0] addr;
    reg [31:0] pc;

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

        begin
            case (idx % 12)

                // Conflito controlado na L1.
                0: begin
                    out_addr = 32'h0000_0000;
                    out_pc   = 32'h0000_AAAA;
                end

                1: begin
                    out_addr = 32'h0000_0800;
                    out_pc   = 32'h0000_BBBB;
                end

                2: begin
                    out_addr = 32'h0000_0000;
                    out_pc   = 32'h0000_AAAA;
                end

                3: begin
                    out_addr = 32'h0000_1000;
                    out_pc   = 32'h0000_CCCC;
                end

                4: begin
                    out_addr = 32'h0000_0800;
                    out_pc   = 32'h0000_BBBB;
                end

                5: begin
                    out_addr = 32'h0000_0800;
                    out_pc   = 32'h0000_BBBB;
                end

                // Hotset pequeno.
                6: begin
                    out_addr = 32'h0000_0140;
                    out_pc   = 32'h0000_1111;
                end

                7: begin
                    out_addr = 32'h0000_0160;
                    out_pc   = 32'h0000_1111;
                end

                8: begin
                    out_addr = 32'h0000_0140;
                    out_pc   = 32'h0000_1111;
                end

                9: begin
                    out_addr = 32'h0000_0160;
                    out_pc   = 32'h0000_1111;
                end

                // Streaming leve para gerar misses.
                10: begin
                    out_addr = 32'h0002_0000 + (idx * 64);
                    out_pc   = 32'h0000_5000;
                end

                default: begin
                    out_addr = 32'h0003_0000 + (idx * 64);
                    out_pc   = 32'h0000_6000;
                end

            endcase
        end
    endtask

    // =========================================================================
    // Executa um acesso CPU e espera done
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

            while ((done !== 1'b1) && (timeout_counter < 1000)) begin
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
    // Teste principal
    // =========================================================================
    initial begin
        errors    = 0;
        rst       = 1'b1;
        req_valid = 1'b0;
        req_addr  = 32'd0;
        req_pc    = 32'd0;

        $display("=========================================================");
        $display(" TESTE RAMP QUIET HIERARQUIA COMPLETA OTIMIZADA");
        $display(" TOTAL_ACCESSES=%0d", TOTAL_ACCESSES);
        $display(" REPORT_EVERY=%0d", REPORT_EVERY);
        $display("=========================================================");

        // Reset
        repeat (10) @(posedge clk);
        rst <= 1'b0;

        // Espera inicializacao interna da L2 em RAM.
        repeat (100) @(posedge clk);

        for (i = 0; i < TOTAL_ACCESSES; i = i + 1) begin
            choose_pattern(i, addr, pc);
            do_access(addr, pc);

            if (((i + 1) % REPORT_EVERY) == 0) begin
                $display("[PROGRESS] %0d/%0d | L1 h/m=%0d/%0d | L2 h/m=%0d/%0d",
                         i + 1, TOTAL_ACCESSES,
                         l1_hit_count, l1_miss_count,
                         l2_hit_count, l2_miss_count);
            end
        end

        $display("=========================================================");
        $display(" RESULTADO FINAL RAMP QUIET");
        $display(" CPU acessos = %0d", TOTAL_ACCESSES);
        $display(" L1: hits=%0d misses=%0d", l1_hit_count, l1_miss_count);
        $display(" L2: hits=%0d misses=%0d", l2_hit_count, l2_miss_count);
        $display(" Soma L1 = %0d", l1_hit_count + l1_miss_count);
        $display(" Soma L2 = %0d", l2_hit_count + l2_miss_count);
        $display("=========================================================");

        if ((l1_hit_count + l1_miss_count) != TOTAL_ACCESSES) begin
            $display("[ERRO] L1 hits+misses diferente do total de acessos CPU.");
            $display("       L1 total=%0d esperado=%0d",
                     l1_hit_count + l1_miss_count, TOTAL_ACCESSES);
            errors = errors + 1;
        end

        if ((l2_hit_count + l2_miss_count) != l1_miss_count) begin
            $display("[ERRO] L2 hits+misses diferente dos misses da L1.");
            $display("       L2 total=%0d L1 misses=%0d",
                     l2_hit_count + l2_miss_count, l1_miss_count);
            errors = errors + 1;
        end

        if (l2_miss_count == 0) begin
            $display("[ERRO] L2 nao registrou misses.");
            errors = errors + 1;
        end

        if (l2_hit_count == 0) begin
            $display("[ERRO] L2 nao registrou hits.");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("[OK] Teste ramp quiet passou.");
        end
        else begin
            $display("[FALHOU] Teste ramp quiet terminou com %0d erro(s).", errors);
        end

        $finish;
    end

endmodule   