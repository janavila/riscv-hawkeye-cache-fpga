`timescale 1ps/1ps

module tb_sampler_find_unit;

    parameter SAMPLER_HIST   = 8;
    parameter SIGNATURE_BITS = 8;
    parameter POS_BITS       = 3;

    reg  [SIGNATURE_BITS-1:0]              signature_atual;
    reg  [SAMPLER_HIST-1:0]                valid_entries;
    reg  [SAMPLER_HIST*SIGNATURE_BITS-1:0] signature_entries_flat;

    wire                                   sampler_hit;
    wire [POS_BITS-1:0]                    sampler_pos;
    wire [SAMPLER_HIST-1:0]                match_vector;

    sampler_find_unit #(
        .SAMPLER_HIST(SAMPLER_HIST),
        .SIGNATURE_BITS(SIGNATURE_BITS),
        .POS_BITS(POS_BITS)
    ) dut (
        .signature_atual(signature_atual),
        .valid_entries(valid_entries),
        .signature_entries_flat(signature_entries_flat),
        .sampler_hit(sampler_hit),
        .sampler_pos(sampler_pos),
        .match_vector(match_vector)
    );

    initial begin
        $dumpfile("waves_sampler_find.vcd");
        $dumpvars(0, tb_sampler_find_unit);

        $display("==== Teste sampler_find_unit ====");

        /*
            Organização do barramento:
            entry0 = bits [7:0]
            entry1 = bits [15:8]
            entry2 = bits [23:16]
            ...
            entry7 = bits [63:56]
        */

        signature_entries_flat[0*8 +: 8] = 8'h10;
        signature_entries_flat[1*8 +: 8] = 8'h20;
        signature_entries_flat[2*8 +: 8] = 8'h30;
        signature_entries_flat[3*8 +: 8] = 8'hAA;
        signature_entries_flat[4*8 +: 8] = 8'h40;
        signature_entries_flat[5*8 +: 8] = 8'hAA;
        signature_entries_flat[6*8 +: 8] = 8'h50;
        signature_entries_flat[7*8 +: 8] = 8'h60;

        // Caso 1: nenhuma entrada válida
        signature_atual = 8'hAA;
        valid_entries = 8'b0000_0000;
        #10;
        $display("Caso 1: sem validos -> hit=%0d pos=%0d match=%b (esperado hit=0)",
                 sampler_hit, sampler_pos, match_vector);

        // Caso 2: match válido na posição 3
        signature_atual = 8'hAA;
        valid_entries = 8'b0000_1000;
        #10;
        $display("Caso 2: match pos 3 -> hit=%0d pos=%0d match=%b (esperado hit=1 pos=3)",
                 sampler_hit, sampler_pos, match_vector);

        // Caso 3: match nas posições 3 e 5, deve retornar a primeira: 3
        signature_atual = 8'hAA;
        valid_entries = 8'b0010_1000;
        #10;
        $display("Caso 3: match pos 3 e 5 -> hit=%0d pos=%0d match=%b (esperado hit=1 pos=3)",
                 sampler_hit, sampler_pos, match_vector);

        // Caso 4: assinatura existe na posição 3, mas posição 3 inválida;
        // posição 5 válida e também tem AA, então deve retornar 5
        signature_atual = 8'hAA;
        valid_entries = 8'b0010_0000;
        #10;
        $display("Caso 4: pos 3 invalida, pos 5 valida -> hit=%0d pos=%0d match=%b (esperado hit=1 pos=5)",
                 sampler_hit, sampler_pos, match_vector);

        // Caso 5: procura assinatura que não existe
        signature_atual = 8'hFF;
        valid_entries = 8'b1111_1111;
        #10;
        $display("Caso 5: assinatura inexistente -> hit=%0d pos=%0d match=%b (esperado hit=0)",
                 sampler_hit, sampler_pos, match_vector);

        $display("==== Fim do teste ====");
        $finish;
    end

endmodule   