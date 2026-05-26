`timescale 1ps/1ps

module tb_hawkeye_predictor;

    parameter PREDICTOR_ENTRIES = 2048;
    parameter INDEX_BITS        = 11;
    parameter COUNTER_BITS      = 5;

    reg                         clk;
    reg                         reset;

    reg                         predict_enable;
    reg  [63:0]                 pc_predict;

    reg                         train_enable;
    reg  [63:0]                 pc_train;
    reg                         train_up;
    reg                         train_down;

    wire                        prediction_valid;
    wire                        friendly;
    wire                        averse;

    wire [COUNTER_BITS-1:0]     counter_predict_debug;
    wire [INDEX_BITS-1:0]       index_predict_debug;

    hawkeye_predictor #(
        .PREDICTOR_ENTRIES(PREDICTOR_ENTRIES),
        .INDEX_BITS(INDEX_BITS),
        .COUNTER_BITS(COUNTER_BITS)
    ) dut (
        .clk(clk),
        .reset(reset),

        .predict_enable(predict_enable),
        .pc_predict(pc_predict),

        .train_enable(train_enable),
        .pc_train(pc_train),
        .train_up(train_up),
        .train_down(train_down),

        .prediction_valid(prediction_valid),
        .friendly(friendly),
        .averse(averse),

        .counter_predict_debug(counter_predict_debug),
        .index_predict_debug(index_predict_debug)
    );

    /*
        Clock com período de 10 ps.
        Borda de subida em 5 ps, 15 ps, 25 ps...
    */
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    task mostra_estado;
        input [8*40:1] nome;
        begin
            #1;
            $display("%s -> index=%0d counter=%0d valid=%0d friendly=%0d averse=%0d",
                     nome,
                     index_predict_debug,
                     counter_predict_debug,
                     prediction_valid,
                     friendly,
                     averse);
        end
    endtask

    task pulso_train_down;
        begin
            train_enable = 1;
            train_up     = 0;
            train_down   = 1;
            @(posedge clk);
            #1;
            train_enable = 0;
            train_down   = 0;
        end
    endtask

    task pulso_train_up;
        begin
            train_enable = 1;
            train_up     = 1;
            train_down   = 0;
            @(posedge clk);
            #1;
            train_enable = 0;
            train_up     = 0;
        end
    endtask

    initial begin
        $dumpfile("waves_predictor.vcd");
        $dumpvars(0, tb_hawkeye_predictor);

        $display("==== Teste hawkeye_predictor ====");

        /*
            Estado inicial
        */
        reset          = 1;
        predict_enable = 0;
        pc_predict     = 64'h0000_0000_0000_0001;

        train_enable   = 0;
        pc_train       = 64'h0000_0000_0000_0001;
        train_up       = 0;
        train_down     = 0;

        /*
            Mantém reset por alguns ciclos.
        */
        repeat (3) @(posedge clk);
        #1;
        reset = 0;

        /*
            Habilita predição para o PC 1.
            Depois do reset, o contador deve estar em 16.
        */
        predict_enable = 1;
        pc_predict     = 64'h0000_0000_0000_0001;
        pc_train       = 64'h0000_0000_0000_0001;

        #10;
        mostra_estado("Depois do reset");
        $display("Esperado: counter=16, friendly=1, averse=0");

        /*
            Um train_down no mesmo PC:
            counter 16 -> 15.
            Como 15 < 16, deve virar averse.
        */
        pulso_train_down();
        #10;
        mostra_estado("Depois de 1 train_down");
        $display("Esperado: counter=15, friendly=0, averse=1");

        /*
            Outro train_down:
            counter 15 -> 14.
            Continua averse.
        */
        pulso_train_down();
        #10;
        mostra_estado("Depois de 2 train_down");
        $display("Esperado: counter=14, friendly=0, averse=1");

        /*
            Um train_up:
            counter 14 -> 15.
            Ainda averse.
        */
        pulso_train_up();
        #10;
        mostra_estado("Depois de 1 train_up");
        $display("Esperado: counter=15, friendly=0, averse=1");

        /*
            Outro train_up:
            counter 15 -> 16.
            Volta para friendly.
        */
        pulso_train_up();
        #10;
        mostra_estado("Depois de 2 train_up");
        $display("Esperado: counter=16, friendly=1, averse=0");

        /*
            Teste com outro PC.
            Deve estar independente e começar em 16.
        */
        pc_predict = 64'h0000_0000_0000_1234;
        pc_train   = 64'h0000_0000_0000_1234;

        #10;
        mostra_estado("Outro PC apos reset");
        $display("Esperado: counter=16, friendly=1, averse=0");

        $display("==== Fim do teste ====");
        $finish;
    end

endmodule   