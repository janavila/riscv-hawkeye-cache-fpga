module hawkeye_hash_index (
    input  wire [63:0] value_in,

    output wire [63:0] hash_out,
    output wire [10:0] predictor_index,
    output wire [7:0]  signature
);

    localparam [63:0] CRC_POLYNOMIAL = 64'd3988292384;

    integer i;
    reg [63:0] result;

    always @(*) begin
        result = value_in;

        for (i = 0; i < 32; i = i + 1) begin
            if (result[0])
                result = (result >> 1) ^ CRC_POLYNOMIAL;
            else
                result = result >> 1;
        end
    end

    assign hash_out = result;

    // Como 2048 = 2^11, usamos 11 bits
    assign predictor_index = result[10:0];

    // Como 256 = 2^8, usamos 8 bits
    assign signature = result[7:0];

endmodule