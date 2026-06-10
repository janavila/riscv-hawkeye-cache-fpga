// =============================================================================
// tb_cache_l2.v
// -----------------------------------------------------------------------------
// Testbench da L2. Mostra DUAS coisas importantes:
//   1) Como a L2 (FSM) e o modulo de politica se conectam pela interface aberta.
//      Repare que aqui no testbench nos instanciamos a L2 E o lru_policy_l2 e
//      ligamos os fios pol_* entre eles. Quando o Hawkeye entrar, o colega
//      troca a instancia de lru_policy_l2 por hawkeye_top - os fios sao os mesmos.
//   2) Como dirigir um modulo FSM com handshake: poe req_valid e espera 'done'.
//
// Como a L2 e multi-ciclo, NAO lemos hit/miss no mesmo ciclo. Damos o pedido
// e esperamos o pulso 'done'; nesse momento hit/miss estao validos.
//
// Conjunto usado no teste: index dos 8 enderecos abaixo cai todo no MESMO
// conjunto, para enchermos as 8 vias e forcar substituicao no 9o endereco.
//   offset = bits [5:0], index = bits [11:6], tag = bits [31:12].
//   Para manter index fixo (=0) e variar a tag, andamos de 0x1000 em 0x1000
//   (bit 12 = primeira posicao de tag).
// =============================================================================

`timescale 1ns/1ps

module tb_cache_l2;

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

    // fios da interface de politica (ligam L2 <-> politica)
    wire [5:0]  pol_set;
    wire [31:0] pol_pc;
    wire        pol_access;
    wire        pol_hit;
    wire [2:0]  pol_hit_way;
    wire        pol_need_victim;
    wire [2:0]  pol_victim_way;
    wire        pol_victim_valid;
    wire [31:0] pol_addr;
    wire        pol_fill;
    wire [2:0]  pol_fill_way;

    // ------ instancia da L2 ------
        // ------ instancia da L2 ------
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
        .pol_victim_way(pol_victim_way),
        .pol_victim_valid(pol_victim_valid),
        .pol_fill(pol_fill),
        .pol_fill_way(pol_fill_way),

        .hit_count(hit_count),
        .miss_count(miss_count)
    );

    // ------ instancia da POLITICA (placeholder LRU) ------
    // >>> E AQUI que o colega vai trocar para hawkeye_top no futuro <<<
        // ------ instancia da POLITICA (placeholder LRU) ------
    //lru_policy_l2 pol (
    //    .clk(clk),
    //    .rst(rst),
//
    //    .pol_set(pol_set),
    //    .pol_pc(pol_pc),
    //    .pol_access(pol_access),
    //    .pol_hit(pol_hit),
    //    .pol_hit_way(pol_hit_way),
    //    .pol_need_victim(pol_need_victim),
//
    //    .pol_victim_way(pol_victim_way),
    //    .pol_victim_valid(pol_victim_valid)
    //);

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

    // ------ clock ------
    always #5 clk = ~clk;

    // ------ tarefa: envia 1 acesso e espera a FSM concluir (done) ------
    task acesso(input [31:0] endereco, input [31:0] pc, input [127:0] rotulo);
        begin
            @(negedge clk);
            req_valid = 1'b1;
            req_addr  = endereco;
            req_pc    = pc;
            @(negedge clk);
            req_valid = 1'b0;        // pedido dura 1 ciclo; a FSM assume daqui
            // espera o pulso done
            wait (done == 1'b1);
            $display("[t=%0t] acesso %0s addr=0x%08h -> %s",
                     $time, rotulo, endereco, hit ? "HIT " : "MISS");
            @(negedge clk);
        end
    endtask
    task espera_ciclos(input integer n);
        integer j;
        begin
            for(j = 0; j < n; j = j + 1) begin
                @(negedge clk);
            end
        end
    endtask

    integer i;
    initial begin
        $dumpfile("ondas_l2.vcd");
        $dumpvars(0, tb_cache_l2);

        clk = 0; rst = 1; req_valid = 0; req_addr = 0; req_pc = 0;
        @(negedge clk); @(negedge clk);
        rst = 0;
        @(negedge clk);

        $display("=========================================================");
        $display(" Teste da L2 (8 vias, FSM, interface de politica aberta)");
        $display("=========================================================");

        // Enche as 8 vias do conjunto 0 com tags diferentes: todas MISS.
        for (i = 0; i < 8; i = i + 1)
            acesso(i * 32'h00001000, 32'h0000_0000 + i, "fill");

        // Reacessa o primeiro endereco (tag 0): deve ser HIT (ainda esta la).
        acesso(32'h00000000, 32'hAAAA, "re-0");        // esperado HIT

        // Novo endereco no mesmo conjunto (tag 8): set cheio -> MISS + despejo.
        // A politica LRU escolhe a via mais velha para despejar.
        acesso(32'h00008000, 32'hBBBB, "new-8");       // esperado MISS

        // Reacessa o endereco 0x1000.
        // Como no teste anterior o RRIP escolheu a way 1 como vitima,
        // esse bloco provavelmente foi removido. Entao esperamos MISS.
        acesso(32'h00001000, 32'h00000001, "re-1-evicted");
        espera_ciclos(20);
        
        acesso(32'h00001000, 32'h00000001, "re-1-again");
        espera_ciclos(20);$display("---------------------------------------------------------");
        $display(" Total: hits=%0d  misses=%0d", hit_count, miss_count);       
        $display(" Esperado: 8 fills (miss) + 1 hit + 1 miss + 1 miss + 1 hit = hits=2 misses=10");        $display("---------------------------------------------------------");

        #20;
        $finish;
    end

endmodule
// ===== fim do tb_cache_l2.v =====
