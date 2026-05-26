`timescale 1ps/1ps

module tb_rrip_victim_selector;

    parameter NUM_WAYS  = 4;
    parameter WAY_BITS  = 2;
    parameter RRPV_BITS = 3;

    reg  [NUM_WAYS-1:0]             valid_entries;
    reg  [NUM_WAYS*RRPV_BITS-1:0]   rrpv_entries_flat;

    wire [WAY_BITS-1:0]             victim_way;
    wire                            victim_found;
    wire                            need_aging;
    wire [NUM_WAYS-1:0]             invalid_vector;
    wire [NUM_WAYS-1:0]             candidate_vector;

    rrip_victim_selector #(
        .NUM_WAYS(NUM_WAYS),
        .WAY_BITS(WAY_BITS),
        .RRPV_BITS(RRPV_BITS)
    ) dut (
        .valid_entries(valid_entries),
        .rrpv_entries_flat(rrpv_entries_flat),

        .victim_way(victim_way),
        .victim_found(victim_found),
        .need_aging(need_aging),
        .invalid_vector(invalid_vector),
        .candidate_vector(candidate_vector)
    );

    initial begin
        $dumpfile("waves_rrip_victim.vcd");
        $dumpvars(0, tb_rrip_victim_selector);

        $display("==== Teste rrip_victim_selector ====");

        /*
            Organização do barramento rrpv_entries_flat:

            way0.rrpv = rrpv_entries_flat[2:0]
            way1.rrpv = rrpv_entries_flat[5:3]
            way2.rrpv = rrpv_entries_flat[8:6]
            way3.rrpv = rrpv_entries_flat[11:9]
        */

        // Caso 1: via 0 inválida
        valid_entries = 4'b1110;

        rrpv_entries_flat[0*3 +: 3] = 3'd2;
        rrpv_entries_flat[1*3 +: 3] = 3'd3;
        rrpv_entries_flat[2*3 +: 3] = 3'd4;
        rrpv_entries_flat[3*3 +: 3] = 3'd5;

        #10;
        $display("Caso 1: way0 invalida -> found=%0d victim=%0d need_aging=%0d invalid=%b candidate=%b (esperado victim=0)",
                 victim_found, victim_way, need_aging, invalid_vector, candidate_vector);

        // Caso 2: via 2 inválida
        valid_entries = 4'b1011;

        rrpv_entries_flat[0*3 +: 3] = 3'd2;
        rrpv_entries_flat[1*3 +: 3] = 3'd3;
        rrpv_entries_flat[2*3 +: 3] = 3'd4;
        rrpv_entries_flat[3*3 +: 3] = 3'd5;

        #10;
        $display("Caso 2: way2 invalida -> found=%0d victim=%0d need_aging=%0d invalid=%b candidate=%b (esperado victim=2)",
                 victim_found, victim_way, need_aging, invalid_vector, candidate_vector);

        // Caso 3: todas válidas, way1 com RRPV_MAX
        valid_entries = 4'b1111;

        rrpv_entries_flat[0*3 +: 3] = 3'd2;
        rrpv_entries_flat[1*3 +: 3] = 3'd7;
        rrpv_entries_flat[2*3 +: 3] = 3'd4;
        rrpv_entries_flat[3*3 +: 3] = 3'd5;

        #10;
        $display("Caso 3: way1 rrpv=7 -> found=%0d victim=%0d need_aging=%0d invalid=%b candidate=%b (esperado victim=1)",
                 victim_found, victim_way, need_aging, invalid_vector, candidate_vector);

        // Caso 4: todas válidas, way2 e way3 com RRPV_MAX.
        // Deve escolher a primeira: way2.
        valid_entries = 4'b1111;

        rrpv_entries_flat[0*3 +: 3] = 3'd2;
        rrpv_entries_flat[1*3 +: 3] = 3'd3;
        rrpv_entries_flat[2*3 +: 3] = 3'd7;
        rrpv_entries_flat[3*3 +: 3] = 3'd7;

        #10;
        $display("Caso 4: way2 e way3 rrpv=7 -> found=%0d victim=%0d need_aging=%0d invalid=%b candidate=%b (esperado victim=2)",
                 victim_found, victim_way, need_aging, invalid_vector, candidate_vector);

        // Caso 5: todas válidas, ninguém com RRPV_MAX.
        // Deve pedir aging.
        valid_entries = 4'b1111;

        rrpv_entries_flat[0*3 +: 3] = 3'd1;
        rrpv_entries_flat[1*3 +: 3] = 3'd2;
        rrpv_entries_flat[2*3 +: 3] = 3'd3;
        rrpv_entries_flat[3*3 +: 3] = 3'd4;

        #10;
        $display("Caso 5: sem rrpv max -> found=%0d victim=%0d need_aging=%0d invalid=%b candidate=%b (esperado found=0 need_aging=1)",
                 victim_found, victim_way, need_aging, invalid_vector, candidate_vector);

        $display("==== Fim do teste ====");
        $finish;
    end

endmodule   