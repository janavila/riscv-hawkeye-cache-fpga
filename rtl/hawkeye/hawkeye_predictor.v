//module hawkeye_predictor #(
//    parameter PREDICTOR_ENTRIES = 2048,
//    parameter INDEX_BITS        = 11,
//    parameter COUNTER_BITS      = 5
//)(
//    input  wire                       clk,
//    input  wire                       reset,
//
//    input  wire                       predict_enable,
//    input  wire [63:0]                pc_predict,
//
//    input  wire                       train_enable,
//    input  wire [63:0]                pc_train,
//    input  wire                       train_up,
//    input  wire                       train_down,
//
//    output wire                       prediction_valid,
//    output wire                       friendly,
//    output wire                       averse,
//
//    output wire [COUNTER_BITS-1:0]    counter_predict_debug,
//    output wire [INDEX_BITS-1:0]      index_predict_debug
//);
//
//    localparam [COUNTER_BITS-1:0] INIT_VALUE = (1 << (COUNTER_BITS - 1));
//    localparam [COUNTER_BITS-1:0] THRESHOLD  = (1 << (COUNTER_BITS - 1));
//
//    wire [INDEX_BITS-1:0] index_predict;
//    wire [INDEX_BITS-1:0] index_train;
//
//    wire [COUNTER_BITS-1:0] counter_predict;
//    wire [COUNTER_BITS-1:0] counter_train;
//    wire [COUNTER_BITS-1:0] counter_next;
//
//    reg [COUNTER_BITS-1:0] predictor_table [0:PREDICTOR_ENTRIES-1];
//
//    integer i;
//
//    hawkeye_hash_index hash_predict (
//        .value_in(pc_predict),
//        .hash_out(),
//        .predictor_index(index_predict),
//        .signature()
//    );
//
//    hawkeye_hash_index hash_train (
//        .value_in(pc_train),
//        .hash_out(),
//        .predictor_index(index_train),
//        .signature()
//    );
//
//    assign counter_predict = predictor_table[index_predict];
//    assign counter_train   = predictor_table[index_train];
//
//    saturating_counter_unit #(
//        .COUNTER_BITS(COUNTER_BITS)
//    ) counter_update (
//        .counter_current(counter_train),
//        .train_up(train_up),
//        .train_down(train_down),
//        .aging_enable(1'b0),
//        .counter_next(counter_next)
//    );
//
//    always @(posedge clk) begin
//        if (reset) begin
//            for (i = 0; i < PREDICTOR_ENTRIES; i = i + 1) begin
//                predictor_table[i] <= INIT_VALUE;
//            end
//        end
//        else begin
//            if (train_enable) begin
//                predictor_table[index_train] <= counter_next;
//            end
//        end
//    end
//
//    assign prediction_valid = predict_enable;
//
//    assign friendly = predict_enable && (counter_predict >= THRESHOLD);
//    assign averse   = predict_enable && (counter_predict <  THRESHOLD);
//
//    assign counter_predict_debug = counter_predict;
//    assign index_predict_debug   = index_predict;
//
//endmodule 


`timescale 1ns/1ps

// =============================================================================
// hawkeye_predictor.v
// -----------------------------------------------------------------------------
// Predictor Hawkeye com RAM espelhada para inferencia de memoria embarcada.
// ramstyle = "AUTO" deixa o Quartus escolher o melhor tipo disponivel no
// dispositivo alvo (M4K, M9K, M10K, M20K, MLAB, etc.).
// =============================================================================

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

    output reg                        prediction_valid,
    output reg                        friendly,
    output reg                        averse,

    output wire [COUNTER_BITS-1:0]    counter_predict_debug,
    output wire [INDEX_BITS-1:0]      index_predict_debug
);

    localparam [COUNTER_BITS-1:0] INIT_VALUE = (1 << (COUNTER_BITS - 1));
    localparam [COUNTER_BITS-1:0] THRESHOLD  = (1 << (COUNTER_BITS - 1));

    wire [INDEX_BITS-1:0] index_predict;
    wire [INDEX_BITS-1:0] index_train;

    // =========================================================================
    // DUAS COPIAS — Simple Dual-Port RAM
    // ramstyle = "AUTO": Quartus escolhe o bloco mais adequado ao dispositivo.
    // Para forcar um tipo especifico, use "M9K", "M10K", "M20K", "MLAB", etc.
    //
    // SEM reset de conteudo — essencial para inferir RAM embarcada.
    // Inicializacao via arquivo .mif se necessario (ver parametro ram_init_file).
    // =========================================================================
    (* ramstyle = "AUTO" *)
    reg [COUNTER_BITS-1:0] ram_predict [0:PREDICTOR_ENTRIES-1];

    (* ramstyle = "AUTO" *)
    reg [COUNTER_BITS-1:0] ram_train   [0:PREDICTOR_ENTRIES-1];

    // -------------------------------------------------------------------------
    // Inicialização SOMENTE para simulação.
    // Em hardware, não usamos reset de conteúdo para preservar inferência de RAM.
    // -------------------------------------------------------------------------
    `ifdef SIMULATION
    integer init_i;
    
    initial begin
        for (init_i = 0; init_i < PREDICTOR_ENTRIES; init_i = init_i + 1) begin
            ram_predict[init_i] = INIT_VALUE;
            ram_train  [init_i] = INIT_VALUE;
        end
    end
    `endif
    // -------------------------------------------------------------------------
    // Saidas registradas das RAMs
    // -------------------------------------------------------------------------
    reg [COUNTER_BITS-1:0] counter_predict_r;
    reg [COUNTER_BITS-1:0] counter_train_r;

    // -------------------------------------------------------------------------
    // Pipeline de controle (registradores normais — nao sao RAM)
    // -------------------------------------------------------------------------
    reg                    predict_enable_r;
    reg [INDEX_BITS-1:0]   index_predict_r;

    reg                    train_enable_r;
    reg                    train_up_r;
    reg                    train_down_r;
    reg [INDEX_BITS-1:0]   index_train_r;

    wire [COUNTER_BITS-1:0] counter_next;

    // =========================================================================
    // Hash de endereco
    // =========================================================================
    hawkeye_hash_index hash_predict (
        .value_in        (pc_predict),
        .hash_out        (),
        .predictor_index (index_predict),
        .signature       ()
    );

    hawkeye_hash_index hash_train (
        .value_in        (pc_train),
        .hash_out        (),
        .predictor_index (index_train),
        .signature       ()
    );

    // =========================================================================
    // Contador saturado combinacional
    // =========================================================================
    saturating_counter_unit #(
        .COUNTER_BITS(COUNTER_BITS)
    ) counter_update (
        .counter_current (counter_train_r),
        .train_up        (train_up_r),
        .train_down      (train_down_r),
        .aging_enable    (1'b0),
        .counter_next    (counter_next)
    );

    // =========================================================================
    // Bloco RAM — leitura sincrona (porta A: predict / porta B: train)
    // Padrao Simple Dual-Port RAM reconhecido pelo Quartus.
    // IMPORTANTE: sem reset de conteudo neste bloco.
    // =========================================================================
    always @(posedge clk) begin
        // Porta de predicao: somente leitura
        counter_predict_r <= ram_predict[index_predict];

        // Porta de treino: somente leitura (para calcular proximo valor)
        counter_train_r   <= ram_train[index_train];
    end

    // =========================================================================
    // Bloco de escrita espelhada nas duas copias
    // Separado do bloco de leitura para deixar o padrao claro ao sintetizador.
    // =========================================================================
    always @(posedge clk) begin
        if (train_enable_r) begin
            ram_predict[index_train_r] <= counter_next;
            ram_train  [index_train_r] <= counter_next;
        end
    end

    // =========================================================================
    // Pipeline de controle — reset afeta somente estes registradores,
    // NUNCA o conteudo da RAM (que nao suporta clear em hardware embarcado).
    // =========================================================================
    always @(posedge clk) begin
        if (reset) begin
            predict_enable_r  <= 1'b0;
            index_predict_r   <= {INDEX_BITS{1'b0}};

            train_enable_r    <= 1'b0;
            train_up_r        <= 1'b0;
            train_down_r      <= 1'b0;
            index_train_r     <= {INDEX_BITS{1'b0}};

            prediction_valid  <= 1'b0;
            friendly          <= 1'b0;
            averse            <= 1'b0;
        end
        else begin
            // Pipeline de predicao
            predict_enable_r  <= predict_enable;
            index_predict_r   <= index_predict;

            prediction_valid  <= predict_enable_r;
            friendly          <= predict_enable_r && (counter_predict_r >= THRESHOLD);
            averse            <= predict_enable_r && (counter_predict_r <  THRESHOLD);

            // Pipeline de treino
            index_train_r     <= index_train;
            train_up_r        <= train_up;
            train_down_r      <= train_down;
            train_enable_r    <= train_enable;
        end
    end

    // =========================================================================
    // Debug
    // =========================================================================
    assign counter_predict_debug = counter_predict_r;
    assign index_predict_debug   = index_predict_r;

endmodule