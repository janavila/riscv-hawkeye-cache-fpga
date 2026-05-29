// =============================================================================
// tb_cache_l1.v
// -----------------------------------------------------------------------------
// Testbench da cache L1. Aplica uma sequencia de enderecos escolhida a dedo
// para exercitar: miss de compulsorio, hit, conflito nas 2 vias do mesmo
// conjunto, e substituicao por LRU.
//
// Como a L1 e single-cycle, cada acesso ocupa 1 ciclo de clock: colocamos
// req_valid=1 e req_addr=<endereco> e, na proxima borda, o estado atualiza.
// Lemos hit/miss combinacionalmente ANTES da borda (no mesmo ciclo).
//
// MAPA DE ENDERECOS (para entender o teste):
//   offset = bits [4:0], index = bits [10:5], tag = bits [31:11].
//   Para forcar o MESMO conjunto (index) e variar a tag, mudamos os bits
//   altos mantendo os bits [10:5] iguais.
//
//   Vamos usar o conjunto 0 (index=0). Enderecos com index=0:
//     A = 0x00000000  -> tag 0, set 0
//     B = 0x00000800  -> tag 1, set 0   (0x800 = bit 11 = primeira tag acima)
//     C = 0x00001000  -> tag 2, set 0
//   Como o conjunto tem 2 vias, A e B cabem juntos; trazer C forca despejo.
// =============================================================================

`timescale 1ns/1ps

module tb_cache_l1;

    // ------ sinais para o DUT ------
    reg         clk;
    reg         rst;
    reg         req_valid;
    reg  [31:0] req_addr;
    wire        hit;
    wire        miss;
    wire [31:0] hit_count;
    wire [31:0] miss_count;

    // ------ instancia da L1 ------
    cache_l1 dut (
        .clk        (clk),
        .rst        (rst),
        .req_valid  (req_valid),
        .req_addr   (req_addr),
        .hit        (hit),
        .miss       (miss),
        .hit_count  (hit_count),
        .miss_count (miss_count)
    );

    // ------ clock de 10 ns ------
    always #5 clk = ~clk;

    // ------ tarefa auxiliar: aplica 1 acesso e imprime o resultado ----------
    // "task" em Verilog e como uma sub-rotina (so para simulacao aqui).
    // Ela poe o endereco, espera a borda de clock, e mostra hit/miss.
    // -----------------------------------------------------------------------
    task aplica_acesso(input [31:0] endereco, input [127:0] rotulo);
        begin
            @(negedge clk);          // alinha no meio do ciclo para setar entradas
            req_valid = 1'b1;
            req_addr  = endereco;
            #1;                      // deixa a logica combinacional estabilizar
            $display("[t=%0t] acesso %0s  addr=0x%08h  -> %s",
                     $time, rotulo, endereco, hit ? "HIT " : "MISS");
            @(posedge clk);          // borda que efetiva a atualizacao de estado
            #1;
            req_valid = 1'b0;        // baixa o valid entre acessos
        end
    endtask

    // ------ estimulos ------
    initial begin
        $dumpfile("ondas_l1.vcd");
        $dumpvars(0, tb_cache_l1);

        // estado inicial + reset
        clk = 1'b0; rst = 1'b1; req_valid = 1'b0; req_addr = 32'd0;
        @(negedge clk); @(negedge clk);
        rst = 1'b0;

        $display("=========================================================");
        $display(" Teste da L1 (2 vias, LRU). Esperado em comentarios.");
        $display("=========================================================");

        // 1) Primeiro acesso a A: compulsorio -> MISS (instala na via 0)
        aplica_acesso(32'h00000000, "A");        // esperado: MISS

        // 2) Reacesso a A: agora esta na cache -> HIT
        aplica_acesso(32'h00000000, "A");        // esperado: HIT

        // 3) Acesso a B (mesmo set, tag diferente): compulsorio -> MISS
        //    Agora as 2 vias estao ocupadas (A e B). LRU aponta B (ultimo).
        aplica_acesso(32'h00000800, "B");        // esperado: MISS

        // 4) Reacesso a A: ainda na cache -> HIT. Agora A vira o mais recente,
        //    entao a vitima futura passa a ser B.
        aplica_acesso(32'h00000000, "A");        // esperado: HIT

        // 5) Acesso a C (mesmo set, terceira tag): MISS. Como A e o mais
        //    recente, a vitima e B. C entra no lugar de B.
        aplica_acesso(32'h00001000, "C");        // esperado: MISS (despeja B)

        // 6) Acesso a B: foi despejado no passo anterior -> MISS de novo.
        //    Isto confirma que o LRU despejou B e nao A.
        aplica_acesso(32'h00000800, "B");        // esperado: MISS

        // 7) Acesso a A: A foi despejado no passo 6? Vamos ver.
        //    No passo 6, o set tinha {A (recente no passo4), C (passo5)}.
        //    LRU no passo 5 marcou C como recente -> vitima no passo 6 = A.
        //    Logo A foi despejado -> este acesso e MISS.
        aplica_acesso(32'h00000000, "A");        // esperado: MISS

        // resumo
        $display("---------------------------------------------------------");
        $display(" Total: hits=%0d  misses=%0d", hit_count, miss_count);
        $display(" Esperado: hits=2  misses=5");
        $display("---------------------------------------------------------");

        #20;
        $finish;
    end

endmodule
// ===== fim do tb_cache_l1.v =====
