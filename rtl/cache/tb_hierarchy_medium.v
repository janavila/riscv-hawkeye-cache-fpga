// =============================================================================
// tb_hierarchy_medium.v
// -----------------------------------------------------------------------------
// Teste medio da hierarquia L1 + L2 + Hawkeye.
//
// Ainda usa a L1 atual, que se auto-preenche em miss.
// Objetivo:
// - validar L1 HIT sem acessar L2;
// - validar L1 MISS acionando L2;
// - gerar L2 HIT apos expulsao da L1;
// - gerar L2 MISS e substituicoes na L2;
// - exercitar Hawkeye/RRIP com mais acessos;
// - checar sanidade: acessos_L2 == misses_L1.
// =============================================================================

`timescale 1ns/1ps

module tb_hierarchy_medium;

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

    integer cpu_access_count;
    integer l2_access_count;

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

    // L1: bloco 32 bytes, 64 sets -> mesmo set da L1 usando passo 0x800.
    function [31:0] addr_l1_set0;
        input integer tag_id;
        begin
            addr_l1_set0 = tag_id * 32'h00000800;
        end
    endfunction

    // L2: bloco 64 bytes, 64 sets -> mesmo set da L2 usando passo 0x1000.
    function [31:0] addr_l2_set0;
        input integer tag_id;
        begin
            addr_l2_set0 = tag_id * 32'h00001000;
        end
    endfunction

    task espera_ciclos;
        input integer n;
        integer j;
        begin
            for(j = 0; j < n; j = j + 1)
                @(negedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Acesso direto na L2. Chamado apenas quando a L1 deu miss.
    // -------------------------------------------------------------------------
    task acessa_l2;
        input [31:0] endereco;
        input [31:0] pc;
        input [127:0] rotulo;
        output integer l2_was_hit;

        integer timeout;

        begin
            l2_access_count = l2_access_count + 1;

            @(negedge clk);
            l2_req_valid = 1'b1;
            l2_req_addr  = endereco;
            l2_req_pc    = pc;

            @(negedge clk);
            l2_req_valid = 1'b0;

            timeout = 0;
            while(l2_done !== 1'b1 && timeout < 500) begin
                @(negedge clk);
                timeout = timeout + 1;
            end

            if(timeout >= 500) begin
                $display("[ERRO t=%0t] TIMEOUT L2 no acesso %0s addr=0x%08h",
                         $time, rotulo, endereco);
                $finish;
            end

            if(l2_hit) begin
                l2_was_hit = 1;
                $display("[TB t=%0t]   L2 %0s addr=0x%08h pc=0x%08h -> HIT",
                         $time, rotulo, endereco, pc);
            end
            else begin
                l2_was_hit = 0;
                $display("[TB t=%0t]   L2 %0s addr=0x%08h pc=0x%08h -> MISS",
                         $time, rotulo, endereco, pc);
            end

            @(negedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Acesso da CPU na hierarquia.
    // Se L1 miss, acessa L2.
    //
    // exp_l1_hit:
    //   1 = espera L1 HIT
    //   0 = espera L1 MISS
    //  -1 = nao checa
    //
    // exp_l2_access:
    //   1 = espera L2 acessada
    //   0 = espera L2 nao acessada
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
            cpu_access_count = cpu_access_count + 1;

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

    integer i;
    integer r;

    initial begin
        $dumpfile("ondas_hierarchy_medium.vcd");
        $dumpvars(0, tb_hierarchy_medium);

        clk = 0;
        rst = 1;

        l1_req_valid = 0;
        l1_req_addr  = 0;

        l2_req_valid = 0;
        l2_req_addr  = 0;
        l2_req_pc    = 0;

        cpu_access_count = 0;
        l2_access_count  = 0;

        @(negedge clk);
        @(negedge clk);
        rst = 0;
        @(negedge clk);

        $display("=========================================================");
        $display(" TESTE MEDIO HIERARQUIA L1 + L2 + HAWKEYE");
        $display("=========================================================");

        // ---------------------------------------------------------------------
        // FASE 1: sanidade simples
        // A primeiro: L1 miss, L2 miss
        // A de novo: L1 hit, L2 nao acessada
        // ---------------------------------------------------------------------
        $display("\n--- FASE 1: sanidade simples ---");
        cpu_acesso(32'h00000000, 32'h0000_AAAA, "A-first", 0, 1, 0);
        cpu_acesso(32'h00000000, 32'h0000_AAAA, "A-again", 1, 0, -1);

        // ---------------------------------------------------------------------
        // FASE 2: conflito basico na L1 e L2 hit
        // A, B, C caem no mesmo set da L1.
        // B volta depois de ser expulso da L1, mas deve estar na L2.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 2: conflito L1 com L2 HIT ---");
        cpu_acesso(addr_l1_set0(1), 32'h0000_BBBB, "B-first", 0, 1, 0);
        cpu_acesso(addr_l1_set0(0), 32'h0000_AAAA, "A-reuse", 1, 0, -1);
        cpu_acesso(addr_l1_set0(2), 32'h0000_CCCC, "C-first", 0, 1, 0);
        cpu_acesso(addr_l1_set0(1), 32'h0000_BBBB, "B-return", 0, 1, 1);
        cpu_acesso(addr_l1_set0(1), 32'h0000_BBBB, "B-again", 1, 0, -1);

        // ---------------------------------------------------------------------
        // FASE 3: pressao no set 0 da L2.
        // Muitos enderecos no mesmo set da L2, forçando misses e evictions.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 3: pressao no set 0 da L2 ---");
        for(i = 2; i < 14; i = i + 1) begin
            cpu_acesso(addr_l2_set0(i), 32'h0000_3000 + i, "l2-set0-stream", 0, 1, -1);
        end

        espera_ciclos(20);

        // ---------------------------------------------------------------------
        // FASE 4: hot trio que causa conflito na L1, mas tende a bater na L2.
        // Sao 3 blocos no mesmo set da L1, entao a L1 2-way deve sofrer.
        // Depois do primeiro ciclo, a L2 deve ter muitos hits.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 4: hot trio com L1 thrashing e L2 reuso ---");
        for(r = 0; r < 5; r = r + 1) begin
            cpu_acesso(32'h00020000, 32'h0000_4000, "hot0", -1, -1, -1);
            cpu_acesso(32'h00020800, 32'h0000_4001, "hot1", -1, -1, -1);
            cpu_acesso(32'h00021000, 32'h0000_4002, "hot2", -1, -1, -1);
            espera_ciclos(3);
        end

        espera_ciclos(30);

        // ---------------------------------------------------------------------
        // FASE 5: reuso de alguns blocos do streaming.
        // Aqui nao forçamos esperado exato porque o RRIP/Hawkeye pode ter
        // escolhido vitimas diferentes. Queremos garantir que nao trava e que
        // os contadores permanecem coerentes.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 5: reuso apos pressao ---");
        cpu_acesso(addr_l2_set0(4),  32'h0000_3004, "reuse-stream-4",  -1, -1, -1);
        cpu_acesso(addr_l2_set0(8),  32'h0000_3008, "reuse-stream-8",  -1, -1, -1);
        cpu_acesso(addr_l2_set0(12), 32'h0000_300C, "reuse-stream-12", -1, -1, -1);

        espera_ciclos(50);

        $display("---------------------------------------------------------");
        $display(" Totais finais:");
        $display(" CPU acessos controlados = %0d", cpu_access_count);
        $display(" L2 acessos controlados  = %0d", l2_access_count);
        $display(" L1: hits=%0d misses=%0d", l1_hit_count, l1_miss_count);
        $display(" L2: hits=%0d misses=%0d", l2_hit_count, l2_miss_count);
        $display("---------------------------------------------------------");

        // ---------------------------------------------------------------------
        // Checks de sanidade
        // ---------------------------------------------------------------------
        if(l1_hit_count == 0 || l1_miss_count == 0) begin
            $display("[ERRO] L1 deveria ter hits e misses.");
            $finish;
        end

        if(l2_hit_count == 0 || l2_miss_count == 0) begin
            $display("[ERRO] L2 deveria ter hits e misses.");
            $finish;
        end

        if(l2_access_count !== l1_miss_count) begin
            $display("[ERRO] Acessos L2 (%0d) diferente de misses L1 (%0d).",
                     l2_access_count, l1_miss_count);
            $finish;
        end

        if((l2_hit_count + l2_miss_count) !== l2_access_count) begin
            $display("[ERRO] Hits+misses L2 (%0d) diferente de acessos L2 (%0d).",
                     l2_hit_count + l2_miss_count, l2_access_count);
            $finish;
        end

        $display("[OK] Teste medio da hierarquia passou.");

        #20;
        $finish;
    end

endmodule   