// =============================================================================
// tb_cache_l2_hawkeye_stress.v
// -----------------------------------------------------------------------------
// Testbench maior para validar L2 + Hawkeye.
// Foco:
// - handshake L2 <-> politica;
// - fills;
// - hits;
// - misses;
// - substituicao por RRIP;
// - integracao com hawkeye_top;
// - sampler_hit;
// - training_done;
// - comportamento com hotset e streaming.
// =============================================================================

`timescale 1ns/1ps

module tb_cache_l2_hawkeye_stress;

    reg         clk;
    reg         rst;
    reg         req_valid;
    reg  [31:0] req_addr;
    reg  [31:0] req_pc;

    wire        done;
    wire        hit;
    wire        miss;
    wire [31:0] hit_count;
    wire [31:0] miss_count;

    // Interface L2 <-> politica
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

    // -------------------------------------------------------------------------
    // L2
    // -------------------------------------------------------------------------
    cache_l2 dut (
        .clk(clk),
        .rst(rst),

        .req_valid(req_valid),
        .req_addr(req_addr),
        .req_pc(req_pc),

        .done(done),
        .hit(hit),
        .miss(miss),

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

        .hit_count(hit_count),
        .miss_count(miss_count)
    );

    // -------------------------------------------------------------------------
    // Politica Hawkeye + RRIP
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Enderecos no mesmo set da L2.
    // L2: offset = 6 bits, index = 6 bits.
    // Para manter set=0 e variar tag, usamos passos de 0x1000.
    // -------------------------------------------------------------------------
    function [31:0] addr_set0;
        input integer tag_id;
        begin
            addr_set0 = tag_id * 32'h00001000;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Espera n ciclos
    // -------------------------------------------------------------------------
    task espera_ciclos;
        input integer n;
        integer j;
        begin
            for(j = 0; j < n; j = j + 1) begin
                @(negedge clk);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Envia um acesso e espera done com timeout.
    // -------------------------------------------------------------------------
    task acesso;
        input [31:0] endereco;
        input [31:0] pc;
        input [127:0] rotulo;

        integer timeout;
        begin
            @(negedge clk);
            req_valid = 1'b1;
            req_addr  = endereco;
            req_pc    = pc;

            @(negedge clk);
            req_valid = 1'b0;

            timeout = 0;
            while(done !== 1'b1 && timeout < 200) begin
                @(negedge clk);
                timeout = timeout + 1;
            end

            if(timeout >= 200) begin
                $display("[ERRO t=%0t] TIMEOUT no acesso %0s addr=0x%08h pc=0x%08h",
                         $time, rotulo, endereco, pc);
                $finish;
            end

            $display("[TB t=%0t] acesso %0s addr=0x%08h pc=0x%08h -> %s",
                     $time, rotulo, endereco, pc, hit ? "HIT " : "MISS");

            @(negedge clk);
        end
    endtask

    integer i;
    integer r;

    initial begin
        $dumpfile("ondas_l2_hawkeye_stress.vcd");
        $dumpvars(0, tb_cache_l2_hawkeye_stress);

        clk = 0;
        rst = 1;
        req_valid = 0;
        req_addr = 0;
        req_pc = 0;

        @(negedge clk);
        @(negedge clk);
        rst = 0;
        @(negedge clk);

        $display("=========================================================");
        $display(" TESTE STRESS L2 + HAWKEYE");
        $display("=========================================================");

        // ---------------------------------------------------------------------
        // FASE 1: preencher as 8 vias do set 0.
        // Esperado: 8 misses e fills.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 1: fill do set 0 ---");
        for(i = 0; i < 8; i = i + 1) begin
            acesso(addr_set0(i), 32'h0000_1000 + i, "fill-set0");
        end

        // ---------------------------------------------------------------------
        // FASE 2: hit em bloco existente.
        // Esperado: hit e RRPV da via protegida indo para 0.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 2: hit apos fill ---");
        acesso(addr_set0(0), 32'h0000_AAAA, "hit-reuse-0");

        // ---------------------------------------------------------------------
        // FASE 3: novo bloco no set cheio.
        // Esperado: miss, pedido de vitima, aging, vitima valida e fill.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 3: eviction por RRIP/Hawkeye ---");
        acesso(addr_set0(8), 32'h0000_BBBB, "new-block-8");

        // ---------------------------------------------------------------------
        // FASE 4: reaccess de bloco provavelmente despejado.
        // Objetivo: gerar sampler_hit e training_done.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 4: reaccess de bloco despejado ---");
        acesso(addr_set0(1), 32'h0000_1001, "reaccess-1-evicted");
        espera_ciclos(20);

        acesso(addr_set0(1), 32'h0000_1001, "reaccess-1-again");
        espera_ciclos(20);

        // ---------------------------------------------------------------------
        // FASE 5: hotset com reutilizacao.
        // Usa poucos blocos repetidos para criar localidade.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 5: hotset reutilizavel ---");
        for(r = 0; r < 5; r = r + 1) begin
            acesso(addr_set0(20), 32'h0000_2000, "hot-A");
            acesso(addr_set0(21), 32'h0000_2001, "hot-B");
            acesso(addr_set0(22), 32'h0000_2002, "hot-C");
            acesso(addr_set0(23), 32'h0000_2003, "hot-D");
            espera_ciclos(5);
        end

        // ---------------------------------------------------------------------
        // FASE 6: streaming/conflito.
        // Muitos blocos diferentes no mesmo set.
        // Objetivo: forcar evictions e dar oportunidade ao Hawkeye de diferenciar.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 6: streaming no mesmo set ---");
        for(i = 100; i < 124; i = i + 1) begin
            acesso(addr_set0(i), 32'h0000_3000, "stream");
        end

        espera_ciclos(50);

        // ---------------------------------------------------------------------
        // FASE 7: voltar ao hotset.
        // Objetivo: ver se os blocos com reutilizacao sobrevivem ou sao
        // reintroduzidos e treinados.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 7: volta ao hotset ---");
        for(r = 0; r < 3; r = r + 1) begin
            acesso(addr_set0(20), 32'h0000_2000, "hot-A-return");
            acesso(addr_set0(21), 32'h0000_2001, "hot-B-return");
            acesso(addr_set0(22), 32'h0000_2002, "hot-C-return");
            acesso(addr_set0(23), 32'h0000_2003, "hot-D-return");
            espera_ciclos(5);
        end

        espera_ciclos(50);

        $display("---------------------------------------------------------");
        $display(" Total final L2: hits=%0d  misses=%0d", hit_count, miss_count);
        $display(" Observacoes esperadas:");
        $display(" - Deve haver hits e misses.");
        $display(" - Deve aparecer sampler_hit=1 em alguns reusos.");
        $display(" - Deve aparecer TRAINING DONE no log.");
        $display(" - Deve aparecer pedido de vitima e vitima RRIP pronta.");
        $display("---------------------------------------------------------");

        if(hit_count == 0) begin
            $display("[ERRO] Nenhum hit ocorreu no teste stress.");
            $finish;
        end

        if(miss_count == 0) begin
            $display("[ERRO] Nenhum miss ocorreu no teste stress.");
            $finish;
        end

        #20;
        $finish;
    end

endmodule   