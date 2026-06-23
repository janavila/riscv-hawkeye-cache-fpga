// =============================================================================
// tb_hierarchy_top_smoke.v
// -----------------------------------------------------------------------------
// Teste pequeno da hierarquia completa otimizada com RAM.
//
// Diferenca desta versao:
// - Nao depende dos pulsos resp_* ficarem altos no ciclo do done.
// - Valida cada acesso pela diferenca dos contadores.
// - Isso e mais robusto para FSMs com pulsos intermediarios.
// =============================================================================

`timescale 1ns/1ps

module tb_hierarchy_top_smoke;

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

    task check_delta;
        input [31:0] got;
        input [31:0] expected;
        input [127:0] name;
        begin
            if (got !== expected) begin
                $display("[ERRO] %0s esperado=%0d obtido=%0d", name, expected, got);
                errors = errors + 1;
            end
        end
    endtask

    task cpu_access_by_counter;
        input [31:0] addr;
        input [31:0] pc;
        input [127:0] label;

        input [31:0] exp_dl1h;
        input [31:0] exp_dl1m;
        input [31:0] exp_dl2h;
        input [31:0] exp_dl2m;

        begin
            l1h_before = l1_hit_count;
            l1m_before = l1_miss_count;
            l2h_before = l2_hit_count;
            l2m_before = l2_miss_count;

            @(posedge clk);
            req_addr  <= addr;
            req_pc    <= pc;
            req_valid <= 1'b1;

            @(posedge clk);
            req_valid <= 1'b0;

            timeout_counter = 0;

            while ((done !== 1'b1) && (timeout_counter < 800)) begin
                @(posedge clk);
                timeout_counter = timeout_counter + 1;
            end

            if (done !== 1'b1) begin
                $display("[ERRO] TIMEOUT no acesso %0s addr=0x%08h state=%0d busy=%0d",
                         label, addr, state_debug, busy);
                errors = errors + 1;
            end
            else begin
                #1;

                dl1h = l1_hit_count  - l1h_before;
                dl1m = l1_miss_count - l1m_before;
                dl2h = l2_hit_count  - l2h_before;
                dl2m = l2_miss_count - l2m_before;

                $display("[TB t=%0t] %-12s addr=0x%08h pc=0x%08h | delta L1 h/m=%0d/%0d L2 h/m=%0d/%0d | total L1=%0d/%0d L2=%0d/%0d",
                         $time, label, addr, pc,
                         dl1h, dl1m, dl2h, dl2m,
                         l1_hit_count, l1_miss_count,
                         l2_hit_count, l2_miss_count);

                check_delta(dl1h, exp_dl1h, "delta L1 hit");
                check_delta(dl1m, exp_dl1m, "delta L1 miss");
                check_delta(dl2h, exp_dl2h, "delta L2 hit");
                check_delta(dl2m, exp_dl2m, "delta L2 miss");
            end

            @(posedge clk);
        end
    endtask

    initial begin
        errors    = 0;
        rst       = 1'b1;
        req_valid = 1'b0;
        req_addr  = 32'd0;
        req_pc    = 32'd0;

        $display("=========================================================");
        $display(" TESTE SMOKE HIERARQUIA COMPLETA OTIMIZADA");
        $display(" Validacao por diferenca de contadores");
        $display("=========================================================");

        repeat (10) @(posedge clk);
        rst <= 1'b0;

        // Espera inicializacao interna da L2 em RAM.
        repeat (100) @(posedge clk);

        $display("\n--- FASE 1: A primeiro miss, depois hit ---");

        // A-first: L1 miss, L2 miss
        cpu_access_by_counter(32'h0000_0000, 32'h0000_AAAA, "A-first",
                              32'd0, 32'd1, 32'd0, 32'd1);

        // A-again: L1 hit, sem acessar L2
        cpu_access_by_counter(32'h0000_0000, 32'h0000_AAAA, "A-again",
                              32'd1, 32'd0, 32'd0, 32'd0);

        $display("\n--- FASE 2: conflito L1 e retorno pela L2 ---");

        // B-first: L1 miss, L2 miss
        cpu_access_by_counter(32'h0000_0800, 32'h0000_BBBB, "B-first",
                              32'd0, 32'd1, 32'd0, 32'd1);

        // A-reuse: L1 hit
        cpu_access_by_counter(32'h0000_0000, 32'h0000_AAAA, "A-reuse",
                              32'd1, 32'd0, 32'd0, 32'd0);

        // C-first: L1 miss, L2 miss
        cpu_access_by_counter(32'h0000_1000, 32'h0000_CCCC, "C-first",
                              32'd0, 32'd1, 32'd0, 32'd1);

        // B-return: L1 miss, L2 hit
        cpu_access_by_counter(32'h0000_0800, 32'h0000_BBBB, "B-return",
                              32'd0, 32'd1, 32'd1, 32'd0);

        // B-again: L1 hit
        cpu_access_by_counter(32'h0000_0800, 32'h0000_BBBB, "B-again",
                              32'd1, 32'd0, 32'd0, 32'd0);

        $display("---------------------------------------------------------");
        $display(" Totais finais:");
        $display(" L1: hits=%0d misses=%0d", l1_hit_count, l1_miss_count);
        $display(" L2: hits=%0d misses=%0d", l2_hit_count, l2_miss_count);
        $display(" Esperado:");
        $display(" L1: hits=3 misses=4");
        $display(" L2: hits=1 misses=3");
        $display("---------------------------------------------------------");

        if (l1_hit_count !== 32'd3) begin
            $display("[ERRO] l1_hit_count esperado=3 obtido=%0d", l1_hit_count);
            errors = errors + 1;
        end

        if (l1_miss_count !== 32'd4) begin
            $display("[ERRO] l1_miss_count esperado=4 obtido=%0d", l1_miss_count);
            errors = errors + 1;
        end

        if (l2_hit_count !== 32'd1) begin
            $display("[ERRO] l2_hit_count esperado=1 obtido=%0d", l2_hit_count);
            errors = errors + 1;
        end

        if (l2_miss_count !== 32'd3) begin
            $display("[ERRO] l2_miss_count esperado=3 obtido=%0d", l2_miss_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("[OK] Teste smoke passou.");
        end
        else begin
            $display("[FALHOU] Teste smoke terminou com %0d erro(s).", errors);
        end

        $finish;
    end

endmodule   