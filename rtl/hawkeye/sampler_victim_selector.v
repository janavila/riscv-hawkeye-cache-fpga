module sampler_victim_selector #(
    parameter SAMPLER_HIST = 8,
    parameter LRU_BITS     = 4,
    parameter POS_BITS     = 3
)(
    input  wire [SAMPLER_HIST-1:0]          valid_entries,
    input  wire [SAMPLER_HIST*LRU_BITS-1:0] lru_entries_flat,

    output reg  [POS_BITS-1:0]              victim_pos,
    output wire                             has_invalid,
    output wire [SAMPLER_HIST-1:0]          invalid_vector
);

    integer i;

    reg [POS_BITS-1:0] invalid_pos;
    reg [POS_BITS-1:0] lru_victim_pos;

    reg [LRU_BITS-1:0] maior_lru;
    reg [LRU_BITS-1:0] lru_i;

    assign invalid_vector = ~valid_entries;
    assign has_invalid = |invalid_vector;

    always @(*) begin
        invalid_pos = {POS_BITS{1'b0}};

        if (invalid_vector[0])
            invalid_pos = 3'd0;
        else if (invalid_vector[1])
            invalid_pos = 3'd1;
        else if (invalid_vector[2])
            invalid_pos = 3'd2;
        else if (invalid_vector[3])
            invalid_pos = 3'd3;
        else if (invalid_vector[4])
            invalid_pos = 3'd4;
        else if (invalid_vector[5])
            invalid_pos = 3'd5;
        else if (invalid_vector[6])
            invalid_pos = 3'd6;
        else if (invalid_vector[7])
            invalid_pos = 3'd7;
    end

    always @(*) begin
        maior_lru = lru_entries_flat[0 +: LRU_BITS];
        lru_victim_pos = {POS_BITS{1'b0}};

        for (i = 1; i < SAMPLER_HIST; i = i + 1) begin
            lru_i = lru_entries_flat[i*LRU_BITS +: LRU_BITS];

            if (lru_i > maior_lru) begin
                maior_lru = lru_i;
                lru_victim_pos = i;
            end
        end
    end

    always @(*) begin
        if (has_invalid)
            victim_pos = invalid_pos;
        else
            victim_pos = lru_victim_pos;
    end

endmodule   