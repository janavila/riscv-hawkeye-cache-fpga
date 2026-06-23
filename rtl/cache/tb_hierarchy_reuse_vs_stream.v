// =============================================================================
// tb_hierarchy_reuse_vs_stream.v
// -----------------------------------------------------------------------------
// Teste da hierarquia completa com dois comportamentos opostos:
//
// PC_REUSE:
//   - Reusa sempre os mesmos 4 enderecos.
//   - Como os 4 enderecos conflitam na L1 2-way, gera varios L1 misses.
//   - Depois do aquecimento, espera-se que muitos desses misses sejam L2 hits.
//
// PC_STREAM:
//   - Gera endereco novo a cada acesso.
//   - Nao deve ter reuso real.
//   - Espera-se L1 miss e L2 miss na maioria/todos os acessos.
//
// Objetivo:
//   - Validar a hierarquia em carga longa.
//   - Separar comportamento de reuso forte e streaming sem reuso.
//   - Observar se a L2 consegue preservar dados reutilizados.
// =============================================================================

`timescale 1ns/1ps

module tb_hierarchy_reuse_vs_stream #(
    parameter TOTAL_ACCESSES = 100000,
    parameter REPORT_EVERY   = 10000,

    // Limiares simples para sanity check.
    // O REUSE deve ter boa taxa de hit na L2 depois do aquecimento.
    parameter MIN_REUSE_L2_HIT_RATE_PERCENT = 50,

    // STREAM idealmente nao deve dar L2 hit, pois nunca repete bloco.
    // Deixei como parametro para poder relaxar se necessario.
    parameter MAX_STREAM_L2_HITS_ALLOWED = 0
);

    reg clk;
    reg rst;

    reg         req_valid;
    reg  [31:0] req_addr;
    reg  [31:0] req_pc;

    wire        done;
    wire        busy;

    wire        resp_l1_hit;
    wire        resp_l1_miss;
    wire        resp_l2_access;
    wire        resp_l2_hit;
    wire        resp_l2_miss;

    wire [31:0] l1_hit_count;
    wire [31:0] l1_miss_count;
    wire [31:0] l2_hit_count;
    wire [31:0] l2_miss_count;

    wire [2:0]  state_debug;

    integer i;
    integer errors;
    integer timeout_counter;

    reg [31:0] addr;
    reg [31:0] pc;

    reg is_reuse_access;
    reg is_stream_access;

    integer reuse_idx;
    integer stream_idx;

    // Contadores antes/depois
    reg [31:0] l1h_before;
    reg [31:0] l1m_before;
    reg [31:0] l2h_before;
    reg [31:0] l2m_before;

    reg [31:0] dl1h;
    reg [31:0] dl1m;
    reg [31:0] dl2h;
    reg [31:0] dl2m;

    // Contadores por classe
    reg [31:0] reuse_accesses;
    reg [31:0] stream_accesses;

    reg [31:0] reuse_l1_hits;
    reg [31:0] reuse_l1_misses;
    reg [31:0] reuse_l2_hits;
    reg [31:0] reuse_l2_misses;

    reg [31:0] stream_l1_hits;
    reg [31:0] stream_l1_misses;
    reg [31:0] stream_l2_hits;
    reg [31:0] stream_l2_misses;

    integer reuse_l2_total;
    integer stream_l2_total;
    integer reuse_l2_hit_rate;
    integer stream_l2_hit_rate;

    localparam [31:0] PC_REUSE  = 32'h0000_AAAA;
    localparam [31:0] PC_STREAM = 32'h0000_BBBB;

    // =========================================================================
    // DUT
    // =========================================================================
    cache_hierarchy_top dut (
        .clk(clk),
        .rst(rst),

        .req_valid(req_valid),
        .req_addr(req_addr),
        .req_pc(req_pc),

        .done(done),
        .busy(busy),

        .resp_l1_hit(resp_l1_hit),
        .resp_l1_miss(resp_l1_miss),
        .resp_l2_access(resp_l2_access),
        .resp_l2_hit(resp_l2_hit),
        .resp_l2_miss(resp_l2_miss),

        .l1_hit_count(l1_hit_count),
        .l1_miss_count(l1_miss_count),
        .l2_hit_count(l2_hit_count),
        .l2_miss_count(l2_miss_count),

        .state_debug(state_debug)
    );

    // =========================================================================
    // Clock
    // =========================================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================================
    // Padrao de acesso
    // =========================================================================
    task choose_pattern;
        input integer idx;
        output [31:0] out_addr;
        output [31:0] out_pc;
        output out_is_reuse;
        output out_is_stream;

        begin
            /*
                Alterna:
                - acesso par: PC_REUSE
                - acesso impar: PC_STREAM

                PC_REUSE:
                Usa 4 enderecos que conflitam na L1:
                    0x0000_0000
                    0x0000_0800
                    0x0000_1000
                    0x0000_1800

                Como a L1 tem 2 vias, esse conjunto de 4 blocos causa conflito.
                Mas a L2 deve conseguir manter esses blocos após aquecimento.

                PC_STREAM:
                Gera endereco novo sempre.
                Usa passo 0x1000 para manter conflito forte e evitar reuso.
            */

            if ((idx % 2) == 0) begin
                out_is_reuse  = 1'b1;
                out_is_stream = 1'b0;
                out_pc        = PC_REUSE;

                case (reuse_idx % 4)
                    0: out_addr = 32'h0000_0000;
                    1: out_addr = 32'h0000_0800;
                    2: out_addr = 32'h0000_1000;
                    default: out_addr = 32'h0000_1800;
                endcase

                reuse_idx = reuse_idx + 1;
            end
            else begin
                out_is_reuse  = 1'b0;
                out_is_stream = 1'b1;
                out_pc        = PC_STREAM;

                // Streaming sem reuso: cada stream_idx gera um bloco novo.
                // Base alta para nao colidir com os 4 enderecos do PC_REUSE.
                out_addr = 32'h1000_0000 + (stream_idx * 32'h0000_1000);

                stream_idx = stream_idx + 1;
            end
        end
    endtask

    // =========================================================================
    // Executa um acesso e mede deltas de contador
    // =========================================================================
    task do_access;
        input [31:0] a;
        input [31:0] p;
        input access_is_reuse;
        input access_is_stream;

        begin
            l1h_before = l1_hit_count;
            l1m_before = l1_miss_count;
            l2h_before = l2_hit_count;
            l2m_before = l2_miss_count;

            @(posedge clk);
            req_addr  <= a;
            req_pc    <= p;
            req_valid <= 1'b1;

            @(posedge clk);
            req_valid <= 1'b0;

            timeout_counter = 0;

            while ((done !== 1'b1) && (timeout_counter < 1000)) begin
                @(posedge clk);
                timeout_counter = timeout_counter + 1;
            end

            if (done !== 1'b1) begin
                $display("[ERRO] TIMEOUT acesso=%0d addr=0x%08h pc=0x%08h state=%0d busy=%0d",
                         i, a, p, state_debug, busy);
                errors = errors + 1;
            end
            else begin
                #1;

                dl1h = l1_hit_count  - l1h_before;
                dl1m = l1_miss_count - l1m_before;
                dl2h = l2_hit_count  - l2h_before;
                dl2m = l2_miss_count - l2m_before;

                if (access_is_reuse) begin
                    reuse_accesses  = reuse_accesses + 1;
                    reuse_l1_hits   = reuse_l1_hits   + dl1h;
                    reuse_l1_misses = reuse_l1_misses + dl1m;
                    reuse_l2_hits   = reuse_l2_hits   + dl2h;
                    reuse_l2_misses = reuse_l2_misses + dl2m;
                end

                if (access_is_stream) begin
                    stream_accesses  = stream_accesses + 1;
                    stream_l1_hits   = stream_l1_hits   + dl1h;
                    stream_l1_misses = stream_l1_misses + dl1m;
                    stream_l2_hits   = stream_l2_hits   + dl2h;
                    stream_l2_misses = stream_l2_misses + dl2m;
                end
            end

            @(posedge clk);
        end
    endtask

    // =========================================================================
    // Teste principal
    // =========================================================================
    initial begin
        errors = 0;

        rst       = 1'b1;
        req_valid = 1'b0;
        req_addr  = 32'd0;
        req_pc    = 32'd0;

        reuse_idx  = 0;
        stream_idx = 0;

        reuse_accesses = 0;
        stream_accesses = 0;

        reuse_l1_hits = 0;
        reuse_l1_misses = 0;
        reuse_l2_hits = 0;
        reuse_l2_misses = 0;

        stream_l1_hits = 0;
        stream_l1_misses = 0;
        stream_l2_hits = 0;
        stream_l2_misses = 0;

        $display("=========================================================");
        $display(" TESTE HAWKEYE: REUSO FORTE vs STREAMING SEM REUSO");
        $display(" TOTAL_ACCESSES=%0d", TOTAL_ACCESSES);
        $display(" REPORT_EVERY=%0d", REPORT_EVERY);
        $display("=========================================================");

        repeat (10) @(posedge clk);
        rst <= 1'b0;

        // Espera inicializacao interna da L2 em RAM.
        repeat (100) @(posedge clk);

        for (i = 0; i < TOTAL_ACCESSES; i = i + 1) begin
            choose_pattern(i, addr, pc, is_reuse_access, is_stream_access);
            do_access(addr, pc, is_reuse_access, is_stream_access);

            if (((i + 1) % REPORT_EVERY) == 0) begin
                reuse_l2_total  = reuse_l2_hits  + reuse_l2_misses;
                stream_l2_total = stream_l2_hits + stream_l2_misses;

                if (reuse_l2_total > 0)
                    reuse_l2_hit_rate = (reuse_l2_hits * 100) / reuse_l2_total;
                else
                    reuse_l2_hit_rate = 0;

                if (stream_l2_total > 0)
                    stream_l2_hit_rate = (stream_l2_hits * 100) / stream_l2_total;
                else
                    stream_l2_hit_rate = 0;

                $display("[PROGRESS] %0d/%0d", i + 1, TOTAL_ACCESSES);
                $display("  TOTAL  | L1 h/m=%0d/%0d | L2 h/m=%0d/%0d",
                         l1_hit_count, l1_miss_count,
                         l2_hit_count, l2_miss_count);
                $display("  REUSE  | access=%0d | L1 h/m=%0d/%0d | L2 h/m=%0d/%0d | L2 hitrate=%0d%%",
                         reuse_accesses,
                         reuse_l1_hits, reuse_l1_misses,
                         reuse_l2_hits, reuse_l2_misses,
                         reuse_l2_hit_rate);
                $display("  STREAM | access=%0d | L1 h/m=%0d/%0d | L2 h/m=%0d/%0d | L2 hitrate=%0d%%",
                         stream_accesses,
                         stream_l1_hits, stream_l1_misses,
                         stream_l2_hits, stream_l2_misses,
                         stream_l2_hit_rate);
            end
        end

        reuse_l2_total  = reuse_l2_hits  + reuse_l2_misses;
        stream_l2_total = stream_l2_hits + stream_l2_misses;

        if (reuse_l2_total > 0)
            reuse_l2_hit_rate = (reuse_l2_hits * 100) / reuse_l2_total;
        else
            reuse_l2_hit_rate = 0;

        if (stream_l2_total > 0)
            stream_l2_hit_rate = (stream_l2_hits * 100) / stream_l2_total;
        else
            stream_l2_hit_rate = 0;

        $display("=========================================================");
        $display(" RESULTADO FINAL: REUSO FORTE vs STREAMING");
        $display(" CPU acessos = %0d", TOTAL_ACCESSES);
        $display("");
        $display(" TOTAL:");
        $display("   L1: hits=%0d misses=%0d soma=%0d",
                 l1_hit_count, l1_miss_count,
                 l1_hit_count + l1_miss_count);
        $display("   L2: hits=%0d misses=%0d soma=%0d",
                 l2_hit_count, l2_miss_count,
                 l2_hit_count + l2_miss_count);
        $display("");
        $display(" REUSE:");
        $display("   acessos=%0d", reuse_accesses);
        $display("   L1: hits=%0d misses=%0d soma=%0d",
                 reuse_l1_hits, reuse_l1_misses,
                 reuse_l1_hits + reuse_l1_misses);
        $display("   L2: hits=%0d misses=%0d soma=%0d hitrate=%0d%%",
                 reuse_l2_hits, reuse_l2_misses,
                 reuse_l2_total, reuse_l2_hit_rate);
        $display("");
        $display(" STREAM:");
        $display("   acessos=%0d", stream_accesses);
        $display("   L1: hits=%0d misses=%0d soma=%0d",
                 stream_l1_hits, stream_l1_misses,
                 stream_l1_hits + stream_l1_misses);
        $display("   L2: hits=%0d misses=%0d soma=%0d hitrate=%0d%%",
                 stream_l2_hits, stream_l2_misses,
                 stream_l2_total, stream_l2_hit_rate);
        $display("=========================================================");

        // Sanidade global
        if ((l1_hit_count + l1_miss_count) != TOTAL_ACCESSES) begin
            $display("[ERRO] L1 hits+misses diferente do total de acessos.");
            errors = errors + 1;
        end

        if ((l2_hit_count + l2_miss_count) != l1_miss_count) begin
            $display("[ERRO] L2 hits+misses diferente dos misses da L1.");
            errors = errors + 1;
        end

        // Sanidade por classe
        if ((reuse_l1_hits + reuse_l1_misses) != reuse_accesses) begin
            $display("[ERRO] REUSE L1 hits+misses diferente dos acessos REUSE.");
            errors = errors + 1;
        end

        if ((stream_l1_hits + stream_l1_misses) != stream_accesses) begin
            $display("[ERRO] STREAM L1 hits+misses diferente dos acessos STREAM.");
            errors = errors + 1;
        end

        if ((reuse_l2_hits + reuse_l2_misses) != reuse_l1_misses) begin
            $display("[ERRO] REUSE L2 total diferente dos misses L1 REUSE.");
            errors = errors + 1;
        end

        if ((stream_l2_hits + stream_l2_misses) != stream_l1_misses) begin
            $display("[ERRO] STREAM L2 total diferente dos misses L1 STREAM.");
            errors = errors + 1;
        end

        // Checagem esperada:
        // REUSE deve ter taxa de hit L2 maior que um minimo.
        if (reuse_l2_hit_rate < MIN_REUSE_L2_HIT_RATE_PERCENT) begin
            $display("[ERRO] REUSE L2 hitrate baixo: %0d%% minimo=%0d%%",
                     reuse_l2_hit_rate, MIN_REUSE_L2_HIT_RATE_PERCENT);
            errors = errors + 1;
        end

        // STREAM nao deve repetir bloco, entao hits na L2 devem ser zero ou poucos.
        if (stream_l2_hits > MAX_STREAM_L2_HITS_ALLOWED) begin
            $display("[ERRO] STREAM teve L2 hits inesperados: %0d permitido=%0d",
                     stream_l2_hits, MAX_STREAM_L2_HITS_ALLOWED);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("[OK] Teste REUSE vs STREAM passou.");
        end
        else begin
            $display("[FALHOU] Teste REUSE vs STREAM terminou com %0d erro(s).", errors);
        end

        $finish;
    end

endmodule   