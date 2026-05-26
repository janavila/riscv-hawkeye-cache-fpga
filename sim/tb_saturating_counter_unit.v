`timescale 1ps/1ps
module tb_saturating_counter_unit;

    reg  [4:0] counter_current;
    reg        train_up;
    reg        train_down;
    reg        aging_enable;
    wire [4:0] counter_next;

    saturating_counter_unit #(
        .COUNTER_BITS(5)
    ) dut (
        .counter_current(counter_current),
        .train_up(train_up),
        .train_down(train_down),
        .aging_enable(aging_enable),
        .counter_next(counter_next)
    );

    initial begin
        $dumpfile("waves_counter.vcd");
        $dumpvars(0, tb_saturating_counter_unit);

        $display("==== Teste saturating_counter_unit ====");

        counter_current = 5'd0;
        train_up = 0;
        train_down = 1;
        aging_enable = 0;
        #10;
        $display("counter=0, train_down=1 -> counter_next=%0d (esperado 0)", counter_next);

        counter_current = 5'd31;
        train_up = 1;
        train_down = 0;
        aging_enable = 0;
        #10;
        $display("counter=31, train_up=1 -> counter_next=%0d (esperado 31)", counter_next);

        counter_current = 5'd15;
        train_up = 1;
        train_down = 0;
        aging_enable = 0;
        #10;
        $display("counter=15, train_up=1 -> counter_next=%0d (esperado 16)", counter_next);

        counter_current = 5'd15;
        train_up = 0;
        train_down = 1;
        aging_enable = 0;
        #10;
        $display("counter=15, train_down=1 -> counter_next=%0d (esperado 14)", counter_next);

        counter_current = 5'd20;
        train_up = 0;
        train_down = 0;
        aging_enable = 1;
        #10;
        $display("counter=20, aging=1 -> counter_next=%0d (esperado 10)", counter_next);

        counter_current = 5'd7;
        train_up = 0;
        train_down = 0;
        aging_enable = 0;
        #10;
        $display("counter=7, sem controle -> counter_next=%0d (esperado 7)", counter_next);

        $display("==== Fim do teste ====");
        $finish;
    end

endmodule
