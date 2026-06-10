// =============================================================================
// tb_cache_l1_stress.v
// -----------------------------------------------------------------------------
// Testbench de stress para validar a L1 isolada com LRU.
//
// Objetivos:
// - fill inicial;
// - hit apos fill;
// - conflito no mesmo set;
// - substituicao por LRU;
// - hotset com reutilizacao;
// - streaming sem reutilizacao;
// - multiplos sets independentes.
// =============================================================================

`timescale 1ns/1ps

module tb_cache_l1_stress;

    reg         clk;
    reg         rst;
    reg         req_valid;
    reg  [31:0] req_addr;

    wire        hit;
    wire        miss;
    wire [31:0] hit_count;
    wire [31:0] miss_count;

    cache_l1 dut (
        .clk(clk),
        .rst(rst),
        .req_valid(req_valid),
        .req_addr(req_addr),
        .hit(hit),
        .miss(miss),
        .hit_count(hit_count),
        .miss_count(miss_count)
    );

    always #5 clk = ~clk;

    // L1: bloco 32 bytes -> offset 5 bits.
    // 64 sets -> index 6 bits.
    // Para manter set=0 e variar tag, passo = 2^(5+6) = 2048 = 0x800.
    function [31:0] addr_set0;
        input integer tag_id;
        begin
            addr_set0 = tag_id * 32'h00000800;
        end
    endfunction

    // Para variar o set mantendo tag baixa:
    // endereco = set_id << 5.
    function [31:0] addr_set;
        input integer set_id;
        begin
            addr_set = set_id * 32'h00000020;
        end
    endfunction

    task acesso;
        input [31:0] endereco;
        input [127:0] rotulo;
    
        reg [31:0] hits_before;
        reg [31:0] misses_before;
    
        begin
            hits_before   = hit_count;
            misses_before = miss_count;
    
            @(negedge clk);
            req_valid = 1'b1;
            req_addr  = endereco;
    
            @(negedge clk);
            req_valid = 1'b0;
    
            if(hit_count > hits_before) begin
                $display("[TB t=%0t] acesso %0s addr=0x%08h -> HIT",
                         $time, rotulo, endereco);
            end
            else if(miss_count > misses_before) begin
                $display("[TB t=%0t] acesso %0s addr=0x%08h -> MISS",
                         $time, rotulo, endereco);
            end
            else begin
                $display("[ERRO t=%0t] acesso %0s addr=0x%08h nao alterou contador",
                         $time, rotulo, endereco);
                $finish;
            end
    
            @(negedge clk);
        end
    endtask
    task check_total;
        input [31:0] exp_hits;
        input [31:0] exp_misses;
        begin
            if(hit_count !== exp_hits || miss_count !== exp_misses) begin
                $display("[ERRO] Contadores incorretos. Esperado hits=%0d misses=%0d | Veio hits=%0d misses=%0d",
                         exp_hits, exp_misses, hit_count, miss_count);
                $finish;
            end
            else begin
                $display("[OK] Contadores batem: hits=%0d misses=%0d", hit_count, miss_count);
            end
        end
    endtask

    integer i;
    integer r;

    initial begin
        $dumpfile("ondas_l1_stress.vcd");
        $dumpvars(0, tb_cache_l1_stress);

        clk = 0;
        rst = 1;
        req_valid = 0;
        req_addr = 0;

        @(negedge clk);
        @(negedge clk);
        rst = 0;
        @(negedge clk);

        $display("=========================================================");
        $display(" TESTE STRESS L1 + LRU");
        $display("=========================================================");

        // ---------------------------------------------------------------------
        // FASE 1: fill + hit simples
        // Esperado: MISS depois HIT
        // ---------------------------------------------------------------------
        $display("\n--- FASE 1: fill + hit simples ---");
        acesso(32'h00000000, "A-first");   // miss
        acesso(32'h00000000, "A-again");   // hit

        // ---------------------------------------------------------------------
        // FASE 2: conflito em set 0 para L1 2-way
        // addr_set0(0), addr_set0(1), addr_set0(2) caem no mesmo set.
        // A terceira entrada deve causar substituicao.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 2: conflito no mesmo set ---");
        acesso(addr_set0(1), "B-fill");    // miss, ocupa segunda via
        acesso(addr_set0(0), "A-reuse");   // hit, A fica recente
        acesso(addr_set0(2), "C-new");     // miss, deve expulsar B se LRU correto

        // Agora A deve continuar e B provavelmente saiu.
        acesso(addr_set0(0), "A-check");   // esperado hit
        acesso(addr_set0(1), "B-check");   // esperado miss se B foi expulso

        // ---------------------------------------------------------------------
        // FASE 3: hotset pequeno.
        // Depois dos fills, deve dar muitos hits.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 3: hotset reutilizavel ---");
        acesso(addr_set(10), "hot-X-fill"); // miss
        acesso(addr_set(11), "hot-Y-fill"); // miss
        acesso(addr_set(12), "hot-Z-fill"); // miss

        for(r = 0; r < 5; r = r + 1) begin
            acesso(addr_set(10), "hot-X");
            acesso(addr_set(11), "hot-Y");
            acesso(addr_set(12), "hot-Z");
        end

        // ---------------------------------------------------------------------
        // FASE 4: streaming em sets diferentes.
        // Acessos únicos devem gerar muitos misses.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 4: streaming em varios sets ---");
        for(i = 20; i < 36; i = i + 1) begin
            acesso(addr_set(i), "stream");
        end

        // ---------------------------------------------------------------------
        // FASE 5: checar independência de sets.
        // Reacessa hotset depois do streaming em outros sets.
        // Como o streaming usou sets 20..35, os sets 10..12 não deveriam ser afetados.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 5: reuso apos streaming em outros sets ---");
        acesso(addr_set(10), "hot-X-return");
        acesso(addr_set(11), "hot-Y-return");
        acesso(addr_set(12), "hot-Z-return");

        $display("---------------------------------------------------------");
        $display(" Total L1: hits=%0d  misses=%0d", hit_count, miss_count);
        $display(" O teste deve ter hits e misses.");
        $display(" Se A-check foi HIT e B-check foi MISS, o LRU no conflito basico esta coerente.");
        $display("---------------------------------------------------------");

        if(hit_count == 0) begin
            $display("[ERRO] Nenhum hit ocorreu na L1.");
            $finish;
        end

        if(miss_count == 0) begin
            $display("[ERRO] Nenhum miss ocorreu na L1.");
            $finish;
        end

        #20;
        $finish;
    end

endmodule   