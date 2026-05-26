`timescale 1ps/1ps

module tb_sampler;

    parameter SAMPLER_SETS   = 64;
    parameter SAMPLER_HIST   = 8;
    parameter SET_BITS       = 6;
    parameter POS_BITS       = 3;
    parameter SIGNATURE_BITS = 8;
    parameter PC_BITS        = 64;
    parameter TIME_BITS      = 32;
    parameter LRU_BITS       = 4;

    reg                         clk;
    reg                         reset;

    reg                         access_valid;
    reg                         update_enable;

    reg  [SET_BITS-1:0]         sample_set;
    reg  [SIGNATURE_BITS-1:0]   signature_atual;
    reg  [PC_BITS-1:0]          pc_atual;
    reg  [TIME_BITS-1:0]        current_time;

    wire                        sampler_hit;
    wire                        sampler_miss;
    wire [POS_BITS-1:0]         sampler_pos;
    wire [POS_BITS-1:0]         pos_write;
    wire [PC_BITS-1:0]          pc_anterior;
    wire [TIME_BITS-1:0]        previous_time;

    wire [SAMPLER_HIST-1:0]     match_vector_debug;
    wire [SAMPLER_HIST-1:0]     valid_entries_debug;

    sampler #(
        .SAMPLER_SETS(SAMPLER_SETS),
        .SAMPLER_HIST(SAMPLER_HIST),
        .SET_BITS(SET_BITS),
        .POS_BITS(POS_BITS),
        .SIGNATURE_BITS(SIGNATURE_BITS),
        .PC_BITS(PC_BITS),
        .TIME_BITS(TIME_BITS),
        .LRU_BITS(LRU_BITS)
    ) dut (
        .clk(clk),
        .reset(reset),

        .access_valid(access_valid),
        .update_enable(update_enable),

        .sample_set(sample_set),
        .signature_atual(signature_atual),
        .pc_atual(pc_atual),
        .current_time(current_time),

        .sampler_hit(sampler_hit),
        .sampler_miss(sampler_miss),
        .sampler_pos(sampler_pos),
        .pos_write(pos_write),
        .pc_anterior(pc_anterior),
        .previous_time(previous_time),

        .match_vector_debug(match_vector_debug),
        .valid_entries_debug(valid_entries_debug)
    );

    /*
        Clock de 10 ps.
    */
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    task mostra_estado;
        input [8*50:1] nome;
        begin
            #1;
            $display("%s -> hit=%0d miss=%0d sampler_pos=%0d pos_write=%0d pc_ant=%0d prev_time=%0d valid=%b match=%b",
                     nome,
                     sampler_hit,
                     sampler_miss,
                     sampler_pos,
                     pos_write,
                     pc_anterior,
                     previous_time,
                     valid_entries_debug,
                     match_vector_debug);
        end
    endtask

    task pulso_update;
        begin
            access_valid  = 1;
            update_enable = 1;
            @(posedge clk);
            #1;
            update_enable = 0;
            access_valid  = 0;
        end
    endtask

    initial begin
        $dumpfile("waves_sampler.vcd");
        $dumpvars(0, tb_sampler);

        $display("==== Teste sampler ====");

        reset          = 1;
        access_valid   = 0;
        update_enable  = 0;

        sample_set      = 6'd2;
        signature_atual = 8'hAA;
        pc_atual        = 64'd100;
        current_time    = 32'd10;

        /*
            Mantém reset por alguns ciclos.
        */
        repeat (3) @(posedge clk);
        #1;
        reset = 0;

        /*
            Caso 1:
            Depois do reset, sampler deve estar vazio.
            Procurando AA no set 2, não deve encontrar.
        */
        #10;
        mostra_estado("Caso 1: apos reset procurando AA");
        $display("Esperado: hit=0 miss=1 pos_write=0 valid=00000000");

        /*
            Caso 2:
            Atualiza sampler com assinatura AA, PC=100, tempo=10.
            Como estava vazio, deve gravar na posição 0.
        */
        pulso_update();

        #10;
        mostra_estado("Caso 2: depois de gravar AA");
        $display("Esperado: hit=1 sampler_pos=0 pc_ant=100 prev_time=10 valid[0]=1");

        /*
            Caso 3:
            Mesmo set e mesma assinatura AA.
            Deve encontrar histórico na posição 0.
        */
        signature_atual = 8'hAA;
        pc_atual        = 64'd200;
        current_time    = 32'd20;

        #10;
        mostra_estado("Caso 3: procurando AA novamente");
        $display("Esperado: hit=1 sampler_pos=0 pc_ant=100 prev_time=10");

        /*
            Caso 4:
            Atualiza a mesma assinatura AA.
            Como houve hit, deve atualizar a própria posição 0.
            Agora PC anterior deve virar 200 e tempo anterior 20.
        */
        pulso_update();

        #10;
        mostra_estado("Caso 4: depois de atualizar AA");
        $display("Esperado: hit=1 sampler_pos=0 pc_ant=200 prev_time=20");

        /*
            Caso 5:
            Nova assinatura BB no mesmo set.
            Como BB ainda não existe, deve dar miss e escolher próxima inválida.
            Esperado pos_write=1.
        */
        signature_atual = 8'hBB;
        pc_atual        = 64'd300;
        current_time    = 32'd30;

        #10;
        mostra_estado("Caso 5: procurando BB nova");
        $display("Esperado: hit=0 miss=1 pos_write=1");

        /*
            Grava BB.
        */
        pulso_update();

        #10;
        mostra_estado("Caso 6: depois de gravar BB");
        $display("Esperado: hit=1 sampler_pos=1 pc_ant=300 prev_time=30");

        /*
            Caso 7:
            Volta para AA.
            Deve encontrar AA ainda na posição 0.
        */
        signature_atual = 8'hAA;
        pc_atual        = 64'd400;
        current_time    = 32'd40;

        #10;
        mostra_estado("Caso 7: procurando AA de novo");
        $display("Esperado: hit=1 sampler_pos=0 pc_ant=200 prev_time=20");

        $display("==== Fim do teste ====");
        $finish;
    end

endmodule   