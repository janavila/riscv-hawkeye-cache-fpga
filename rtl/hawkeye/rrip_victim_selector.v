module rrip_victim_selector #(
    parameter NUM_WAYS  = 2,
    parameter WAY_BITS  = 1,
    parameter RRPV_BITS = 3
)(
    input  wire [NUM_WAYS-1:0]             valid_entries,
    input  wire [NUM_WAYS*RRPV_BITS-1:0]   rrpv_entries_flat,

    output reg  [WAY_BITS-1:0]             victim_way,
    output reg                             victim_found,
    output reg                             need_aging,
    output wire [NUM_WAYS-1:0]             invalid_vector,
    output wire [NUM_WAYS-1:0]             candidate_vector
);

    localparam [RRPV_BITS-1:0] RRPV_MAX = {RRPV_BITS{1'b1}};

    integer i;

    reg [RRPV_BITS-1:0] rrpv_i;

    assign invalid_vector = ~valid_entries;

    genvar g;

    generate
        for (g = 0; g < NUM_WAYS; g = g + 1) begin : GEN_CANDIDATE
            assign candidate_vector[g] =
                valid_entries[g] &&
                (rrpv_entries_flat[g*RRPV_BITS +: RRPV_BITS] == RRPV_MAX);
        end
    endgenerate

    always @(*) begin
        victim_way   = {WAY_BITS{1'b0}};
        victim_found = 1'b0;
        need_aging   = 1'b0;

        /*
            Prioridade 1:
            escolher a primeira via inválida.
        */
        for (i = 0; i < NUM_WAYS; i = i + 1) begin
            if (!victim_found && invalid_vector[i]) begin
                victim_way   = i;
                victim_found = 1'b1;
                need_aging   = 1'b0;
            end
        end

        /*
            Prioridade 2:
            se todas são válidas, escolher a primeira via com RRPV_MAX.
        */
        if (!victim_found) begin
            for (i = 0; i < NUM_WAYS; i = i + 1) begin
                rrpv_i = rrpv_entries_flat[i*RRPV_BITS +: RRPV_BITS];

                if (!victim_found && valid_entries[i] && (rrpv_i == RRPV_MAX)) begin
                    victim_way   = i;
                    victim_found = 1'b1;
                    need_aging   = 1'b0;
                end
            end
        end

        /*
            Prioridade 3:
            se não há inválida e ninguém tem RRPV_MAX,
            precisa envelhecer os RRPVs.
        */
        if (!victim_found) begin
            need_aging = 1'b1;
        end
    end

endmodule   