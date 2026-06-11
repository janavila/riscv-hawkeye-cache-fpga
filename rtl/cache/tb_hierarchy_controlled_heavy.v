// =============================================================================
// tb_hierarchy_controlled_heavy.v
// -----------------------------------------------------------------------------
// Teste pesado da hierarquia L1 + L2 + Hawkeye com fill controlado.
//
// Objetivo:
// - Rodar muitos acessos, por padrao 100k.
// - Exercitar L1 com fill controlado.
// - Exercitar L2 + Hawkeye com PCs diferentes.
// - Forcar caminho FRIENDLY e AVERSE.
// - Misturar reuse, streaming, ruido e hot L1.
// - Checar contadores e sanidade geral.
// =============================================================================

`timescale 1ns/1ps

module tb_hierarchy_controlled_heavy #(
    parameter integer TOTAL_ACCESSES = 100000,
    parameter integer REPORT_EVERY   = 10000
);

    reg clk;
    reg rst;

    // ---------------- L1 ----------------
    reg         l1_req_valid;
    reg  [31:0] l1_req_addr;
    reg         l1_fill_valid;
    reg  [31:0] l1_fill_addr;

    wire        l1_hit;
    wire        l1_miss;
    wire [31:0] l1_hit_count;
    wire [31:0] l1_miss_count;

    // ---------------- L2 ----------------
    reg         l2_req_valid;
    reg  [31:0] l2_req_addr;
    reg  [31:0] l2_req_pc;

    wire        l2_done;
    wire        l2_hit;
    wire        l2_miss;
    wire [31:0] l2_hit_count;
    wire [31:0] l2_miss_count;

    // Interface L2 <-> politica Hawkeye
    wire [5:0]  pol_set;
    wire [31:0] pol_pc;
    wire [31:0] pol_addr;
    wire        pol_access;
    wire        pol_hit;
    wire [2:0]  pol_hit_way;
    wire        pol_need_victim;
    wire        pol_fill;
    wire [2:0]  pol_fill_way;
    wire [2:0]  pol_victim_way;
    wire        pol_victim_valid;

    // PCs de classes diferentes
    localparam [31:0] PC_REUSE  = 32'h0000_4000;
    localparam [31:0] PC_STREAM = 32'h0000_5000;
    localparam [31:0] PC_NOISE  = 32'h0000_6000;
    localparam [31:0] PC_HOTL1  = 32'h0000_7000;

    integer cpu_access_count;
    integer l2_access_count;

    integer reuse_cpu_total;
    integer stream_cpu_total;
    integer noise_cpu_total;
    integer hotl1_cpu_total;

    integer reuse_l2_total;
    integer stream_l2_total;
    integer noise_l2_total;
    integer hotl1_l2_total;

    integer reuse_l2_hits;
    integer stream_l2_hits;
    integer noise_l2_hits;
    integer hotl1_l2_hits;

    integer fill_friendly_count;
    integer fill_averse_count;
    integer sampler_hit_seen_count;
    integer training_done_count;
    integer victim_count;

    // ---------------- L1 com fill controlado ----------------
    cache_l1 #(
        .AUTO_FILL_ON_MISS(0)
    ) l1 (
        .clk(clk),
        .rst(rst),

        .req_valid(l1_req_valid),
        .req_addr(l1_req_addr),

        .fill_valid(l1_fill_valid),
        .fill_addr(l1_fill_addr),

        .hit(l1_hit),
        .miss(l1_miss),
        .hit_count(l1_hit_count),
        .miss_count(l1_miss_count)
    );

    // ---------------- L2 ----------------
    cache_l2 l2 (
        .clk(clk),
        .rst(rst),

        .req_valid(l2_req_valid),
        .req_addr(l2_req_addr),
        .req_pc(l2_req_pc),

        .done(l2_done),
        .hit(l2_hit),
        .miss(l2_miss),

        .pol_set(pol_set),
        .pol_pc(pol_pc),
        .pol_addr(pol_addr),
        .pol_access(pol_access),
        .pol_hit(pol_hit),
        .pol_hit_way(pol_hit_way),
        .pol_need_victim(pol_need_victim),
        .pol_fill(pol_fill),
        .pol_fill_way(pol_fill_way),
        .pol_victim_way(pol_victim_way),
        .pol_victim_valid(pol_victim_valid),

        .hit_count(l2_hit_count),
        .miss_count(l2_miss_count)
    );

    // ---------------- Hawkeye L2 Policy ----------------
    hawkeye_l2_policy pol (
        .clk(clk),
        .rst(rst),

        .pol_set(pol_set),
        .pol_pc(pol_pc),
        .pol_addr(pol_addr),
        .pol_access(pol_access),
        .pol_hit(pol_hit),
        .pol_hit_way(pol_hit_way),
        .pol_need_victim(pol_need_victim),
        .pol_fill(pol_fill),
        .pol_fill_way(pol_fill_way),

        .pol_victim_way(pol_victim_way),
        .pol_victim_valid(pol_victim_valid)
    );

    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Endereco L2: offset=6, index=6.
    // addr = tag << 12 | set << 6.
    // -------------------------------------------------------------------------
    function [31:0] addr_l2;
        input integer set_id;
        input integer tag_id;
        begin
            addr_l2 = (tag_id * 32'h00001000) + (set_id * 32'h00000040);
        end
    endfunction

    // -------------------------------------------------------------------------
    // Mesma hash usada antes para acessar predictor_table em teste dirigido.
    // -------------------------------------------------------------------------
    function [10:0] hawkeye_index;
        input [63:0] value_in;
        integer k;
        reg [63:0] result;
        begin
            result = value_in;

            for(k = 0; k < 32; k = k + 1) begin
                if(result[0])
                    result = (result >> 1) ^ 64'd3988292384;
                else
                    result = result >> 1;
            end

            hawkeye_index = result[10:0];
        end
    endfunction

    task set_predictor_counter;
        input [31:0] pc32;
        input [4:0]  value;
        reg [10:0] idx;
        begin
            idx = hawkeye_index({32'd0, pc32});
            pol.hawkeye_core.predictor_inst.predictor_table[idx] = value;
        end
    endtask

    task prepare_predictor_bias;
        begin
            // Teste pesado dirigido:
            // REUSE e HOTL1 tendem a friendly.
            // STREAM e NOISE tendem a averse.
            set_predictor_counter(PC_REUSE,  5'd31);
            set_predictor_counter(PC_HOTL1,  5'd31);
            set_predictor_counter(PC_STREAM, 5'd0);
            set_predictor_counter(PC_NOISE,  5'd0);
        end
    endtask

    task fill_l1;
        input [31:0] endereco;
        begin
            @(negedge clk);
            l1_fill_valid = 1'b1;
            l1_fill_addr  = endereco;

            @(negedge clk);
            l1_fill_valid = 1'b0;
            l1_fill_addr  = 32'd0;

            @(negedge clk);
        end
    endtask

    task acessa_l2;
        input [31:0] endereco;
        input [31:0] pc;
        output integer l2_was_hit;

        integer timeout;

        begin
            l2_access_count = l2_access_count + 1;

            @(negedge clk);
            l2_req_valid = 1'b1;
            l2_req_addr  = endereco;
            l2_req_pc    = pc;

            @(negedge clk);
            l2_req_valid = 1'b0;

            timeout = 0;
            while(l2_done !== 1'b1 && timeout < 1000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end

            if(timeout >= 1000) begin
                $display("[ERRO t=%0t] TIMEOUT L2 addr=0x%08h pc=0x%08h",
                         $time, endereco, pc);
                $finish;
            end

            l2_was_hit = l2_hit ? 1 : 0;

            @(negedge clk);
        end
    endtask

    task cpu_acesso;
        input [31:0] endereco;
        input [31:0] pc;
        input integer classe;

        reg [31:0] l1_hits_before;
        reg [31:0] l1_misses_before;

        integer l2_was_hit;

        begin
            cpu_access_count = cpu_access_count + 1;

            if(classe == 0) reuse_cpu_total  = reuse_cpu_total  + 1;
            if(classe == 1) stream_cpu_total = stream_cpu_total + 1;
            if(classe == 2) noise_cpu_total  = noise_cpu_total  + 1;
            if(classe == 3) hotl1_cpu_total  = hotl1_cpu_total  + 1;

            l1_hits_before   = l1_hit_count;
            l1_misses_before = l1_miss_count;

            @(negedge clk);
            l1_req_valid = 1'b1;
            l1_req_addr  = endereco;

            @(negedge clk);
            l1_req_valid = 1'b0;

            if(l1_hit_count > l1_hits_before) begin
                // L1 HIT: nao acessa L2.
            end
            else if(l1_miss_count > l1_misses_before) begin
                acessa_l2(endereco, pc, l2_was_hit);

                if(classe == 0) begin
                    reuse_l2_total = reuse_l2_total + 1;
                    if(l2_was_hit) reuse_l2_hits = reuse_l2_hits + 1;
                end
                if(classe == 1) begin
                    stream_l2_total = stream_l2_total + 1;
                    if(l2_was_hit) stream_l2_hits = stream_l2_hits + 1;
                end
                if(classe == 2) begin
                    noise_l2_total = noise_l2_total + 1;
                    if(l2_was_hit) noise_l2_hits = noise_l2_hits + 1;
                end
                if(classe == 3) begin
                    hotl1_l2_total = hotl1_l2_total + 1;
                    if(l2_was_hit) hotl1_l2_hits = hotl1_l2_hits + 1;
                end

                // Fill controlado da L1 depois da resposta da L2.
                fill_l1(endereco);
            end
            else begin
                $display("[ERRO t=%0t] Acesso CPU nao alterou contador L1 addr=0x%08h pc=0x%08h",
                         $time, endereco, pc);
                $finish;
            end

            @(negedge clk);
        end
    endtask

    // Monitores leves, sem imprimir por acesso.
    always @(posedge clk) begin
        if(!rst) begin
            if(pol_fill) begin
                if(pol.pred_friendly_latched)
                    fill_friendly_count <= fill_friendly_count + 1;
                else
                    fill_averse_count <= fill_averse_count + 1;
            end

            if(pol.hawkeye_sampler_hit_debug)
                sampler_hit_seen_count <= sampler_hit_seen_count + 1;

            if(pol.hawkeye_training_done)
                training_done_count <= training_done_count + 1;

            if(pol_victim_valid)
                victim_count <= victim_count + 1;
        end
    end

    integer i;
    integer reuse_ptr;
    integer stream_ptr;
    integer noise_ptr;

    reg [31:0] cur_addr;
    reg [31:0] cur_pc;
    integer cur_class;

    initial begin
        $dumpfile("ondas_hierarchy_controlled_heavy.vcd");
        $dumpvars(0, tb_hierarchy_controlled_heavy);

        clk = 0;
        rst = 1;

        l1_req_valid  = 0;
        l1_req_addr   = 0;
        l1_fill_valid = 0;
        l1_fill_addr  = 0;

        l2_req_valid  = 0;
        l2_req_addr   = 0;
        l2_req_pc     = 0;

        cpu_access_count = 0;
        l2_access_count  = 0;

        reuse_cpu_total = 0;
        stream_cpu_total = 0;
        noise_cpu_total = 0;
        hotl1_cpu_total = 0;

        reuse_l2_total = 0;
        stream_l2_total = 0;
        noise_l2_total = 0;
        hotl1_l2_total = 0;

        reuse_l2_hits = 0;
        stream_l2_hits = 0;
        noise_l2_hits = 0;
        hotl1_l2_hits = 0;

        fill_friendly_count = 0;
        fill_averse_count = 0;
        sampler_hit_seen_count = 0;
        training_done_count = 0;
        victim_count = 0;

        reuse_ptr = 0;
        stream_ptr = 0;
        noise_ptr = 0;

        @(negedge clk);
        @(negedge clk);
        rst = 0;
        @(negedge clk);

        prepare_predictor_bias();

        $display("=========================================================");
        $display(" TESTE PESADO CONTROLADO L1 + L2 + HAWKEYE");
        $display(" TOTAL_ACCESSES=%0d", TOTAL_ACCESSES);
        $display("=========================================================");

        for(i = 0; i < TOTAL_ACCESSES; i = i + 1) begin
            // Reforca o bias a cada bloco grande para garantir os dois caminhos.
            if((i % 5000) == 0)
                prepare_predictor_bias();

            // Classe 3: hot L1. Mesmo endereco, set diferente dos de pressao.
            // Deve gerar L1 hits depois do primeiro fill.
            if((i % 20) == 0) begin
                cur_addr  = addr_l2(10, 777);
                cur_pc    = PC_HOTL1;
                cur_class = 3;
            end

            // Classe 2: ruido em sets variados.
            else if((i % 37) == 0) begin
                cur_addr  = addr_l2((noise_ptr % 8) + 20, 2000 + noise_ptr);
                cur_pc    = PC_NOISE;
                cur_class = 2;
                noise_ptr = noise_ptr + 1;
            end

            // Classe 0: reuse. 6 blocos no mesmo set da L2.
            // Como cabem em 8 ways, devem gerar muitos hits na L2.
            else if((i % 2) == 0) begin
                cur_addr  = addr_l2(0, 100 + (reuse_ptr % 6));
                cur_pc    = PC_REUSE;
                cur_class = 0;
                reuse_ptr = reuse_ptr + 1;
            end

            // Classe 1: stream. Sempre tag nova no mesmo set da L2.
            // Deve gerar misses e evictions.
            else begin
                cur_addr  = addr_l2(0, 10000 + stream_ptr);
                cur_pc    = PC_STREAM;
                cur_class = 1;
                stream_ptr = stream_ptr + 1;
            end

            cpu_acesso(cur_addr, cur_pc, cur_class);

            if(((i + 1) % REPORT_EVERY) == 0) begin
                $display("[PROGRESS] %0d/%0d CPU=%0d L2=%0d | L1 h/m=%0d/%0d | L2 h/m=%0d/%0d | fill F/A=%0d/%0d | train=%0d sampler=%0d victims=%0d",
                         i + 1, TOTAL_ACCESSES,
                         cpu_access_count,
                         l2_access_count,
                         l1_hit_count,
                         l1_miss_count,
                         l2_hit_count,
                         l2_miss_count,
                         fill_friendly_count,
                         fill_averse_count,
                         training_done_count,
                         sampler_hit_seen_count,
                         victim_count);
            end
        end

        $display("---------------------------------------------------------");
        $display(" RESULTADO FINAL HEAVY");
        $display(" CPU acessos = %0d", cpu_access_count);
        $display(" L2 acessos  = %0d", l2_access_count);
        $display(" L1: hits=%0d misses=%0d", l1_hit_count, l1_miss_count);
        $display(" L2: hits=%0d misses=%0d", l2_hit_count, l2_miss_count);
        $display(" fills FRIENDLY=%0d AVERSE=%0d", fill_friendly_count, fill_averse_count);
        $display(" sampler_hit_seen=%0d training_done=%0d victims=%0d",
                 sampler_hit_seen_count, training_done_count, victim_count);
        $display("");
        $display(" L2 por classe:");
        $display(" REUSE : hits=%0d total=%0d", reuse_l2_hits, reuse_l2_total);
        $display(" STREAM: hits=%0d total=%0d", stream_l2_hits, stream_l2_total);
        $display(" NOISE : hits=%0d total=%0d", noise_l2_hits, noise_l2_total);
        $display(" HOTL1 : hits=%0d total=%0d", hotl1_l2_hits, hotl1_l2_total);
        $display("---------------------------------------------------------");

        // Checks de sanidade
        if(l2_access_count !== l1_miss_count) begin
            $display("[ERRO] L2 acessos (%0d) diferente de L1 misses (%0d)",
                     l2_access_count, l1_miss_count);
            $finish;
        end

        if((l2_hit_count + l2_miss_count) !== l2_access_count) begin
            $display("[ERRO] L2 hits+misses diferente de acessos L2.");
            $finish;
        end

        if(fill_friendly_count == 0) begin
            $display("[ERRO] Nenhum fill FRIENDLY observado.");
            $finish;
        end

        if(fill_averse_count == 0) begin
            $display("[ERRO] Nenhum fill AVERSE observado.");
            $finish;
        end

        if(training_done_count == 0) begin
            $display("[ERRO] Nenhum training_done observado.");
            $finish;
        end

        if(sampler_hit_seen_count == 0) begin
            $display("[ERRO] Nenhum sampler_hit observado.");
            $finish;
        end

        if(victim_count == 0) begin
            $display("[ERRO] Nenhuma vitima RRIP observada.");
            $finish;
        end

        if(reuse_l2_hits == 0) begin
            $display("[ERRO] REUSE nao gerou nenhum L2 HIT.");
            $finish;
        end

        $display("[OK] Teste pesado controlado passou.");

        #20;
        $finish;
    end

endmodule