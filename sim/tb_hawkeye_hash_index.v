`timescale 1ps/1ps

module tb_hawkeye_hash_index;

    reg  [63:0] value_in;

    wire [63:0] hash_out;
    wire [10:0] predictor_index;
    wire [7:0]  signature;

    hawkeye_hash_index dut (
        .value_in(value_in),
        .hash_out(hash_out),
        .predictor_index(predictor_index),
        .signature(signature)
    );

    initial begin
        $dumpfile("waves_hash.vcd");
        $dumpvars(0, tb_hawkeye_hash_index);

        $display("==== Teste hawkeye_hash_index ====");

        value_in = 64'h0000_0000_0000_0000;
        #10;
        $display("value=0x%h -> hash=0x%h, index=%0d, signature=%0d", 
                 value_in, hash_out, predictor_index, signature);
        $display("esperado: hash=0x0000000000000000, index=0, signature=0");

        value_in = 64'h0000_0000_0000_0001;
        #10;
        $display("value=0x%h -> hash=0x%h, index=%0d, signature=%0d", 
                 value_in, hash_out, predictor_index, signature);
        $display("esperado: hash=0x00000000b8bc6765, index=1893, signature=101");

        value_in = 64'h0000_0000_0000_0002;
        #10;
        $display("value=0x%h -> hash=0x%h, index=%0d, signature=%0d", 
                 value_in, hash_out, predictor_index, signature);
        $display("esperado: hash=0x00000000aa09c88b, index=139, signature=139");

        value_in = 64'h0000_0000_0000_0010;
        #10;
        $display("value=0x%h -> hash=0x%h, index=%0d, signature=%0d", 
                 value_in, hash_out, predictor_index, signature);
        $display("esperado: hash=0x000000005019579f, index=1951, signature=159");

        value_in = 64'h0000_0000_0000_1234;
        #10;
        $display("value=0x%h -> hash=0x%h, index=%0d, signature=%0d", 
                 value_in, hash_out, predictor_index, signature);
        $display("esperado: hash=0x0000000060eb18e8, index=232, signature=232");

        value_in = 64'h0000_0000_DEAD_BEEF;
        #10;
        $display("value=0x%h -> hash=0x%h, index=%0d, signature=%0d", 
                 value_in, hash_out, predictor_index, signature);
        $display("esperado: hash=0x000000003b1ebf03, index=1795, signature=3");

        $display("==== Fim do teste ====");
        $finish;
    end

endmodule   