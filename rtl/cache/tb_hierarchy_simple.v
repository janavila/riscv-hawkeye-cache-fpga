// =============================================================================
// tb_hierarchy_simple.v
// -----------------------------------------------------------------------------
// Teste simples da hierarquia L1 + L2 + Hawkeye.
//
// IMPORTANTE:
// - A L1 atual ainda se auto-preenche em miss.
// - Portanto este teste valida o fluxo funcional:
//      CPU -> L1
//      se L1 MISS -> acessa L2
//      se L1 HIT  -> nao acessa L2
//
// Este ainda NAO e o modelo hierarquico final com fill controlado.
// =============================================================================

`timescale 1ns/1ps

module tb_hierarchy_simple;

    reg clk;
    reg rst;

    // ---------------- L1 ----------------
    reg         l1_req_valid;
    reg  [31:0] l1_req_addr;
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

    // ---------------- Instancia L1 ----------------
    cache_l1 l1 (
        .clk(clk),
        .rst(rst),
        .req_valid(l1_req_valid),
        .req_addr(l1_req_addr),
        .hit(l1_hit),
        .miss(l1_miss),
        .hit_count(l1_hit_count),
        .miss_count(l1_miss_count)
    );

    // ---------------- Instancia L2 ----------------
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

    // ---------------- Politica Hawkeye da L2 ----------------
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
    // Acesso direto na L2. Usado apenas quando a L1 deu miss.
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
                $display("[ERRO t=%0t] TIMEOUT L2 no acesso %0s addr=0x%08h",
                         $time, rotulo, endereco);
                $finish;
            end

            if(l2_hit) begin
                l2_was_hit = 1;
                $display("[TB t=%0t]   L2 acesso %0s addr=0x%08h -> HIT",
                         $time, rotulo, endereco);
            end
            else begin
                l2_was_hit = 0;
                $display("[TB t=%0t]   L2 acesso %0s addr=0x%08h -> MISS",
                         $time, rotulo, endereco);
            end

            @(negedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Acesso da CPU na hierarquia:
    // - consulta L1;
    // - se L1 miss, consulta L2.
    //
    // exp_l1_hit:
    //   1 = espera L1 HIT
    //   0 = espera L1 MISS
    //  -1 = nao checa
    //
    // exp_l2_access:
    //   1 = espera que L2 seja acessada
    //   0 = espera que L2 nao seja acessada
    //  -1 = nao checa
    //
    // exp_l2_hit:
    //   1 = espera L2 HIT
    //   0 = espera L2 MISS
    //  -1 = nao checa
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
        $dumpfile("ondas_hierarchy_simple.vcd");
        $dumpvars(0, tb_hierarchy_simple);

        clk = 0;
        rst = 1;

        l1_req_valid = 0;
        l1_req_addr  = 0;

        l2_req_valid = 0;
        l2_req_addr  = 0;
        l2_req_pc    = 0;

        @(negedge clk);
        @(negedge clk);
        rst = 0;
        @(negedge clk);

        $display("=========================================================");
        $display(" TESTE SIMPLES HIERARQUIA L1 + L2 + HAWKEYE");
        $display("=========================================================");

        // ---------------------------------------------------------------------
        // FASE 1:
        // Primeiro acesso a A:
        //   L1 MISS
        //   L2 MISS
        // Segundo acesso a A:
        //   L1 HIT
        //   L2 nao deve ser acessada
        // ---------------------------------------------------------------------
        $display("\n--- FASE 1: Acesso repetido ao mesmo endereco ---");

        cpu_acesso(32'h00000000, 32'h0000_AAAA, "A-first", -1, 1, 0);
        cpu_acesso(32'h00000000, 32'h0000_AAAA, "A-again", 1, 0, -1);

        // ---------------------------------------------------------------------
        // FASE 2:
        // Usa enderecos que conflitam na L1 2-way:
        // A = 0x0000
        // B = 0x0800
        // C = 0x1000
        //
        // A e B entram na L1.
        // A e reutilizado.
        // C entra e deve expulsar B da L1.
        // Depois B volta:
        //   L1 MISS
        //   L2 HIT, porque B ainda estava na L2.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 2: L1 MISS + L2 HIT ---");

        cpu_acesso(32'h00000800, 32'h0000_BBBB, "B-first", 0, 1, 0);
        cpu_acesso(32'h00000000, 32'h0000_AAAA, "A-reuse", 1, 0, -1);
        cpu_acesso(32'h00001000, 32'h0000_CCCC, "C-first", 0, 1, 0);
        cpu_acesso(32'h00000800, 32'h0000_BBBB, "B-return", 0, 1, 1);

        // Agora B acabou de voltar para a L1, entao deve ser HIT.
        cpu_acesso(32'h00000800, 32'h0000_BBBB, "B-again", 1, 0, -1);

        $display("---------------------------------------------------------");
        $display(" Totais finais:");
        $display(" L1: hits=%0d misses=%0d", l1_hit_count, l1_miss_count);
        $display(" L2: hits=%0d misses=%0d", l2_hit_count, l2_miss_count);
        $display(" Esperado aproximado neste teste:");
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

        $display("[OK] Teste simples da hierarquia passou.");

        #20;
        $finish;
    end

endmodule   