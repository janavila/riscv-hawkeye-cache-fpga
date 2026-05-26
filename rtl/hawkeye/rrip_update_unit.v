module rrip_update_unit #(
    parameter RRPV_BITS = 3
)(
    input  wire [RRPV_BITS-1:0] current_rrpv,

    input  wire                 update_enable,
    input  wire                 hit,
    input  wire                 insert,

    input  wire                 friendly,

    output reg  [RRPV_BITS-1:0] new_rrpv,
    output reg                  write_rrpv
);

    localparam [RRPV_BITS-1:0] RRPV_MAX   = {RRPV_BITS{1'b1}};
    localparam [RRPV_BITS-1:0] RRPV_ZERO  = {RRPV_BITS{1'b0}};

    always @(*) begin
        new_rrpv   = current_rrpv;
        write_rrpv = 1'b0;

        if (update_enable) begin

            /*
                Caso 1: hit na linha.
                Se for friendly, protege totalmente.
                Se for averse, reduz um pouco o RRPV se possível.
            */
            if (hit) begin
                write_rrpv = 1'b1;

                if (friendly) begin
                    new_rrpv = RRPV_ZERO;
                end
                else begin
                    if (current_rrpv > RRPV_ZERO)
                        new_rrpv = current_rrpv - 1'b1;
                    else
                        new_rrpv = RRPV_ZERO;
                end
            end

            /*
                Caso 2: inserção de novo bloco.
                Friendly entra protegido.
                Averse entra como candidato forte à remoção.
            */
            else if (insert) begin
                write_rrpv = 1'b1;

                if (friendly)
                    new_rrpv = RRPV_ZERO;
                else
                    new_rrpv = RRPV_MAX;
            end
        end
    end

endmodule   