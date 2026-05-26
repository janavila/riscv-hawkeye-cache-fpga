`timescale 1ps/1ps

module tb_hawkeye_training_controller;

    parameter PC_BITS = 64;

    reg                 clk;
    reg                 reset;

    reg                 access_valid;
    reg                 access_miss;

    reg                 sampler_hit;
    reg  [PC_BITS-1:0] pc_anterior;

    reg                 optgen_done;
    reg                 optgen_should_cache;

    wire                optgen_start_check;
    wire                optgen_start_set_access;

    wire                predictor_train_enable;
    wire                predictor_train_up;
    wire                predictor_train_down;
    wire [PC_BITS-1:0] pc_train;

    wire                sampler_update_enable;

    wire                busy;
    wire                done;
    wire [3:0]          state_debug;

    hawkeye_training_controller #(
        .PC_BITS(PC_BITS)
    ) dut (
        .clk(clk),
        .reset(reset),

        .access_valid(access_valid),
        .access_miss(access_miss),

        .sampler_hit(sampler_hit),
        .pc_anterior(pc_anterior),

        .optgen_done(optgen_done),
        .optgen_should_cache(optgen_should_cache),

        .optgen_start_check(optgen_start_check),
        .optgen_start_set_access(optgen_start_set_access),

        .predictor_train_enable(predictor_train_enable),
        .predictor_train_up(predictor_train_up),
        .predictor_train_down(predictor_train_down),
        .pc_train(pc_train),

        .sampler_update_enable(sampler_update_enable),

        .busy(busy),
        .done(done),
        .state_debug(state_debug)
    );

    /*
        Clock de 10 ps.
    */
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    /*
        Pulso de access_valid por 1 ciclo.
    */
    task pulso_access;
        begin
            access_valid = 1'b1;
            @(posedge clk);
            #1;
            access_valid = 1'b0;
        end
    endtask

    /*
        Simula o OPTgen respondendo após alguns ciclos.

        should_cache_in = 1 -> OPTgen diz que deveria ficar na cache.
        should_cache_in = 0 -> OPTgen diz que não deveria ficar.
    */
    task responde_optgen;
        input should_cache_in;
        begin
            repeat (3) @(posedge clk);
            #1;
            optgen_should_cache = should_cache_in;
            optgen_done = 1'b1;

            @(posedge clk);
            #1;
            optgen_done = 1'b0;
        end
    endtask

    task espera_done_controller;
        begin
            wait(done == 1'b1);
            #1;
        end
    endtask

    initial begin
        $dumpfile("waves_training_controller.vcd");
        $dumpvars(0, tb_hawkeye_training_controller);

        $display("==== Teste hawkeye_training_controller ====");

        reset = 1'b1;

        access_valid = 1'b0;
        access_miss  = 1'b0;

        sampler_hit  = 1'b0;
        pc_anterior  = 64'd0;

        optgen_done         = 1'b0;
        optgen_should_cache = 1'b0;

        repeat (3) @(posedge clk);
        #1;
        reset = 1'b0;

        #10;

        /*
            CASO 1:
            sampler_hit = 0, access_miss = 1.
            Não deve chamar optgen_check.
            Deve chamar set_access e atualizar sampler.
        */
        $display("---- Caso 1: sampler miss ----");

        sampler_hit = 1'b0;
        access_miss = 1'b1;
        pc_anterior = 64'd100;

        pulso_access();

        /*
            Como nesse caminho o controller chama set_access,
            precisamos simular optgen_done para finalizar set_access.
        */
        wait(optgen_start_set_access == 1'b1);
        responde_optgen(1'b0);

        espera_done_controller();

        $display("Caso 1 final -> done=%0d train_en=%0d up=%0d down=%0d sampler_update=%0d",
                 done, predictor_train_enable, predictor_train_up, predictor_train_down, sampler_update_enable);
        $display("Esperado: sem treino de preditor; caminho apenas set_access + sampler_update");

        #20;

        /*
            CASO 2:
            sampler_hit = 1, mas access_miss = 0.
            Ou seja, foi hit na cache.
            Não deve chamar optgen_check.
            Não deve treinar preditor.
            Deve chamar set_access e atualizar sampler.
        */
        $display("---- Caso 2: sampler hit, mas access hit ----");

        sampler_hit = 1'b1;
        access_miss = 1'b0;
        pc_anterior = 64'd200;

        pulso_access();

        wait(optgen_start_set_access == 1'b1);
        responde_optgen(1'b0);

        espera_done_controller();

        $display("Caso 2 final -> done=%0d train_en=%0d up=%0d down=%0d sampler_update=%0d",
                 done, predictor_train_enable, predictor_train_up, predictor_train_down, sampler_update_enable);
        $display("Esperado: sem treino de preditor; caminho apenas set_access + sampler_update");

        #20;

        /*
            CASO 3:
            sampler_hit = 1 e access_miss = 1.
            Deve chamar optgen_check.
            OPTgen responde should_cache = 1.
            Controller deve gerar train_up.
        */
        $display("---- Caso 3: sampler hit + miss + should_cache=1 ----");

        sampler_hit = 1'b1;
        access_miss = 1'b1;
        pc_anterior = 64'd300;

        pulso_access();

        wait(optgen_start_check == 1'b1);
        responde_optgen(1'b1);

        /*
            Depois do treino, controller chama set_access.
        */
        wait(optgen_start_set_access == 1'b1);
        responde_optgen(1'b1);

        espera_done_controller();

        $display("Caso 3 final -> done=%0d pc_train=%0d train_en=%0d up=%0d down=%0d sampler_update=%0d",
                 done, pc_train, predictor_train_enable, predictor_train_up, predictor_train_down, sampler_update_enable);
        $display("Esperado: em algum ciclo train_enable=1, train_up=1, pc_train=300");

        #20;

        /*
            CASO 4:
            sampler_hit = 1 e access_miss = 1.
            OPTgen responde should_cache = 0.
            Controller deve gerar train_down.
        */
        $display("---- Caso 4: sampler hit + miss + should_cache=0 ----");

        sampler_hit = 1'b1;
        access_miss = 1'b1;
        pc_anterior = 64'd400;

        pulso_access();

        wait(optgen_start_check == 1'b1);
        responde_optgen(1'b0);

        wait(optgen_start_set_access == 1'b1);
        responde_optgen(1'b0);

        espera_done_controller();

        $display("Caso 4 final -> done=%0d pc_train=%0d train_en=%0d up=%0d down=%0d sampler_update=%0d",
                 done, pc_train, predictor_train_enable, predictor_train_up, predictor_train_down, sampler_update_enable);
        $display("Esperado: em algum ciclo train_enable=1, train_down=1, pc_train=400");

        #20;

        $display("==== Fim do teste ====");
        $finish;
    end

endmodule   