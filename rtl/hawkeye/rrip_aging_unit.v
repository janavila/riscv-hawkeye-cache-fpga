module rrip_aging_unit #(
    parameter NUM_WAYS  = 2,
    parameter RRPV_BITS = 3
)(
    input  wire [NUM_WAYS-1:0]             valid_entries,
    input  wire [NUM_WAYS*RRPV_BITS-1:0]   rrpv_entries_flat,
    input  wire                            aging_enable,

    output reg  [NUM_WAYS*RRPV_BITS-1:0]   new_rrpv_entries_flat,
    output reg  [NUM_WAYS-1:0]             write_mask
);

    localparam [RRPV_BITS-1:0] RRPV_MAX = {RRPV_BITS{1'b1}};

    integer i;

    reg [RRPV_BITS-1:0] rrpv_i;
    reg [RRPV_BITS-1:0] rrpv_new_i;

    always @(*) begin
        new_rrpv_entries_flat = rrpv_entries_flat;
        write_mask = {NUM_WAYS{1'b0}};

        if (aging_enable) begin
            for (i = 0; i < NUM_WAYS; i = i + 1) begin
                rrpv_i = rrpv_entries_flat[i*RRPV_BITS +: RRPV_BITS];

                if (valid_entries[i]) begin
                    write_mask[i] = 1'b1;

                    if (rrpv_i == RRPV_MAX)
                        rrpv_new_i = RRPV_MAX;
                    else
                        rrpv_new_i = rrpv_i + 1'b1;

                    new_rrpv_entries_flat[i*RRPV_BITS +: RRPV_BITS] = rrpv_new_i;
                end
                else begin
                    /*
                        Via inválida não precisa ser envelhecida.
                        Mantemos o valor original.
                    */
                    write_mask[i] = 1'b0;
                    new_rrpv_entries_flat[i*RRPV_BITS +: RRPV_BITS] = rrpv_i;
                end
            end
        end
    end

endmodule   