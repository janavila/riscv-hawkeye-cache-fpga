// =============================================================================
// tb_cache_l2_hawkeye_averse.v
// -----------------------------------------------------------------------------
// Teste dirigido para validar propagacao friendly/averse ate o RRIP.
//
// Objetivo:
// - Forcar contador do Predictor para um PC friendly.
// - Forcar contador do Predictor para um PC averse.
// - Verificar se fill FRIENDLY entra com RRPV baixo.
// - Verificar se fill AVERSE entra com RRPV alto.
// - Encher o set e forcar eviction.
// - Conferir se a vitima tende a ser uma linha AVERSE.
// =============================================================================

`timescale 1ns/1ps

module tb_cache_l2_hawkeye_averse;

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

    localparam [31:0] PC_FRIENDLY = 32'h1111_0000;
    localparam [31:0] PC_AVERSE   = 32'h2222_0000;

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

    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Enderecos no mesmo set da L2.
    // offset = 6 bits, index = 6 bits.
    // Para manter set=0 e variar tag, usamos passo 0x1000.
    // -------------------------------------------------------------------------
    function [31:0] addr_set0;
        input integer tag_id;
        begin
            addr_set0 = tag_id * 32'h00001000;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Mesma hash usada pelo hawkeye_hash_index para descobrir predictor_index.
    // -------------------------------------------------------------------------
    function [10:0] hawkeye_index;
        input [63:0] value_in;
        integer i;
        reg [63:0] result;
        begin
            result = value_in;

            for(i = 0; i < 32; i = i + 1) begin
                if(result[0])
                    result = (result >> 1) ^ 64'd3988292384;
                else
                    result = result >> 1;
            end

            hawkeye_index = result[10:0];
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

    task set_predictor_counter;
        input [31:0] pc32;
        input [4:0]  value;
        reg [10:0] idx;
        begin
            idx = hawkeye_index({32'd0, pc32});

            // Acesso hierarquico apenas para teste dirigido.
            // Caminho: testbench -> pol -> hawkeye_core -> predictor_inst.
            pol.hawkeye_core.predictor_inst.predictor_table[idx] = value;

            $display("[TB t=%0t] FORCE predictor pc=0x%08h index=%0d counter=%0d",
                     $time, pc32, idx, value);
        end
    endtask

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

    initial begin
        $dumpfile("ondas_l2_hawkeye_averse.vcd");
        $dumpvars(0, tb_cache_l2_hawkeye_averse);

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
        $display(" TESTE DIRIGIDO L2 + HAWKEYE: FRIENDLY vs AVERSE");
        $display("=========================================================");

        // Forca os contadores para garantir comportamento divergente.
        // counter 31 -> friendly
        // counter 0  -> averse
        set_predictor_counter(PC_FRIENDLY, 5'd31);
        set_predictor_counter(PC_AVERSE,   5'd0);

        espera_ciclos(2);

        // ---------------------------------------------------------------------
        // FASE 1: preencher set 0 alternando PC friendly e PC averse.
        // Esperado:
        // - fills com PC_FRIENDLY -> fill FRIENDLY rrpv=2
        // - fills com PC_AVERSE   -> fill AVERSE rrpv=6
        // ---------------------------------------------------------------------
        $display("\n--- FASE 1: fills alternando friendly/averse ---");

        for(i = 0; i < 8; i = i + 1) begin
            if(i[0] == 1'b0) begin
                set_predictor_counter(PC_FRIENDLY, 5'd31);
                acesso(addr_set0(i), PC_FRIENDLY, "fill-friendly");
            end
            else begin
                set_predictor_counter(PC_AVERSE, 5'd0);
                acesso(addr_set0(i), PC_AVERSE, "fill-averse");
            end
        end

        espera_ciclos(10);

        $display("\n--- CHECK RRPV apos fills ---");
        $display("RRPV way0 esperado friendly baixo = %0d", pol.rrpv_table[0][0]);
        $display("RRPV way1 esperado averse alto    = %0d", pol.rrpv_table[0][1]);

        if(pol.rrpv_table[0][0] != 3'd2) begin
            $display("[ERRO] way0 deveria ser FRIENDLY com RRPV=2, mas veio %0d",
                     pol.rrpv_table[0][0]);
            $finish;
        end

        if(pol.rrpv_table[0][1] != 3'd6) begin
            $display("[ERRO] way1 deveria ser AVERSE com RRPV=6, mas veio %0d",
                     pol.rrpv_table[0][1]);
            $finish;
        end

        // ---------------------------------------------------------------------
        // FASE 2: acessar novo bloco no set cheio.
        // Como as linhas averse estao com RRPV maior, apos aging a vitima
        // esperada deve ser uma das vias averse. Como o primeiro averse esta
        // na way1, esperamos victim way1.
        // ---------------------------------------------------------------------
        $display("\n--- FASE 2: eviction deve preferir linha AVERSE ---");

        set_predictor_counter(PC_FRIENDLY, 5'd31);
        acesso(addr_set0(8), PC_FRIENDLY, "new-after-averse");

        espera_ciclos(10);

        $display("---------------------------------------------------------");
        $display(" Total L2: hits=%0d misses=%0d", hit_count, miss_count);
        $display(" Teste esperado:");
        $display(" - aparecer fill FRIENDLY");
        $display(" - aparecer fill AVERSE");
        $display(" - vitima RRIP deve tender a uma via AVERSE, idealmente way=1");
        $display("---------------------------------------------------------");

        #20;
        $finish;
    end

endmodule   