`timescale 1ps/1ps

module tb_rrip_aging_unit;

    parameter NUM_WAYS  = 4;
    parameter RRPV_BITS = 3;

    reg  [NUM_WAYS-1:0]             valid_entries;
    reg  [NUM_WAYS*RRPV_BITS-1:0]   rrpv_entries_flat;
    reg                             aging_enable;

    wire [NUM_WAYS*RRPV_BITS-1:0]   new_rrpv_entries_flat;
    wire [NUM_WAYS-1:0]             write_mask;

    rrip_aging_unit #(
        .NUM_WAYS(NUM_WAYS),
        .RRPV_BITS(RRPV_BITS)
    ) dut (
        .valid_entries(valid_entries),
        .rrpv_entries_flat(rrpv_entries_flat),
        .aging_enable(aging_enable),
        .new_rrpv_entries_flat(new_rrpv_entries_flat),
        .write_mask(write_mask)
    );

    initial begin
        $dumpfile("waves_rrip_aging.vcd");
        $dumpvars(0, tb_rrip_aging_unit);

        $display("==== Teste rrip_aging_unit ====");

        /*
            Organização do barramento:

            way0.rrpv = rrpv_entries_flat[2:0]
            way1.rrpv = rrpv_entries_flat[5:3]
            way2.rrpv = rrpv_entries_flat[8:6]
            way3.rrpv = rrpv_entries_flat[11:9]
        */

        // Caso 1: aging desabilitado, deve manter tudo
        valid_entries = 4'b1111;
        aging_enable = 1'b0;

        rrpv_entries_flat[0*3 +: 3] = 3'd1;
        rrpv_entries_flat[1*3 +: 3] = 3'd2;
        rrpv_entries_flat[2*3 +: 3] = 3'd3;
        rrpv_entries_flat[3*3 +: 3] = 3'd4;

        #10;
        $display("Caso 1: aging=0 -> new_flat=%h write_mask=%b (esperado manter, write=0000)",
                 new_rrpv_entries_flat, write_mask);

        // Caso 2: aging habilitado, todas válidas, incrementa todas
        valid_entries = 4'b1111;
        aging_enable = 1'b1;

        rrpv_entries_flat[0*3 +: 3] = 3'd1;
        rrpv_entries_flat[1*3 +: 3] = 3'd2;
        rrpv_entries_flat[2*3 +: 3] = 3'd3;
        rrpv_entries_flat[3*3 +: 3] = 3'd4;

        #10;
        $display("Caso 2: aging=1 todas validas -> way0=%0d way1=%0d way2=%0d way3=%0d write=%b (esperado 2,3,4,5 write=1111)",
                 new_rrpv_entries_flat[0*3 +: 3],
                 new_rrpv_entries_flat[1*3 +: 3],
                 new_rrpv_entries_flat[2*3 +: 3],
                 new_rrpv_entries_flat[3*3 +: 3],
                 write_mask);

        // Caso 3: valores no máximo saturam em 7
        valid_entries = 4'b1111;
        aging_enable = 1'b1;

        rrpv_entries_flat[0*3 +: 3] = 3'd6;
        rrpv_entries_flat[1*3 +: 3] = 3'd7;
        rrpv_entries_flat[2*3 +: 3] = 3'd5;
        rrpv_entries_flat[3*3 +: 3] = 3'd7;

        #10;
        $display("Caso 3: saturacao -> way0=%0d way1=%0d way2=%0d way3=%0d write=%b (esperado 7,7,6,7 write=1111)",
                 new_rrpv_entries_flat[0*3 +: 3],
                 new_rrpv_entries_flat[1*3 +: 3],
                 new_rrpv_entries_flat[2*3 +: 3],
                 new_rrpv_entries_flat[3*3 +: 3],
                 write_mask);

        // Caso 4: vias inválidas não envelhecem
        valid_entries = 4'b1011;
        aging_enable = 1'b1;

        rrpv_entries_flat[0*3 +: 3] = 3'd1;
        rrpv_entries_flat[1*3 +: 3] = 3'd2;
        rrpv_entries_flat[2*3 +: 3] = 3'd3;
        rrpv_entries_flat[3*3 +: 3] = 3'd4;

        #10;
        $display("Caso 4: way2 invalida -> way0=%0d way1=%0d way2=%0d way3=%0d write=%b (esperado 2,3,3,5 write=1011)",
                 new_rrpv_entries_flat[0*3 +: 3],
                 new_rrpv_entries_flat[1*3 +: 3],
                 new_rrpv_entries_flat[2*3 +: 3],
                 new_rrpv_entries_flat[3*3 +: 3],
                 write_mask);

        $display("==== Fim do teste ====");
        $finish;
    end

endmodule   