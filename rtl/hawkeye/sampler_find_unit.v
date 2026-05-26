module sampler_find_unit #(
    parameter SAMPLER_HIST   = 8,
    parameter SIGNATURE_BITS = 8,
    parameter POS_BITS       = 3
)(
    input  wire [SIGNATURE_BITS-1:0]              signature_atual,
    input  wire [SAMPLER_HIST-1:0]                valid_entries,
    input  wire [SAMPLER_HIST*SIGNATURE_BITS-1:0] signature_entries_flat,

    output wire                                   sampler_hit,
    output reg  [POS_BITS-1:0]                    sampler_pos,
    output wire [SAMPLER_HIST-1:0]                match_vector
);

    genvar g;

    generate
        for (g = 0; g < SAMPLER_HIST; g = g + 1) begin : GEN_MATCH
            assign match_vector[g] =
                valid_entries[g] &&
                (signature_entries_flat[g*SIGNATURE_BITS +: SIGNATURE_BITS] == signature_atual);
        end
    endgenerate

    assign sampler_hit = |match_vector;

    always @(*) begin
        sampler_pos = {POS_BITS{1'b0}};

        if (match_vector[0])
            sampler_pos = 3'd0;
        else if (match_vector[1])
            sampler_pos = 3'd1;
        else if (match_vector[2])
            sampler_pos = 3'd2;
        else if (match_vector[3])
            sampler_pos = 3'd3;
        else if (match_vector[4])
            sampler_pos = 3'd4;
        else if (match_vector[5])
            sampler_pos = 3'd5;
        else if (match_vector[6])
            sampler_pos = 3'd6;
        else if (match_vector[7])
            sampler_pos = 3'd7;
    end

endmodule   