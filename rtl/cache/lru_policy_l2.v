// =============================================================================
// lru_policy_l2.v
// -----------------------------------------------------------------------------
// Modulo de POLITICA de substituicao para a L2 - implementacao LRU por
// contadores de idade. ESTE MODULO E UM PLACEHOLDER (provisorio).
//
// MOTIVO: voces decidiram que a L2 vai usar Hawkeye, nao LRU. Mas para testar
// a ESTRUTURA da L2 sozinho (antes do Hawkeye chegar), precisamos de ALGUMA
// politica que escolha vitimas. Este LRU faz esse papel. Quando o colega
// plugar o hawkeye_top, este arquivo simplesmente deixa de ser instanciado -
// a cache_l2.v nao muda.
//
// COMO O LRU POR IDADE FUNCIONA (versao intuitiva):
//   - Cada via de cada conjunto tem um contador de "idade".
//   - A cada acesso a um conjunto, a via acessada zera sua idade (vira a mais
//     nova) e as demais vias daquele conjunto envelhecem (+1).
//   - A vitima e a via com MAIOR idade (a usada ha mais tempo).
//   Isto e o LRU exato. Para 8 vias usamos idade de 3 bits (0..7).
//
// INTERFACE (casa com os sinais pol_* da cache_l2):
//   recebe : set, pc(ignorado pelo LRU), access(pulso), hit, hit_way,
//            need_victim(pulso)
//   devolve: victim_way (combinacional - a via mais velha do conjunto)
// =============================================================================

`timescale 1ns/1ps

module lru_policy_l2 #(
    parameter INDEX_BITS = 6,
    parameter NUM_SETS   = 64,
    parameter WAYS       = 8,
    parameter WAY_BITS   = 3,
    parameter AGE_BITS   = 3,             // 3 bits => idades 0..7 (8 vias)
    parameter ADDR_WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   rst,

    // vindos da L2
    input  wire [INDEX_BITS-1:0]  pol_set,
    input  wire [ADDR_WIDTH-1:0]  pol_pc,       // nao usado no LRU (so existe p/ casar interface)
    input  wire                   pol_access,   // pulso: houve acesso ao conjunto
    input  wire                   pol_hit,      // foi hit?
    input  wire [WAY_BITS-1:0]    pol_hit_way,  // via do hit
    input  wire                   pol_need_victim,

    // resposta para a L2
    output wire [WAY_BITS-1:0]    pol_victim_way
);

    // idade de cada via de cada conjunto
    reg [AGE_BITS-1:0] age [0:NUM_SETS-1][0:WAYS-1];

    // ------ SELECAO DA VITIMA (combinacional) ------
    // Procura a via com maior idade no conjunto pol_set.
    reg [WAY_BITS-1:0] victim;
    reg [AGE_BITS-1:0] maior_idade;
    integer w;
    always @(*) begin
        victim      = {WAY_BITS{1'b0}};
        maior_idade = age[pol_set][0];
        for (w = 1; w < WAYS; w = w + 1) begin
            if (age[pol_set][w] > maior_idade) begin
                maior_idade = age[pol_set][w];
                victim      = w[WAY_BITS-1:0];
            end
        end
    end
    assign pol_victim_way = victim;

    // ------ ATUALIZACAO DAS IDADES (sincrona) ------
    // Em cada acesso valido ao conjunto, a via "tocada" zera e as outras
    // envelhecem. A via tocada e:
    //   - em hit : a via do hit (pol_hit_way)
    //   - em miss: a via que sera instalada. Como em miss a L2 instala na
    //     vitima (ou numa invalida), aproximamos tocando a 'victim' calculada.
    //     Observacao: este placeholder nao precisa ser perfeito em todos os
    //     cantos - ele so existe para a L2 ter o que testar. O LRU "de verdade"
    //     do projeto e a L1; a L2 vai de Hawkeye.
    // -----------------------------------------------------------------------
    wire [WAY_BITS-1:0] touched = pol_hit ? pol_hit_way : victim;

    integer s, v;
    always @(posedge clk) begin
        if (rst) begin
            for (s = 0; s < NUM_SETS; s = s + 1)
                for (v = 0; v < WAYS; v = v + 1)
                    age[s][v] <= v[AGE_BITS-1:0]; // idades iniciais distintas 0..7
        end
        else if (pol_access) begin
            for (v = 0; v < WAYS; v = v + 1) begin
                if (v[WAY_BITS-1:0] == touched)
                    age[pol_set][v] <= {AGE_BITS{1'b0}};      // vira a mais nova
                else if (age[pol_set][v] < {AGE_BITS{1'b1}})
                    age[pol_set][v] <= age[pol_set][v] + 1'b1; // envelhece (satura)
            end
        end
    end

endmodule
// ===== fim do lru_policy_l2.v =====
