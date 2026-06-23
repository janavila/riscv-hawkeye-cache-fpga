module hawkeye_training_controller #(
    parameter PC_BITS = 64
)(
    input  wire                 clk,
    input  wire                 reset,

    /*
        Entrada vinda da cache/top-level.
        access_valid indica que existe um acesso novo para processar.
        access_miss indica se esse acesso foi miss.
    */
    input  wire                 access_valid,
    input  wire                 access_miss,

    /*
        Resultado vindo do sampler.
        sampler_hit = 1 significa que existe histórico para essa assinatura.
        pc_anterior é o PC salvo anteriormente no sampler.
    */
    input  wire                 sampler_hit,
    input  wire [PC_BITS-1:0]   pc_anterior,

    /*
        Resultado vindo do OPTgen.
        optgen_done indica que o OPTgen terminou.
        optgen_should_cache é o julgamento:
        1 = deveria ficar na cache
        0 = não deveria ficar na cache
    */
    input  wire                 optgen_done,
    input  wire                 optgen_should_cache,

    /*
        Controle para o OPTgen.
    */
    output reg                  optgen_start_check,
    output reg                  optgen_start_set_access,

    /*
        Controle para o preditor Hawkeye.
    */
    output reg                  predictor_train_enable,
    output reg                  predictor_train_up,
    output reg                  predictor_train_down,
    output reg  [PC_BITS-1:0]   pc_train,

    /*
        Controle para o sampler.
        Quando sobe, o sampler atualiza/salva a entrada atual.
    */
    output reg                  sampler_update_enable,

    /*
        Sinais gerais.
    */
    output reg                  busy,
    output reg                  done,
    output wire [3:0]           state_debug
);

    localparam [3:0] IDLE               = 4'd0;
    localparam [3:0] WAIT_SAMPLER_READ  = 4'd1;
    localparam [3:0] DECIDE_PATH        = 4'd2;
    localparam [3:0] START_OPTGEN_CHECK = 4'd3;
    localparam [3:0] WAIT_OPTGEN_CHECK  = 4'd4;
    localparam [3:0] TRAIN_PREDICTOR    = 4'd5;
    localparam [3:0] START_SET_ACCESS   = 4'd6;
    localparam [3:0] WAIT_SET_ACCESS    = 4'd7;
    localparam [3:0] UPDATE_SAMPLER     = 4'd8;
    localparam [3:0] DONE_STATE         = 4'd9;

    reg [3:0] state;

    /*
        Guardamos o resultado do OPTgen para usar no estado de treino.
    */
    reg should_cache_reg;
    /*
    Registradores para alinhar sinais vindos de RAM síncrona.
    O sampler_hit e pc_anterior não devem ser usados crus no mesmo ciclo
    do access_valid, porque o sampler agora usa RAM.
    */
    reg                  access_miss_reg;
    reg                  sampler_hit_reg;
    reg [PC_BITS-1:0]    pc_anterior_reg;
    assign state_debug = state;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;

            optgen_start_check      <= 1'b0;
            optgen_start_set_access <= 1'b0;

            predictor_train_enable  <= 1'b0;
            predictor_train_up      <= 1'b0;
            predictor_train_down    <= 1'b0;
            pc_train                <= {PC_BITS{1'b0}};

            sampler_update_enable   <= 1'b0;

            busy                    <= 1'b0;
            done                    <= 1'b0;

            should_cache_reg        <= 1'b0;
            access_miss_reg      <= 1'b0;
            sampler_hit_reg      <= 1'b0;
            pc_anterior_reg      <= {PC_BITS{1'b0}};
        end
        else begin
            /*
                Por padrão, sinais de pulso ficam zerados.
                Eles sobem apenas em estados específicos por 1 ciclo.
            */
            optgen_start_check      <= 1'b0;
            optgen_start_set_access <= 1'b0;

            predictor_train_enable  <= 1'b0;
            predictor_train_up      <= 1'b0;
            predictor_train_down    <= 1'b0;

            sampler_update_enable   <= 1'b0;

            done                    <= 1'b0;

            case (state)

                /*
                    Espera um novo acesso.
                */
                IDLE: begin
                    busy <= 1'b0;   
                                  if (access_valid) begin
                      busy <= 1'b1; 
                                      /*
                          Guarda o miss do acesso atual, porque access1;    
                                      /*
                          Guarda o miss do acesso atual, porque access_miss pode ser pulso.
                          O sampler será lido agora, mas o resultado só ficará válido depois.
                      */
                      access_miss_reg <= access_miss;   
                                      state <= WAIT_SAMPLER_READ;
                  end
                end
                WAIT_SAMPLER_READ: begin
                    busy <= 1'b1;

                    /*
                        Espera 1 ciclo para o sampler entregar sampler_hit e pc_anterior.
                        Como o sampler foi convertido para RAM síncrona, esses sinais precisam
                        ser registrados antes da decisão.
                    */
                    sampler_hit_reg <= sampler_hit;
                    pc_anterior_reg <= pc_anterior;

                    state <= DECIDE_PATH;
                end
                /*
                    Decide qual caminho seguir.

                    Se o sampler encontrou histórico e o acesso foi miss,
                    precisamos chamar OPTgen para decidir se treina up ou down.

                    Caso contrário, não há treino do preditor.
                    Mesmo assim, o OPTgen precisa receber set_access e
                    o sampler deve ser atualizado.
                */
                DECIDE_PATH: begin
                    busy <= 1'b1;

                    /*
                        Usa os sinais registrados, não os sinais crus.
                    */
                    if (sampler_hit_reg && access_miss_reg) begin
                        state <= START_OPTGEN_CHECK;
                    end
                    else begin
                        state <= START_SET_ACCESS;
                    end
                end

                /*
                    Dá um pulso para iniciar optgen_is_cache().
                */
                START_OPTGEN_CHECK: begin
                    busy <= 1'b1;

                    optgen_start_check <= 1'b1;

                    state <= WAIT_OPTGEN_CHECK;
                end

                /*
                    Espera o OPTgen terminar o check.
                */
                WAIT_OPTGEN_CHECK: begin
                    busy <= 1'b1;

                    if (optgen_done) begin
                        should_cache_reg <= optgen_should_cache;
                        state <= TRAIN_PREDICTOR;
                    end
                end

                /*
                    Gera treino para o preditor.

                    should_cache = 1:
                        train_up

                    should_cache = 0:
                        train_down

                    O PC treinado é o PC anterior salvo no sampler.
                */
                TRAIN_PREDICTOR: begin
                    busy <= 1'b1;

                    predictor_train_enable <= 1'b1;
                    pc_train <= pc_anterior_reg;
                    if (should_cache_reg) begin
                        predictor_train_up   <= 1'b1;
                        predictor_train_down <= 1'b0;
                    end
                    else begin
                        predictor_train_up   <= 1'b0;
                        predictor_train_down <= 1'b1;
                    end

                    state <= START_SET_ACCESS;
                end

                /*
                    Depois do check/treino, executa optgen_set_access().
                    Isso zera a posição atual da janela de liveness.
                */
                START_SET_ACCESS: begin
                    busy <= 1'b1;

                    optgen_start_set_access <= 1'b1;

                    state <= WAIT_SET_ACCESS;
                end

                /*
                    Espera o optgen_set_access terminar.
                */
                WAIT_SET_ACCESS: begin
                    busy <= 1'b1;

                    if (optgen_done) begin
                        state <= UPDATE_SAMPLER;
                    end
                end

                /*
                    Atualiza o sampler com a assinatura/PC/tempo atuais.
                    O sampler.v usa esse pulso para gravar a entrada.
                */
                UPDATE_SAMPLER: begin
                    busy <= 1'b1;

                    sampler_update_enable <= 1'b1;

                    state <= DONE_STATE;
                end

                /*
                    Finaliza o processamento do acesso.
                */
                DONE_STATE: begin
                    busy <= 1'b0;
                    done <= 1'b1;

                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    busy  <= 1'b0;
                    done  <= 1'b0;
                end

            endcase
        end
    end

endmodule   