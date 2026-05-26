module saturating_counter_unit #(
    parameter COUNTER_BITS = 5
)(
    input  wire [COUNTER_BITS-1:0] counter_current,
    input  wire                    train_up,
    input  wire                    train_down,
    input  wire                    aging_enable,
    output reg  [COUNTER_BITS-1:0] counter_next
);

    localparam [COUNTER_BITS-1:0] MAX_VALUE  = {COUNTER_BITS{1'b1}};
    localparam [COUNTER_BITS-1:0] ZERO_VALUE = {COUNTER_BITS{1'b0}};

    always @(*) begin
        if (aging_enable) begin
            counter_next = counter_current >> 1;
        end
        else if (train_up) begin
            if (counter_current == MAX_VALUE)
                counter_next = MAX_VALUE;
            else
                counter_next = counter_current + 1'b1;
        end
        else if (train_down) begin
            if (counter_current == ZERO_VALUE)
                counter_next = ZERO_VALUE;
            else
                counter_next = counter_current - 1'b1;
        end
        else begin
            counter_next = counter_current;
        end
    end

endmodule
