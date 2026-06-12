// =============================================================================
// cache_hierarchy_top.v
// -----------------------------------------------------------------------------
// Top sintetizavel da hierarquia:
//   Entrada externa -> L1
//   L1 miss -> L2
//   L2 done -> fill controlado na L1
//
// Este modulo NAO e testbench.
// Nao possui initial, task, $display, $finish ou dumpvars.
// =============================================================================

`timescale 1ns/1ps

module cache_hierarchy_top (
    input  wire        clk,
    input  wire        rst,

    // Requisicao externa
    input  wire        req_valid,
    input  wire [31:0] req_addr,
    input  wire [31:0] req_pc,

    // Resposta da hierarquia
    output reg         done,
    output reg         busy,

    // Resultado do acesso
    output reg         resp_l1_hit,
    output reg         resp_l1_miss,
    output reg         resp_l2_access,
    output reg         resp_l2_hit,
    output reg         resp_l2_miss,

    // Contadores para debug/sintese
    output wire [31:0] l1_hit_count,
    output wire [31:0] l1_miss_count,
    output wire [31:0] l2_hit_count,
    output wire [31:0] l2_miss_count,

    // Debug simples de estado
    output reg  [2:0]  state_debug
);

    // =========================================================================
    // Estados da FSM da hierarquia
    // =========================================================================
    localparam [2:0] S_IDLE      = 3'd0;
    localparam [2:0] S_L1_LOOKUP = 3'd1;
    localparam [2:0] S_L2_REQ    = 3'd2;
    localparam [2:0] S_L2_WAIT   = 3'd3;
    localparam [2:0] S_L1_FILL   = 3'd4;
    localparam [2:0] S_DONE      = 3'd5;

    reg [2:0] state;

    // Guarda o acesso atual
    reg [31:0] addr_reg;
    reg [31:0] pc_reg;

    // =========================================================================
    // Sinais da L1
    // =========================================================================
    reg         l1_req_valid;
    reg  [31:0] l1_req_addr;

    reg         l1_fill_valid;
    reg  [31:0] l1_fill_addr;

    wire        l1_hit;
    wire        l1_miss;

    // =========================================================================
    // Sinais da L2
    // =========================================================================
    reg         l2_req_valid;
    reg  [31:0] l2_req_addr;
    reg  [31:0] l2_req_pc;

    wire        l2_done;
    wire        l2_hit;
    wire        l2_miss;

    // =========================================================================
    // Interface L2 <-> Politica Hawkeye
    // =========================================================================
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

    // =========================================================================
    // Instancia da L1
    // -------------------------------------------------------------------------
    // AUTO_FILL_ON_MISS=0:
    // A L1 NAO se preenche sozinha.
    // Ela so instala o bloco quando este top levanta l1_fill_valid.
    // =========================================================================
    cache_l1 #(
        .AUTO_FILL_ON_MISS(0)
    ) u_l1 (
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

    // =========================================================================
    // Instancia da L2
    // =========================================================================
    cache_l2 u_l2 (
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

    // =========================================================================
    // Politica Hawkeye da L2
    // =========================================================================
    hawkeye_l2_policy u_policy (
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

    // =========================================================================
    // FSM da hierarquia
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;

            addr_reg <= 32'd0;
            pc_reg   <= 32'd0;

            l1_req_valid  <= 1'b0;
            l1_req_addr   <= 32'd0;
            l1_fill_valid <= 1'b0;
            l1_fill_addr  <= 32'd0;

            l2_req_valid  <= 1'b0;
            l2_req_addr   <= 32'd0;
            l2_req_pc     <= 32'd0;

            done          <= 1'b0;
            busy          <= 1'b0;
            resp_l1_hit   <= 1'b0;
            resp_l1_miss  <= 1'b0;
            resp_l2_access <= 1'b0;
            resp_l2_hit   <= 1'b0;
            resp_l2_miss  <= 1'b0;

            state_debug   <= S_IDLE;
        end
        else begin
            // Pulsos default
            done          <= 1'b0;
            l1_req_valid  <= 1'b0;
            l1_fill_valid <= 1'b0;
            l2_req_valid  <= 1'b0;

            state_debug <= state;

            case (state)

                // -------------------------------------------------------------
                // Aguarda novo acesso externo
                // -------------------------------------------------------------
                S_IDLE: begin
                    busy <= 1'b0;

                    resp_l1_hit    <= 1'b0;
                    resp_l1_miss   <= 1'b0;
                    resp_l2_access <= 1'b0;
                    resp_l2_hit    <= 1'b0;
                    resp_l2_miss   <= 1'b0;

                    if (req_valid) begin
                        addr_reg <= req_addr;
                        pc_reg   <= req_pc;

                        l1_req_valid <= 1'b1;
                        l1_req_addr  <= req_addr;

                        busy  <= 1'b1;
                        state <= S_L1_LOOKUP;
                    end
                end

                // -------------------------------------------------------------
                // L1 foi acionada no ciclo anterior.
                // Aqui lemos o resultado combinacional da L1.
                // -------------------------------------------------------------
                S_L1_LOOKUP: begin
                    if (l1_hit) begin
                        resp_l1_hit    <= 1'b1;
                        resp_l1_miss   <= 1'b0;
                        resp_l2_access <= 1'b0;
                        resp_l2_hit    <= 1'b0;
                        resp_l2_miss   <= 1'b0;

                        state <= S_DONE;
                    end
                    else begin
                        resp_l1_hit    <= 1'b0;
                        resp_l1_miss   <= 1'b1;
                        resp_l2_access <= 1'b1;

                        // Aciona L2 por 1 ciclo
                        l2_req_valid <= 1'b1;
                        l2_req_addr  <= addr_reg;
                        l2_req_pc    <= pc_reg;

                        state <= S_L2_REQ;
                    end
                end

                // -------------------------------------------------------------
                // Remove pulso de req_valid da L2 e passa a esperar done
                // -------------------------------------------------------------
                S_L2_REQ: begin
                    state <= S_L2_WAIT;
                end

                // -------------------------------------------------------------
                // Aguarda L2 terminar.
                // Quando a L2 termina, fazemos fill controlado na L1.
                // -------------------------------------------------------------
                S_L2_WAIT: begin
                    if (l2_done) begin
                        resp_l2_hit  <= l2_hit;
                        resp_l2_miss <= l2_miss;

                        // Fill controlado da L1 com o bloco solicitado
                        l1_fill_valid <= 1'b1;
                        l1_fill_addr  <= addr_reg;

                        state <= S_L1_FILL;
                    end
                end

                // -------------------------------------------------------------
                // O fill_valid ficou alto durante este ciclo.
                // Na borda seguinte, a L1 instala o bloco.
                // -------------------------------------------------------------
                S_L1_FILL: begin
                    state <= S_DONE;
                end

                // -------------------------------------------------------------
                // Finaliza transacao.
                // done fica alto por 1 ciclo.
                // -------------------------------------------------------------
                S_DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule
// =============================================================================
// fim do cache_hierarchy_top.v
// =============================================================================