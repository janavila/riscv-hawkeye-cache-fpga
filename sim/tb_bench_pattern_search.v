// =============================================================================
// tb_bench_pattern_search.v
// -----------------------------------------------------------------------------
// Espelha o benchmark "Pattern Search" do modelo em C:
//   24 entradas competindo pelas 8 vias da L2 -> thrashing.
//
// Enderecos = BASE + k*L2_SIZE_BYTES (k=0..23) mantem o MESMO indice de set
// e MUDA so a tag, forcando conflito real de associatividade (24 > 8 vias).
// =============================================================================

`timescale 1ns/1ps

module tb_bench_pattern_search #(
    parameter TOTAL_ACCESSES = 50000,
    parameter REPORT_EVERY   = 5000
);

    localparam L2_SIZE_BYTES   = 32768; // 32 KB
    localparam PATTERN_ENTRIES = 24;    // > 8 vias -> thrashing garantido

    localparam [31:0] BASE_PATTERN = 32'h4000_0000;
    localparam [31:0] PC_PATTERN   = 32'h0000_4001;

    localparam CYCLES_L1_HIT = 1;
    localparam CYCLES_L2_HIT = 10;
    localparam CYCLES_RAM    = 100;

    // =========================================================================
    // DUT
    // =========================================================================
    reg         clk;
    reg         rst;

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

    integer clk_cycle_count;
    always @(posedge clk) clk_cycle_count = clk_cycle_count + 1;

    // =========================================================================
    // Geracao do padrao Pattern Search
    // =========================================================================
    integer pattern_idx;

    task choose_pattern;
        input  integer idx;
        output [31:0]  out_addr;
        output [31:0]  out_pc;
        begin
            pattern_idx = idx % PATTERN_ENTRIES;
            out_addr = BASE_PATTERN + (pattern_idx * L2_SIZE_BYTES);
            out_pc   = PC_PATTERN;
        end
    endtask

    // =========================================================================
    // Execucao de um acesso
    // =========================================================================
    integer timeout_counter;
    integer errors;

    reg [31:0] l1h_before, l1m_before, l2h_before, l2m_before;
    reg [31:0] dl1h, dl1m, dl2h, dl2m;

    integer total_l1_hits, total_l1_misses;
    integer total_l2_hits, total_l2_misses;
    real    total_cost_cycles;

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
            while ((done !== 1'b1) && (timeout_counter < 1000)) begin
                @(posedge clk);
                timeout_counter = timeout_counter + 1;
            end

            if (done !== 1'b1) begin
                $display("[ERRO] TIMEOUT addr=0x%08h pc=0x%08h", a, p);
                errors = errors + 1;
            end

            dl1h = l1_hit_count  - l1h_before;
            dl1m = l1_miss_count - l1m_before;
            dl2h = l2_hit_count  - l2h_before;
            dl2m = l2_miss_count - l2m_before;

            total_l1_hits   = total_l1_hits   + dl1h;
            total_l1_misses = total_l1_misses + dl1m;
            total_l2_hits   = total_l2_hits   + dl2h;
            total_l2_misses = total_l2_misses + dl2m;

            if (dl1h) total_cost_cycles = total_cost_cycles + CYCLES_L1_HIT;
            if (dl2h) total_cost_cycles = total_cost_cycles + CYCLES_L2_HIT;
            if (dl2m) total_cost_cycles = total_cost_cycles + CYCLES_RAM;
        end
    endtask

    // =========================================================================
    // Sequencia principal
    // =========================================================================
    integer i;
    reg [31:0] addr, pc;
    real hr_l1_pct, hr_l2_pct;

    initial begin
        rst             = 1'b1;
        req_valid       = 1'b0;
        req_addr        = 32'h0;
        req_pc          = 32'h0;
        errors          = 0;
        clk_cycle_count = 0;

        total_l1_hits   = 0;
        total_l1_misses = 0;
        total_l2_hits   = 0;
        total_l2_misses = 0;
        total_cost_cycles = 0.0;

        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (150) @(posedge clk);

        $display("ECHO,BENCHMARK,pattern");
        $display("ECHO,TOTAL_ACCESSES,%0d", TOTAL_ACCESSES);
        $display("ECHO,HEADER,idx,l1_hits,l1_misses,l2_hits,l2_misses,hr_l1_pct,hr_l2_pct");

        for (i = 0; i < TOTAL_ACCESSES; i = i + 1) begin
            choose_pattern(i, addr, pc);
            do_access(addr, pc);

            if ((i % REPORT_EVERY) == 0 && i > 0) begin
                hr_l1_pct = 100.0 * total_l1_hits / (total_l1_hits + total_l1_misses);
                hr_l2_pct = 100.0 * total_l2_hits / (total_l2_hits + total_l2_misses + 1);
                $display("ECHO,PROGRESS,%0d,%0d,%0d,%0d,%0d,%0.2f,%0.2f",
                          i, total_l1_hits, total_l1_misses,
                          total_l2_hits, total_l2_misses, hr_l1_pct, hr_l2_pct);
            end
        end

        hr_l1_pct = 100.0 * total_l1_hits / (total_l1_hits + total_l1_misses);
        hr_l2_pct = 100.0 * total_l2_hits / (total_l2_hits + total_l2_misses);

        $display("ECHO,FINAL,BENCHMARK,pattern");
        $display("ECHO,FINAL,HR_L1_PCT,%0.4f", hr_l1_pct);
        $display("ECHO,FINAL,HR_L2_PCT,%0.4f", hr_l2_pct);
        $display("ECHO,FINAL,L1_HITS,%0d",   total_l1_hits);
        $display("ECHO,FINAL,L1_MISSES,%0d", total_l1_misses);
        $display("ECHO,FINAL,L2_HITS,%0d",   total_l2_hits);
        $display("ECHO,FINAL,L2_MISSES,%0d", total_l2_misses);
        $display("ECHO,FINAL,RAM_ACCESSES,%0d", total_l2_misses);
        $display("ECHO,FINAL,COST_MODEL_CYCLES,%0.1f", total_cost_cycles);
        $display("ECHO,FINAL,RTL_CLK_CYCLES,%0d", clk_cycle_count);
        $display("ECHO,FINAL,ERRORS,%0d", errors);
        $display("ECHO,DONE");

        $stop;
    end

endmodule
