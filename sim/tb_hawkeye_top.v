`timescale 1ps/1ps

module tb_hawkeye_top;

    parameter PC_BITS        = 64;
    parameter BLOCK_BITS     = 64;

    parameter SAMPLER_SETS   = 64;
    parameter SAMPLER_HIST   = 8;
    parameter SET_BITS       = 6;
    parameter POS_BITS       = 3;
    parameter SIGNATURE_BITS = 8;
    parameter TIME_BITS      = 32;
    parameter LRU_BITS       = 4;

    parameter OPTGEN_SIZE       = 128;
    parameter OPTGEN_INDEX_BITS = 7;
    parameter LIVENESS_BITS     = 8;
    parameter CACHE_SIZE_BITS   = 8;

    parameter PREDICTOR_ENTRIES    = 2048;
    parameter PREDICTOR_INDEX_BITS = 11;
    parameter COUNTER_BITS         = 5;

    reg                         clk;
    reg                         reset;

    reg                         access_valid;
    reg  [PC_BITS-1:0]          pc;
    reg  [BLOCK_BITS-1:0]       block_addr;
    reg  [SET_BITS-1:0]         set_index;
    reg                         access_miss;
    reg  [CACHE_SIZE_BITS-1:0]  optgen_cache_size;

    wire                        prediction_valid;
    wire                        friendly;
    wire                        averse;

    wire                        training_busy;
    wire                        training_done;

    wire [SIGNATURE_BITS-1:0]   signature_debug;
    wire [SET_BITS-1:0]         sample_set_debug;
    wire [TIME_BITS-1:0]        current_time_debug;
    wire [OPTGEN_INDEX_BITS-1:0] current_val_debug;
    wire [OPTGEN_INDEX_BITS-1:0] prev_val_debug;
    wire                        sampler_hit_debug;
    wire [POS_BITS-1:0]         sampler_pos_debug;
    wire [3:0]                  controller_state_debug;

    hawkeye_top #(
        .PC_BITS(PC_BITS),
        .BLOCK_BITS(BLOCK_BITS),

        .SAMPLER_SETS(SAMPLER_SETS),
        .SAMPLER_HIST(SAMPLER_HIST),
        .SET_BITS(SET_BITS),
        .POS_BITS(POS_BITS),
        .SIGNATURE_BITS(SIGNATURE_BITS),
        .TIME_BITS(TIME_BITS),
        .LRU_BITS(LRU_BITS),

        .OPTGEN_SIZE(OPTGEN_SIZE),
        .OPTGEN_INDEX_BITS(OPTGEN_INDEX_BITS),
        .LIVENESS_BITS(LIVENESS_BITS),
        .CACHE_SIZE_BITS(CACHE_SIZE_BITS),

        .PREDICTOR_ENTRIES(PREDICTOR_ENTRIES),
        .PREDICTOR_INDEX_BITS(PREDICTOR_INDEX_BITS),
        .COUNTER_BITS(COUNTER_BITS)
    ) dut (
        .clk(clk),
        .reset(reset),

        .access_valid(access_valid),
        .pc(pc),
        .block_addr(block_addr),
        .set_index(set_index),
        .access_miss(access_miss),

        .optgen_cache_size(optgen_cache_size),

        .prediction_valid(prediction_valid),
        .friendly(friendly),
        .averse(averse),

        .training_busy(training_busy),
        .training_done(training_done),

        .signature_debug(signature_debug),
        .sample_set_debug(sample_set_debug),
        .current_time_debug(current_time_debug),
        .current_val_debug(current_val_debug),
        .prev_val_debug(prev_val_debug),
        .sampler_hit_debug(sampler_hit_debug),
        .sampler_pos_debug(sampler_pos_debug),
        .controller_state_debug(controller_state_debug)
    );

    /*
        Clock de 10 ps.
    */
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    task executa_acesso;
        input [8*50:1] nome;
        input [PC_BITS-1:0] pc_in;
        input [BLOCK_BITS-1:0] block_in;
        input [SET_BITS-1:0] set_in;
        input miss_in;
        begin
            pc          = pc_in;
            block_addr  = block_in;
            set_index   = set_in;
            access_miss = miss_in;

            /*
                Colocamos access_valid = 1 antes da borda.
                Assim conseguimos observar a predição e o sampler no início do acesso.
            */
            access_valid = 1'b1;
            #1;

            $display("INICIO %s -> pc=%0d block=0x%h set=%0d miss=%0d sig=0x%h time=%0d sampler_hit=%0d sampler_pos=%0d pred_valid=%0d friendly=%0d averse=%0d",
                     nome,
                     pc,
                     block_addr,
                     set_index,
                     access_miss,
                     signature_debug,
                     current_time_debug,
                     sampler_hit_debug,
                     sampler_pos_debug,
                     prediction_valid,
                     friendly,
                     averse);

            @(posedge clk);
            #1;
            access_valid = 1'b0;

            /*
                Espera o treinamento daquele acesso terminar.
            */
            wait(training_done == 1'b1);

            /*
                Espera mais uma borda para o set_timer ser atualizado.
            */
            @(posedge clk);
            #1;

            $display("FIM    %s -> time=%0d current_val=%0d prev_val=%0d sampler_hit=%0d sampler_pos=%0d training_done=%0d state=%0d",
                     nome,
                     current_time_debug,
                     current_val_debug,
                     prev_val_debug,
                     sampler_hit_debug,
                     sampler_pos_debug,
                     training_done,
                     controller_state_debug);

            /*
                Garante espaço antes do próximo acesso.
            */
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        $dumpfile("waves_hawkeye_top.vcd");
        $dumpvars(0, tb_hawkeye_top);

        $display("==== Teste hawkeye_top ====");

        reset             = 1'b1;
        access_valid      = 1'b0;
        pc                = 64'd0;
        block_addr        = 64'd0;
        set_index         = 6'd2;
        access_miss       = 1'b0;
        optgen_cache_size = 8'd2;

        repeat (4) @(posedge clk);
        #1;
        reset = 1'b0;

        #10;

        /*
            Acesso 1:
            Primeiro acesso ao bloco 1 no set 2.
            Sampler ainda está vazio.
            Esperado no início: sampler_hit = 0.
            Ao final: sampler passa a reconhecer esse bloco.
        */
        executa_acesso("Acesso 1: primeiro bloco 1",
                       64'd100,
                       64'h0000_0000_0000_0001,
                       6'd2,
                       1'b1);

        /*
            Acesso 2:
            Mesmo bloco 1 no mesmo set.
            Agora o sampler deve encontrar histórico.
            Como access_miss = 1 e sampler_hit = 1, o controller deve acionar OPTgen.
        */
        executa_acesso("Acesso 2: repete bloco 1",
                       64'd200,
                       64'h0000_0000_0000_0001,
                       6'd2,
                       1'b1);

        /*
            Acesso 3:
            Novo bloco no mesmo set.
            Como a assinatura é diferente, deve dar sampler miss no início.
            Ao final, o sampler deve gravar esse segundo bloco em outra posição.
        */
        executa_acesso("Acesso 3: novo bloco 1234",
                       64'd300,
                       64'h0000_0000_0000_1234,
                       6'd2,
                       1'b1);

        /*
            Acesso 4:
            Volta para o bloco 1.
            Deve encontrar histórico do bloco 1 novamente.
        */
        executa_acesso("Acesso 4: volta bloco 1",
                       64'd400,
                       64'h0000_0000_0000_0001,
                       6'd2,
                       1'b1);

        $display("==== Fim do teste ====");
        $finish;
    end

endmodule   