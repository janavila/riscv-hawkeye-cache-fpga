// =============================================================================
// tb_hierarchy_controlled_simple.v
// -----------------------------------------------------------------------------
// Teste simples da hierarquia L1 + L2 + Hawkeye com fill controlado.
//
// Agora a L1 NAO se auto-preenche em miss.
// Fluxo realista:
//   CPU acessa L1
//   se L1 MISS -> acessa L2
//   quando L2 termina -> testbench gera fill_valid na L1
//   proximo acesso ao mesmo bloco deve dar L1 HIT
// =============================================================================

`timescale 1ns/1ps

module tb_hierarchy_controlled_simple;

    reg clk;
    reg rst;

    // ---------------- L1 ----------------
    reg         l1_req_valid;
    reg  [31:0] l1_req_addr;
    reg         l1_fill_valid;
    reg  [31:0] l1_fill_addr;

    wire        l1_hit;
    wire        l1_miss;
    wire [31:0] l1_hit_count;
    wire [31:0] l1_miss_count;

    // ---------------- L2 ----------------
    reg         l2_req_valid;
    reg  [31:0] l2_req_addr;
    reg  [31:0] l2_req_pc;

    wire        l2_done;
    wire        l2_hit;
    wire        l2_miss;
    wire [31:0] l2_hit_count;
    wire [31:0] l2_miss_count;

    // Interface L2 <-> politica Hawkeye
    wire [5:0]  pol_set;
    wire [31:0] pol_pc;
    wire [31:0] pol_addr;
    wire        pol_access;
    wire        pol_hit;
    wire [2:0]  pol_hit_way;
    wire        pol_need_victim;
    wire        pol_fill;
    wire [2:0]  pol_fill_way;
    wire [2:0]  pol_victim_way;
    wire        pol_victim_valid;

    // ---------------- L1 com fill controlado ----------------
    cache_l1 #(
        .AUTO_FILL_ON_MISS(0)
    ) l1 (
        .clk(clk),
        .rst(rst),

        .req_valid(l1_req_valid),
        .req_addr(l1_req_addr),

        .fill_valid(l1_fill_valid),
        .fill_addr(l1_fill_addr),

        .hit(l1_hit),
        .miss(l1_miss),
        .hit_count(l1_hit_count),
        .miss_count(l1_miss_count)
    );

    // ---------------- L2 ----------------
    cache_l2 l2 (
        .clk(clk),
        .rst(rst),

        .req_valid(l2_req_valid),
        .req_addr(l2_req_addr),
        .req_pc(l2_req_pc),

        .done(l2_done),
        .hit(l2_hit),
        .miss(l2_miss),

        .pol_set(pol_set),
        .pol_pc(pol_pc),
        .pol_addr(pol_addr),
        .pol_access(pol_access),
        .pol_hit(pol_hit),
        .pol_hit_way(pol_hit_way),
        .pol_need_victim(pol_need_victim),
        .pol_fill(pol_fill),
        .pol_fill_way(pol_fill_way),
        .pol_victim_way(pol_victim_way),
        .pol_victim_valid(pol_victim_valid),

        .hit_count(l2_hit_count),
        .miss_count(l2_miss_count)
    );

    // ---------------- Hawkeye L2 Policy ----------------
    hawkeye_l2_policy pol (
        .clk(clk),
        .rst(rst),

        .pol_set(pol_set),
        .pol_pc(pol_pc),
        .pol_addr(pol_addr),
        .pol_access(pol_access),
        .pol_hit(pol_hit),
        .pol_hit_way(pol_hit_way),
        .pol_need_victim(pol_need_victim),
        .pol_fill(pol_fill),
        .pol_fill_way(pol_fill_way),

        .pol_victim_way(pol_victim_way),
        .pol_victim_valid(pol_victim_valid)
    );

    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Acesso L2
    // -------------------------------------------------------------------------
    task acessa_l2;
        input [31:0] endereco;
        input [31:0] pc;
        input [127:0] rotulo;
        output integer l2_was_hit;

        integer timeout;

        begin
            @(negedge clk);
            l2_req_valid = 1'b1;
            l2_req_addr  = endereco;
            l2_req_pc    = pc;

            @(negedge clk);
            l2_req_valid = 1'b0;

            timeout = 0;
            while(l2_done !== 1'b1 && timeout < 300) begin
                @(negedge clk);
                timeout = timeout + 1;
            end

            if(timeout >= 300) begin
                $display("[ERRO t=%0t] TIMEOUT L2 em %0s addr=0x%08h",
                         $time, rotulo, endereco);
                $finish;
            end

            if(l2_hit) begin
                l2_was_hit = 1;
                $display("[TB t=%0t]   L2 %0s addr=0x%08h -> HIT",
                         $time, rotulo, endereco);
            end
            else begin
                l2_was_hit = 0;
                $display("[TB t=%0t]   L2 %0s addr=0x%08h -> MISS",
                         $time, rotulo, endereco);
            end

            @(negedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Fill da L1 controlado pela hierarquia
    // -------------------------------------------------------------------------
    task fill_l1;
        input [31:0] endereco;
        input [127:0] rotulo;

        begin
            @(negedge clk);
            l1_fill_valid = 1'b1;
            l1_fill_addr  = endereco;

            @(negedge clk);
            l1_fill_valid = 1'b0;
            l1_fill_addr  = 32'd0;

            $display("[TB t=%0t]   L1 fill controlado %0s addr=0x%08h",
                     $time, rotulo, endereco);

            @(negedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Acesso CPU -> L1 -> L2 se miss -> fill L1
    // -------------------------------------------------------------------------
    task cpu_acesso;
        input [31:0] endereco;
        input [31:0] pc;
        input [127:0] rotulo;
        input integer exp_l1_hit;
        input integer exp_l2_access;
        input integer exp_l2_hit;

        reg [31:0] l1_hits_before;
        reg [31:0] l1_misses_before;

        integer l1_was_hit;
        integer l2_was_hit;
        integer l2_accessed;

        begin
            l1_hits_before   = l1_hit_count;
            l1_misses_before = l1_miss_count;
            l2_accessed      = 0;
            l2_was_hit       = -1;

            @(negedge clk);
            l1_req_valid = 1'b1;
            l1_req_addr  = endereco;

            @(negedge clk);
            l1_req_valid = 1'b0;

            if(l1_hit_count > l1_hits_before) begin
                l1_was_hit = 1;
                $display("[TB t=%0t] CPU %0s addr=0x%08h -> L1 HIT",
                         $time, rotulo, endereco);
            end
            else if(l1_miss_count > l1_misses_before) begin
                l1_was_hit = 0;
                $display("[TB t=%0t] CPU %0s addr=0x%08h -> L1 MISS",
                         $time, rotulo, endereco);

                l2_accessed = 1;
                acessa_l2(endereco, pc, rotulo, l2_was_hit);

                // Fill da L1 somente depois da L2 responder.
                fill_l1(endereco, rotulo);
            end
            else begin
                $display("[ERRO t=%0t] CPU %0s nao alterou contador da L1",
                         $time, rotulo);
                $finish;
            end

            if(exp_l1_hit != -1 && l1_was_hit != exp_l1_hit) begin
                $display("[ERRO] %0s: L1 esperado=%0d veio=%0d",
                         rotulo, exp_l1_hit, l1_was_hit);
                $finish;
            end

            if(exp_l2_access != -1 && l2_accessed != exp_l2_access) begin
                $display("[ERRO] %0s: acesso L2 esperado=%0d veio=%0d",
                         rotulo, exp_l2_access, l2_accessed);
                $finish;
            end

            if(l2_accessed && exp_l2_hit != -1 && l2_was_hit != exp_l2_hit) begin
                $display("[ERRO] %0s: L2 hit esperado=%0d veio=%0d",
                         rotulo, exp_l2_hit, l2_was_hit);
                $finish;
            end

            @(negedge clk);
        end
    endtask

    initial begin
        $dumpfile("ondas_hierarchy_controlled_simple.vcd");
        $dumpvars(0, tb_hierarchy_controlled_simple);

        clk = 0;
        rst = 1;

        l1_req_valid  = 0;
        l1_req_addr   = 0;
        l1_fill_valid = 0;
        l1_fill_addr  = 0;

        l2_req_valid  = 0;
        l2_req_addr   = 0;
        l2_req_pc     = 0;

        @(negedge clk);
        @(negedge clk);
        rst = 0;
        @(negedge clk);

        $display("=========================================================");
        $display(" TESTE CONTROLADO SIMPLES L1 + L2 + HAWKEYE");
        $display("=========================================================");

        $display("\n--- FASE 1: A primeiro miss, depois hit ---");
        cpu_acesso(32'h00000000, 32'h0000_AAAA, "A-first", 0, 1, 0);
        cpu_acesso(32'h00000000, 32'h0000_AAAA, "A-again", 1, 0, -1);

        $display("\n--- FASE 2: L1 miss com L2 hit ---");
        cpu_acesso(32'h00000800, 32'h0000_BBBB, "B-first", 0, 1, 0);
        cpu_acesso(32'h00000000, 32'h0000_AAAA, "A-reuse", 1, 0, -1);
        cpu_acesso(32'h00001000, 32'h0000_CCCC, "C-first", 0, 1, 0);
        cpu_acesso(32'h00000800, 32'h0000_BBBB, "B-return", 0, 1, 1);
        cpu_acesso(32'h00000800, 32'h0000_BBBB, "B-again", 1, 0, -1);

        $display("---------------------------------------------------------");
        $display(" Totais finais:");
        $display(" L1: hits=%0d misses=%0d", l1_hit_count, l1_miss_count);
        $display(" L2: hits=%0d misses=%0d", l2_hit_count, l2_miss_count);
        $display(" Esperado:");
        $display(" L1: hits=3 misses=4");
        $display(" L2: hits=1 misses=3");
        $display("---------------------------------------------------------");

        if(l1_hit_count !== 32'd3 || l1_miss_count !== 32'd4) begin
            $display("[ERRO] Totais L1 inesperados.");
            $finish;
        end

        if(l2_hit_count !== 32'd1 || l2_miss_count !== 32'd3) begin
            $display("[ERRO] Totais L2 inesperados.");
            $finish;
        end

        $display("[OK] Teste controlado simples passou.");

        #20;
        $finish;
    end

endmodule   