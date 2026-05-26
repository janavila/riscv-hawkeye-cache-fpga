`timescale 1ps/1ps

module tb_sampler_victim_selector;

    parameter SAMPLER_HIST = 8;
    parameter LRU_BITS     = 4;
    parameter POS_BITS     = 3;

    reg  [SAMPLER_HIST-1:0]          valid_entries;
    reg  [SAMPLER_HIST*LRU_BITS-1:0] lru_entries_flat;

    wire [POS_BITS-1:0]              victim_pos;
    wire                             has_invalid;
    wire [SAMPLER_HIST-1:0]          invalid_vector;

    sampler_victim_selector #(
        .SAMPLER_HIST(SAMPLER_HIST),
        .LRU_BITS(LRU_BITS),
        .POS_BITS(POS_BITS)
    ) dut (
        .valid_entries(valid_entries),
        .lru_entries_flat(lru_entries_flat),
        .victim_pos(victim_pos),
        .has_invalid(has_invalid),
        .invalid_vector(invalid_vector)
    );

    initial begin
        $dumpfile("waves_sampler_victim.vcd");
        $dumpvars(0, tb_sampler_victim_selector);

        $display("==== Teste sampler_victim_selector ====");

        /*
            Organização do barramento lru_entries_flat:

            entry0.lru = lru_entries_flat[3:0]
            entry1.lru = lru_entries_flat[7:4]
            entry2.lru = lru_entries_flat[11:8]
            ...
            entry7.lru = lru_entries_flat[31:28]
        */

        lru_entries_flat[0*4 +: 4] = 4'd0;
        lru_entries_flat[1*4 +: 4] = 4'd3;
        lru_entries_flat[2*4 +: 4] = 4'd5;
        lru_entries_flat[3*4 +: 4] = 4'd1;
        lru_entries_flat[4*4 +: 4] = 4'd7;
        lru_entries_flat[5*4 +: 4] = 4'd2;
        lru_entries_flat[6*4 +: 4] = 4'd4;
        lru_entries_flat[7*4 +: 4] = 4'd6;

        // Caso 1: entrada 0 inválida
        valid_entries = 8'b1111_1110;
        #10;
        $display("Caso 1: entry0 invalida -> has_invalid=%0d invalid=%b victim=%0d (esperado victim=0)",
                 has_invalid, invalid_vector, victim_pos);

        // Caso 2: entrada 2 inválida
        valid_entries = 8'b1111_1011;
        #10;
        $display("Caso 2: entry2 invalida -> has_invalid=%0d invalid=%b victim=%0d (esperado victim=2)",
                 has_invalid, invalid_vector, victim_pos);

        // Caso 3: várias inválidas: 0,1,2,3. Deve escolher a primeira: 0
        valid_entries = 8'b1111_0000;
        #10;
        $display("Caso 3: varias invalidas -> has_invalid=%0d invalid=%b victim=%0d (esperado victim=0)",
                 has_invalid, invalid_vector, victim_pos);

        // Caso 4: todas válidas. Deve escolher maior LRU.
        // LRUs: 0,3,5,1,7,2,4,6 -> maior é entry4
        valid_entries = 8'b1111_1111;
        #10;
        $display("Caso 4: todas validas -> has_invalid=%0d invalid=%b victim=%0d (esperado victim=4)",
                 has_invalid, invalid_vector, victim_pos);

        // Caso 5: todas válidas, altera LRUs para maior na posição 7
        lru_entries_flat[0*4 +: 4] = 4'd1;
        lru_entries_flat[1*4 +: 4] = 4'd2;
        lru_entries_flat[2*4 +: 4] = 4'd3;
        lru_entries_flat[3*4 +: 4] = 4'd4;
        lru_entries_flat[4*4 +: 4] = 4'd5;
        lru_entries_flat[5*4 +: 4] = 4'd6;
        lru_entries_flat[6*4 +: 4] = 4'd7;
        lru_entries_flat[7*4 +: 4] = 4'd8;
        valid_entries = 8'b1111_1111;
        #10;
        $display("Caso 5: maior LRU na pos 7 -> has_invalid=%0d invalid=%b victim=%0d (esperado victim=7)",
                 has_invalid, invalid_vector, victim_pos);

        $display("==== Fim do teste ====");
        $finish;
    end

endmodule   