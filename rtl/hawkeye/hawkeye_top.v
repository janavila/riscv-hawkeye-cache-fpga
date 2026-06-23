module hawkeye_top #(
    parameter PC_BITS        = 64,
    parameter BLOCK_BITS     = 64,

    parameter SAMPLER_SETS   = 64,
    parameter SAMPLER_HIST   = 8,
    parameter SET_BITS       = 6,
    parameter POS_BITS       = 3,
    parameter SIGNATURE_BITS = 8,
    parameter TIME_BITS      = 32,
    parameter LRU_BITS       = 4,

    parameter OPTGEN_SIZE      = 128,
    parameter OPTGEN_INDEX_BITS = 7,
    parameter LIVENESS_BITS     = 8,
    parameter CACHE_SIZE_BITS   = 8,

    parameter PREDICTOR_ENTRIES = 2048,
    parameter PREDICTOR_INDEX_BITS = 11,
    parameter COUNTER_BITS = 5
)(
    input  wire                         clk,
    input  wire                         reset,

    /*
        Entrada vinda da cache.
    */
    input  wire                         access_valid,
    input  wire [PC_BITS-1:0]           pc,
    input  wire [BLOCK_BITS-1:0]        block_addr,
    input  wire [SET_BITS-1:0]          set_index,
    input  wire                         access_miss,

    /*
        Tamanho efetivo usado pelo OPTgen.
        Para comeÃƒÂ§ar, pode ser a associatividade.
        Exemplo: cache_size = 2, 4 ou 8.
    */
    input  wire [CACHE_SIZE_BITS-1:0]   optgen_cache_size,

    /*
        SaÃƒÂ­das para RRIP/cache.
    */
    output wire                         prediction_valid,
    output wire                         friendly,
    output wire                         averse,

    /*
        Status do treinamento.
    */
    output wire                         training_busy,
    output wire                         training_done,

    /*
        Debug para ModelSim.
    */
    output wire [SIGNATURE_BITS-1:0]    signature_debug,
    output wire [SET_BITS-1:0]          sample_set_debug,
    output wire [TIME_BITS-1:0]         current_time_debug,
    output wire [OPTGEN_INDEX_BITS-1:0] current_val_debug,
    output wire [OPTGEN_INDEX_BITS-1:0] prev_val_debug,
    output wire                         sampler_hit_debug,
    output wire [POS_BITS-1:0]          sampler_pos_debug,
    output wire [3:0]                   controller_state_debug
);

    /*
        ============================================================
        1. Hash do bloco para gerar assinatura do sampler
        ============================================================
    */

    wire [63:0] block_hash;
    wire [PREDICTOR_INDEX_BITS-1:0] unused_predictor_index_from_block;
    wire [SIGNATURE_BITS-1:0] signature;

    hawkeye_hash_index hash_block (
        .value_in(block_addr),
        .hash_out(block_hash),
        .predictor_index(unused_predictor_index_from_block),
        .signature(signature)
    );

    assign signature_debug = signature;

    /*
        ============================================================
        2. Sample set
        ============================================================

        Como SAMPLER_SETS = 64, usamos set_index diretamente.
    */

    wire [SET_BITS-1:0] sample_set;

    assign sample_set = set_index;

    assign sample_set_debug = sample_set;

    /*
        ============================================================
        3. Timer por sampled set
        ============================================================

        Equivalente ao set_timer[set] do C.
    */

    reg [TIME_BITS-1:0] set_timer [0:SAMPLER_SETS-1];

    wire [TIME_BITS-1:0] current_time;
    wire [OPTGEN_INDEX_BITS-1:0] current_val;

    assign current_time = set_timer[sample_set];

    /*
        OPTGEN_SIZE = 128 = 2^7.
        EntÃƒÂ£o current_val = current_time % 128
        vira current_time[6:0].
    */
    assign current_val = current_time[OPTGEN_INDEX_BITS-1:0];

    assign current_time_debug = current_time;
    assign current_val_debug  = current_val;

    /*
        ============================================================
        4. Sampler
        ============================================================
    */

    wire sampler_hit;
    wire sampler_miss;
    wire [POS_BITS-1:0] sampler_pos;
    wire [POS_BITS-1:0] pos_write;
    wire [PC_BITS-1:0] pc_anterior;
    wire [TIME_BITS-1:0] previous_time;

    wire [SAMPLER_HIST-1:0] match_vector_debug;
    wire [SAMPLER_HIST-1:0] valid_entries_debug;

    wire sampler_update_enable;

    sampler #(
        .SAMPLER_SETS(SAMPLER_SETS),
        .SAMPLER_HIST(SAMPLER_HIST),
        .SET_BITS(SET_BITS),
        .POS_BITS(POS_BITS),
        .SIGNATURE_BITS(SIGNATURE_BITS),
        .PC_BITS(PC_BITS),
        .TIME_BITS(TIME_BITS),
        .LRU_BITS(LRU_BITS)
    ) sampler_inst (
        .clk(clk),
        .reset(reset),

        .access_valid(access_valid),
        .update_enable(sampler_update_enable),

        .sample_set(sample_set),
        .signature_atual(signature),
        .pc_atual(pc),
        .current_time(current_time),

        .sampler_hit(sampler_hit),
        .sampler_miss(sampler_miss),
        .sampler_pos(sampler_pos),
        .pos_write(pos_write),
        .pc_anterior(pc_anterior),
        .previous_time(previous_time),

        .match_vector_debug(match_vector_debug),
        .valid_entries_debug(valid_entries_debug)
    );

    assign sampler_hit_debug = sampler_hit;
    assign sampler_pos_debug = sampler_pos;

    /*
        previous_time % OPTGEN_SIZE
        Como OPTGEN_SIZE = 128, usamos os 7 bits baixos.
    */

    wire [OPTGEN_INDEX_BITS-1:0] prev_val;

    assign prev_val = previous_time[OPTGEN_INDEX_BITS-1:0];

    assign prev_val_debug = prev_val;

    /*
        ============================================================
        5. OPTgen
        ============================================================
    */

    wire optgen_start_check;
    wire optgen_start_set_access;
    wire optgen_busy;
    wire optgen_done;
    wire optgen_should_cache;

    wire [31:0] optgen_num_cache_debug;
    wire [31:0] optgen_access_debug;
    wire [OPTGEN_INDEX_BITS-1:0] optgen_count_debug;
    wire [2:0] optgen_state_debug;

    optgen #(
        .OPTGEN_SIZE(OPTGEN_SIZE),
        .INDEX_BITS(OPTGEN_INDEX_BITS),
        .LIVENESS_BITS(LIVENESS_BITS),
        .CACHE_SIZE_BITS(CACHE_SIZE_BITS),
        .NUM_CACHE_BITS(32),
        .ACCESS_BITS(32)
    ) optgen_inst (
        .clk(clk),
        .reset(reset),

        .start_check(optgen_start_check),
        .start_set_access(optgen_start_set_access),

        .current_val(current_val),
        .end_val(prev_val),
        .cache_size(optgen_cache_size),

        .busy(optgen_busy),
        .done(optgen_done),
        .should_cache(optgen_should_cache),

        .num_cache_debug(optgen_num_cache_debug),
        .access_debug(optgen_access_debug),
        .count_debug(optgen_count_debug),
        .state_debug(optgen_state_debug)
    );

    /*
        ============================================================
        6. Predictor Hawkeye
        ============================================================
    */

    wire predictor_train_enable;
    wire predictor_train_up;
    wire predictor_train_down;
    wire [PC_BITS-1:0] pc_train;

    wire [COUNTER_BITS-1:0] counter_predict_debug;
    wire [PREDICTOR_INDEX_BITS-1:0] index_predict_debug;

    hawkeye_predictor #(
        .PREDICTOR_ENTRIES(PREDICTOR_ENTRIES),
        .INDEX_BITS(PREDICTOR_INDEX_BITS),
        .COUNTER_BITS(COUNTER_BITS)
    ) predictor_inst (
        .clk(clk),
        .reset(reset),

        .predict_enable(access_valid),
        .pc_predict(pc),

        .train_enable(predictor_train_enable),
        .pc_train(pc_train),
        .train_up(predictor_train_up),
        .train_down(predictor_train_down),

        .prediction_valid(prediction_valid),
        .friendly(friendly),
        .averse(averse),

        .counter_predict_debug(counter_predict_debug),
        .index_predict_debug(index_predict_debug)
    );

    /*
        ============================================================
        7. Training Controller
        ============================================================
    */

    hawkeye_training_controller #(
        .PC_BITS(PC_BITS)
    ) controller_inst (
        .clk(clk),
        .reset(reset),

        .access_valid(access_valid),
        .access_miss(access_miss),

        .sampler_hit(sampler_hit),
        .pc_anterior(pc_anterior),

        .optgen_done(optgen_done),
        .optgen_should_cache(optgen_should_cache),

        .optgen_start_check(optgen_start_check),
        .optgen_start_set_access(optgen_start_set_access),

        .predictor_train_enable(predictor_train_enable),
        .predictor_train_up(predictor_train_up),
        .predictor_train_down(predictor_train_down),
        .pc_train(pc_train),

        .sampler_update_enable(sampler_update_enable),

        .busy(training_busy),
        .done(training_done),
        .state_debug(controller_state_debug)
    );

    /*
        ============================================================
        8. Incremento do set_timer
        ============================================================

        No C, ao fim do update_on_access, ocorre:
            cache->set_timer[req->set]++;

        Aqui fazemos isso quando o treinamento daquele acesso termina.
    */

    integer t;

    always @(posedge clk) begin
        if (reset) begin
            for (t = 0; t < SAMPLER_SETS; t = t + 1) begin
                set_timer[t] <= {TIME_BITS{1'b0}};
            end
        end
        else begin
            if (training_done) begin
                set_timer[sample_set] <= set_timer[sample_set] + 1'b1;
            end
        end
    end
	 
endmodule