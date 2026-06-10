// =============================================================================
// hawkeye_l2_policy_dummy.v
// -----------------------------------------------------------------------------
// Politica dummy para testar integracao com a L2.
//
// Objetivo:
// - Simular uma politica multi-ciclo.
// - A L2 pede uma vitima com pol_need_victim.
// - Este modulo espera alguns ciclos.
// - Depois responde com pol_victim_valid = 1 e pol_victim_way.
//
// Isso ainda NAO e o Hawkeye completo.
// Serve apenas para validar o handshake:
//     pol_need_victim -> espera -> pol_victim_valid
// =============================================================================

`timescale 1ns/1ps

module hawkeye_l2_policy_dummy #(
    parameter SET_BITS       = 6,
    parameter PC_WIDTH       = 32,
    parameter ADDR_WIDTH     = 32,
    parameter WAY_BITS       = 3,
    parameter RESPONSE_DELAY = 2
)(
    input  wire                    clk,
    input  wire                    rst,

    // sinais vindos da L2
    input  wire [SET_BITS-1:0]     pol_set,
    input  wire [PC_WIDTH-1:0]     pol_pc,
    input  wire [ADDR_WIDTH-1:0]   pol_addr,
    input  wire                    pol_access,
    input  wire                    pol_hit,
    input  wire [WAY_BITS-1:0]     pol_hit_way,
    input  wire                    pol_need_victim,
    input  wire                    pol_fill,
    input  wire [WAY_BITS-1:0]     pol_fill_way,

    // resposta para a L2
    output reg  [WAY_BITS-1:0]     pol_victim_way,
    output reg                     pol_victim_valid
);

    reg pending;
    reg [7:0] delay_count;

    always @(posedge clk) begin
        if(rst) begin
            pending          <= 1'b0;
            delay_count      <= 8'd0;
            pol_victim_way   <= {WAY_BITS{1'b0}};
            pol_victim_valid <= 1'b0;
        end
        else begin
            // pol_victim_valid e pulso de 1 ciclo
            pol_victim_valid <= 1'b0;

            // Apenas imprime os acessos que chegam da L2 para a politica.
            if(pol_access) begin
                $display("[POL t=%0t] acesso recebido: set=%0d pc=0x%08h addr=0x%08h hit=%0d hit_way=%0d",
                         $time, pol_set, pol_pc, pol_addr, pol_hit, pol_hit_way);
            end
            
            // Imprime quando a L2 realmente instalou uma linha nova.
            if(pol_fill) begin
                $display("[POL t=%0t] fill confirmado pela L2: set=%0d way=%0d addr=0x%08h",
                         $time, pol_set, pol_fill_way, pol_addr);
            end

            // Quando a L2 precisa de vitima, iniciamos uma resposta multi-ciclo.
            if(pol_need_victim && !pending) begin
                pending     <= 1'b1;
                delay_count <= 8'd0;

                $display("[POL t=%0t] L2 pediu vitima no set=%0d. Politica vai esperar %0d ciclos.",
                         $time, pol_set, RESPONSE_DELAY);
            end

            // Enquanto pending=1, simulamos uma politica que demora alguns ciclos.
            else if(pending) begin
                if(delay_count == RESPONSE_DELAY[7:0]) begin
                    pending <= 1'b0;

                    // Escolha dummy da vitima.
                    // Por enquanto escolhe uma via derivada do set.
                    // Depois isso sera substituido pelo Hawkeye/RRIP real.
                    pol_victim_way   <= pol_set[WAY_BITS-1:0];
                    pol_victim_valid <= 1'b1;

                    $display("[POL t=%0t] vitima pronta: way=%0d valid=1",
                             $time, pol_set[WAY_BITS-1:0]);
                end
                else begin
                    delay_count <= delay_count + 1'b1;

                    $display("[POL t=%0t] aguardando politica... ciclo=%0d",
                             $time, delay_count + 1'b1);
                end
            end
        end
    end

endmodule   