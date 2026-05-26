`timescale 1ps/1ps

module tb_optgen;

    parameter OPTGEN_SIZE       = 128;
    parameter INDEX_BITS        = 7;
    parameter LIVENESS_BITS     = 8;
    parameter CACHE_SIZE_BITS   = 8;
    parameter NUM_CACHE_BITS    = 32;
    parameter ACCESS_BITS       = 32;

    reg                         clk;
    reg                         reset;

    reg                         start_check;
    reg                         start_set_access;

    reg  [INDEX_BITS-1:0]       current_val;
    reg  [INDEX_BITS-1:0]       end_val;
    reg  [CACHE_SIZE_BITS-1:0]  cache_size;

    wire                        busy;
    wire                        done;
    wire                        should_cache;

    wire [NUM_CACHE_BITS-1:0]   num_cache_debug;
    wire [ACCESS_BITS-1:0]      access_debug;
    wire [INDEX_BITS-1:0]       count_debug;
    wire [2:0]                  state_debug;

    optgen #(
        .OPTGEN_SIZE(OPTGEN_SIZE),
        .INDEX_BITS(INDEX_BITS),
        .LIVENESS_BITS(LIVENESS_BITS),
        .CACHE_SIZE_BITS(CACHE_SIZE_BITS),
        .NUM_CACHE_BITS(NUM_CACHE_BITS),
        .ACCESS_BITS(ACCESS_BITS)
    ) dut (
        .clk(clk),
        .reset(reset),

        .start_check(start_check),
        .start_set_access(start_set_access),

        .current_val(current_val),
        .end_val(end_val),
        .cache_size(cache_size),

        .busy(busy),
        .done(done),
        .should_cache(should_cache),

        .num_cache_debug(num_cache_debug),
        .access_debug(access_debug),
        .count_debug(count_debug),
        .state_debug(state_debug)
    );

    /*
        Clock de 10 ps.
    */
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    task inicia_set_access;
        input [INDEX_BITS-1:0] cv;
        begin
            current_val = cv;
            start_set_access = 1'b1;
            @(posedge clk);
            #1;
            start_set_access = 1'b0;

            wait(done == 1'b1);
            #1;
        end
    endtask

    task inicia_check;
        input [INDEX_BITS-1:0] cv;
        input [INDEX_BITS-1:0] ev;
        input [CACHE_SIZE_BITS-1:0] cs;
        begin
            current_val = cv;
            end_val     = ev;
            cache_size  = cs;

            start_check = 1'b1;
            @(posedge clk);
            #1;
            start_check = 1'b0;

            wait(done == 1'b1);
            #1;
        end
    endtask

    initial begin
        $dumpfile("waves_optgen.vcd");
        $dumpvars(0, tb_optgen);

        $display("==== Teste optgen ====");

        reset            = 1'b1;
        start_check      = 1'b0;
        start_set_access = 1'b0;

        current_val = 7'd0;
        end_val     = 7'd0;
        cache_size  = 8'd2;

        /*
            Reset por alguns ciclos.
        */
        repeat (3) @(posedge clk);
        #1;
        reset = 1'b0;

        #10;
        $display("Depois do reset -> busy=%0d done=%0d should_cache=%0d num_cache=%0d access=%0d state=%0d",
                 busy, done, should_cache, num_cache_debug, access_debug, state_debug);
        $display("Esperado: busy=0, num_cache=0, access=0");

        /*
            Caso 1:
            Testa optgen_set_access.
            Deve incrementar access_debug.
        */
        inicia_set_access(7'd5);

        $display("Caso 1: set_access current=5 -> done=%0d access=%0d state=%0d",
                 done, access_debug, state_debug);
        $display("Esperado: access=1");

        /*
            Caso 2:
            Check do intervalo end=2 até current=5.
            Como os liveness_intervals estão zerados, deve caber na cache.
            Intervalo percorrido: 2,3,4.
            Deve retornar should_cache=1 e incrementar num_cache.
        */
        inicia_check(7'd5, 7'd2, 8'd2);

        $display("Caso 2: check intervalo livre end=2 current=5 cache_size=2 -> should_cache=%0d num_cache=%0d count=%0d",
                 should_cache, num_cache_debug, count_debug);
        $display("Esperado: should_cache=1, num_cache=1");

        /*
            Caso 3:
            Agora o intervalo 2,3,4 já foi incrementado para 1.
            Se cache_size=1, então liveness_intervals[count] >= cache_size
            logo no começo.
            Deve retornar should_cache=0 e não incrementar num_cache.
        */
        inicia_check(7'd5, 7'd2, 8'd1);

        $display("Caso 3: check intervalo cheio end=2 current=5 cache_size=1 -> should_cache=%0d num_cache=%0d count=%0d",
                 should_cache, num_cache_debug, count_debug);
        $display("Esperado: should_cache=0, num_cache continua 1");

        /*
            Caso 4:
            Intervalo vazio: current_val == end_val.
            O while do C não percorre nada.
            Deve retornar should_cache=1 e incrementar num_cache.
        */
        inicia_check(7'd10, 7'd10, 8'd1);

        $display("Caso 4: intervalo vazio current=end=10 -> should_cache=%0d num_cache=%0d",
                 should_cache, num_cache_debug);
        $display("Esperado: should_cache=1, num_cache=2");

        $display("==== Fim do teste ====");
        $finish;
    end

endmodule   