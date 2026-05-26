`timescale 1ps/1ps

module tb_rrip_update_unit;

    parameter RRPV_BITS = 3;

    reg  [RRPV_BITS-1:0] current_rrpv;
    reg                  update_enable;
    reg                  hit;
    reg                  insert;
    reg                  friendly;

    wire [RRPV_BITS-1:0] new_rrpv;
    wire                 write_rrpv;

    rrip_update_unit #(
        .RRPV_BITS(RRPV_BITS)
    ) dut (
        .current_rrpv(current_rrpv),
        .update_enable(update_enable),
        .hit(hit),
        .insert(insert),
        .friendly(friendly),
        .new_rrpv(new_rrpv),
        .write_rrpv(write_rrpv)
    );

    initial begin
        $dumpfile("waves_rrip_update.vcd");
        $dumpvars(0, tb_rrip_update_unit);

        $display("==== Teste rrip_update_unit ====");

        // Caso 1: update desabilitado
        current_rrpv  = 3'd5;
        update_enable = 0;
        hit           = 0;
        insert        = 0;
        friendly      = 0;
        #10;
        $display("Caso 1: update=0 -> new_rrpv=%0d write=%0d (esperado new=5 write=0)",
                 new_rrpv, write_rrpv);

        // Caso 2: hit friendly
        current_rrpv  = 3'd5;
        update_enable = 1;
        hit           = 1;
        insert        = 0;
        friendly      = 1;
        #10;
        $display("Caso 2: hit friendly -> new_rrpv=%0d write=%0d (esperado new=0 write=1)",
                 new_rrpv, write_rrpv);

        // Caso 3: hit averse
        current_rrpv  = 3'd5;
        update_enable = 1;
        hit           = 1;
        insert        = 0;
        friendly      = 0;
        #10;
        $display("Caso 3: hit averse -> new_rrpv=%0d write=%0d (esperado new=4 write=1)",
                 new_rrpv, write_rrpv);

        // Caso 4: hit averse com RRPV zero
        current_rrpv  = 3'd0;
        update_enable = 1;
        hit           = 1;
        insert        = 0;
        friendly      = 0;
        #10;
        $display("Caso 4: hit averse rrpv=0 -> new_rrpv=%0d write=%0d (esperado new=0 write=1)",
                 new_rrpv, write_rrpv);

        // Caso 5: inserção friendly
        current_rrpv  = 3'd6;
        update_enable = 1;
        hit           = 0;
        insert        = 1;
        friendly      = 1;
        #10;
        $display("Caso 5: insert friendly -> new_rrpv=%0d write=%0d (esperado new=0 write=1)",
                 new_rrpv, write_rrpv);

        // Caso 6: inserção averse
        current_rrpv  = 3'd2;
        update_enable = 1;
        hit           = 0;
        insert        = 1;
        friendly      = 0;
        #10;
        $display("Caso 6: insert averse -> new_rrpv=%0d write=%0d (esperado new=7 write=1)",
                 new_rrpv, write_rrpv);

        // Caso 7: hit e insert ao mesmo tempo
        // Pela prioridade do módulo, hit vem antes de insert.
        current_rrpv  = 3'd6;
        update_enable = 1;
        hit           = 1;
        insert        = 1;
        friendly      = 0;
        #10;
        $display("Caso 7: hit e insert juntos -> new_rrpv=%0d write=%0d (esperado tratar como hit: new=5 write=1)",
                 new_rrpv, write_rrpv);

        $display("==== Fim do teste ====");
        $finish;
    end

endmodule   