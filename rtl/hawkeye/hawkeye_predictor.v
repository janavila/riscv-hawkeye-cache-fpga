module hawkeye_predictor #(
    parameter PREDICTOR_ENTRIES = 2048,
    parameter INDEX_BITS        = 11,
    parameter COUNTER_BITS      = 5
)(
    input  wire                       clk,
    input  wire                       reset,

    input  wire                       predict_enable,
    input  wire [63:0]                pc_predict,

    input  wire                       train_enable,
    input  wire [63:0]                pc_train,
    input  wire                       train_up,
    input  wire                       train_down,

    output wire                       prediction_valid,
    output wire                       friendly,
    output wire                       averse,

    output wire [COUNTER_BITS-1:0]    counter_predict_debug,
    output wire [INDEX_BITS-1:0]      index_predict_debug
);

    localparam [COUNTER_BITS-1:0] INIT_VALUE = (1 << (COUNTER_BITS - 1));
    localparam [COUNTER_BITS-1:0] THRESHOLD  = (1 << (COUNTER_BITS - 1));

    wire [INDEX_BITS-1:0] index_predict;
    wire [INDEX_BITS-1:0] index_train;

    wire [COUNTER_BITS-1:0] counter_predict;
    wire [COUNTER_BITS-1:0] counter_train;
    wire [COUNTER_BITS-1:0] counter_next;

    reg [COUNTER_BITS-1:0] predictor_table [0:PREDICTOR_ENTRIES-1];

    integer i;

    hawkeye_hash_index hash_predict (
        .value_in(pc_predict),
        .hash_out(),
        .predictor_index(index_predict),
        .signature()
    );

    hawkeye_hash_index hash_train (
        .value_in(pc_train),
        .hash_out(),
        .predictor_index(index_train),
        .signature()
    );

    assign counter_predict = predictor_table[index_predict];
    assign counter_train   = predictor_table[index_train];

    saturating_counter_unit #(
        .COUNTER_BITS(COUNTER_BITS)
    ) counter_update (
        .counter_current(counter_train),
        .train_up(train_up),
        .train_down(train_down),
        .aging_enable(1'b0),
        .counter_next(counter_next)
    );

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < PREDICTOR_ENTRIES; i = i + 1) begin
                predictor_table[i] <= INIT_VALUE;
            end
        end
        else begin
            if (train_enable) begin
                predictor_table[index_train] <= counter_next;
            end
        end
    end

    assign prediction_valid = predict_enable;

    assign friendly = predict_enable && (counter_predict >= THRESHOLD);
    assign averse   = predict_enable && (counter_predict <  THRESHOLD);

    assign counter_predict_debug = counter_predict;
    assign index_predict_debug   = index_predict;

endmodule   