module optgen #(
    parameter OPTGEN_SIZE      = 128,
    parameter INDEX_BITS       = 7,
    parameter LIVENESS_BITS    = 8,
    parameter CACHE_SIZE_BITS  = 8,
    parameter NUM_CACHE_BITS   = 32,
    parameter ACCESS_BITS      = 32
)(
    input  wire                         clk,
    input  wire                         reset,

    /*
        start_check:
        Inicia a operação equivalente ao optgen_is_cache() do C.

        start_set_access:
        Inicia a operação equivalente ao optgen_set_access() do C.
    */
    input  wire                         start_check,
    input  wire                         start_set_access,

    /*
        current_val:
        Valor atual do tempo circular.
        No C: currentVal = set_timer[set] % OPTGEN_SIZE

        end_val:
        Valor anterior salvo no sampler.
        No C: prev_mod = previous_time % OPTGEN_SIZE

        cache_size:
        Tamanho efetivo usado pelo OPTgen.
        No C: opt->cache_size
    */
    input  wire [INDEX_BITS-1:0]        current_val,
    input  wire [INDEX_BITS-1:0]        end_val,
    input  wire [CACHE_SIZE_BITS-1:0]   cache_size,

    /*
        busy:
        Indica que o OPTgen está processando.

        done:
        Sobe por 1 ciclo quando a operação termina.

        should_cache:
        Resultado do optgen_is_cache().
        1 = bloco deveria ficar na cache.
        0 = bloco não deveria ficar na cache.
    */
    output reg                          busy,
    output reg                          done,
    output reg                          should_cache,

    /*
        Saídas de debug para ModelSim.
    */
    output wire [NUM_CACHE_BITS-1:0]    num_cache_debug,
    output wire [ACCESS_BITS-1:0]       access_debug,
    output wire [INDEX_BITS-1:0]        count_debug,
    output wire [2:0]                   state_debug
);

    /*
        Estados da FSM.
    */
    localparam [2:0] IDLE            = 3'd0;
    localparam [2:0] CHECK_INTERVAL  = 3'd1;
    localparam [2:0] UPDATE_INTERVAL = 3'd2;
    localparam [2:0] SET_ACCESS      = 3'd3;
    localparam [2:0] DONE_STATE      = 3'd4;

    reg [2:0] state;

    /*
        Memória equivalente a:

        unsigned int liveness_intervals[OPTGEN_SIZE];

        No C, cada posição da janela guarda quantos blocos estão vivos
        naquele intervalo.
    */
    reg [LIVENESS_BITS-1:0] liveness_intervals [0:OPTGEN_SIZE-1];

    /*
        Equivalentes aos campos do struct OPTgen no C.
    */
    reg [NUM_CACHE_BITS-1:0] num_cache;
    reg [ACCESS_BITS-1:0]    access_count;

    /*
        Registradores internos para congelar as entradas durante uma operação.
        Isso é importante porque start_check pode durar vários ciclos.
    */
    reg [INDEX_BITS-1:0]      current_val_reg;
    reg [INDEX_BITS-1:0]      end_val_reg;
    reg [CACHE_SIZE_BITS-1:0] cache_size_reg;

    /*
        count percorre circularmente a janela.
        Como OPTGEN_SIZE = 128 = 2^7, count com 7 bits já faz wrap automático:
        127 + 1 = 0.
    */
    reg [INDEX_BITS-1:0] count;

    integer i;

    assign num_cache_debug = num_cache;
    assign access_debug    = access_count;
    assign count_debug     = count;
    assign state_debug     = state;

    always @(posedge clk) begin
        if (reset) begin
            state        <= IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            should_cache <= 1'b0;

            count           <= {INDEX_BITS{1'b0}};
            current_val_reg <= {INDEX_BITS{1'b0}};
            end_val_reg     <= {INDEX_BITS{1'b0}};
            cache_size_reg  <= {CACHE_SIZE_BITS{1'b0}};

            num_cache    <= {NUM_CACHE_BITS{1'b0}};
            access_count <= {ACCESS_BITS{1'b0}};

            for (i = 0; i < OPTGEN_SIZE; i = i + 1) begin
                liveness_intervals[i] <= {LIVENESS_BITS{1'b0}};
            end
        end
        else begin
            /*
                Por padrão, done fica 0.
                Ele só sobe no estado DONE_STATE.
            */
            done <= 1'b0;

            case (state)

                /*
                    Estado parado.
                    Espera um comando.
                */
                IDLE: begin
                    busy <= 1'b0;

                    if (start_check) begin
                        /*
                            Começa operação equivalente ao optgen_is_cache().

                            No C:
                                bool cache = true;
                                count = endVal;
                                while (count != val) ...
                        */
                        current_val_reg <= current_val;
                        end_val_reg     <= end_val;
                        cache_size_reg  <= cache_size;

                        count           <= end_val;
                        should_cache    <= 1'b1;
                        busy            <= 1'b1;

                        state           <= CHECK_INTERVAL;
                    end
                    else if (start_set_access) begin
                        /*
                            Começa operação equivalente ao optgen_set_access().

                            No C:
                                opt->access++;
                                opt->liveness_intervals[val] = 0;
                        */
                        current_val_reg <= current_val;
                        busy            <= 1'b1;

                        state           <= SET_ACCESS;
                    end
                end

                /*
                    Primeiro while do optgen_is_cache():

                    while (count != val)
                    {
                        if (liveness_intervals[count] >= cache_size)
                        {
                            cache = false;
                            break;
                        }

                        count = (count + 1) % OPTGEN_SIZE;
                    }
                */
                CHECK_INTERVAL: begin
                    busy <= 1'b1;

                    if (count == current_val_reg) begin
                        /*
                            Chegou no final do intervalo sem violar cache_size.
                            Então o bloco deveria caber na cache.
                            Agora precisamos incrementar os intervalos vivos.
                        */
                        should_cache <= 1'b1;
                        count        <= end_val_reg;
                        state        <= UPDATE_INTERVAL;
                    end
                    else if (liveness_intervals[count] >= cache_size_reg) begin
                        /*
                            Encontrou um intervalo já cheio.
                            Então o bloco não deveria estar na cache.
                            Não incrementa os intervalos.
                        */
                        should_cache <= 1'b0;
                        state        <= DONE_STATE;
                    end
                    else begin
                        /*
                            Continua percorrendo a janela circular.
                        */
                        count <= count + 1'b1;
                    end
                end

                /*
                    Segundo while do optgen_is_cache(), executado apenas
                    se should_cache for verdadeiro:

                    while (count != val)
                    {
                        liveness_intervals[count]++;
                        count = (count + 1) % OPTGEN_SIZE;
                    }

                    num_cache++;
                */
                UPDATE_INTERVAL: begin
                    busy <= 1'b1;

                    if (count == current_val_reg) begin
                        /*
                            Terminou de incrementar os intervalos.
                            Conta mais um hit ideal no OPTgen.
                        */
                        num_cache <= num_cache + 1'b1;
                        state     <= DONE_STATE;
                    end
                    else begin
                        /*
                            Incrementa o intervalo vivo com saturação simples.
                            Isso evita overflow da contagem.
                        */
                        if (liveness_intervals[count] != {LIVENESS_BITS{1'b1}}) begin
                            liveness_intervals[count] <= liveness_intervals[count] + 1'b1;
                        end

                        count <= count + 1'b1;
                    end
                end

                /*
                    Operação equivalente ao optgen_set_access():

                    No C:
                        opt->access++;
                        opt->liveness_intervals[val] = 0;

                    Esse comando normalmente deve acontecer depois do check.
                */
                SET_ACCESS: begin
                    busy <= 1'b1;

                    access_count <= access_count + 1'b1;
                    liveness_intervals[current_val_reg] <= {LIVENESS_BITS{1'b0}};

                    state <= DONE_STATE;
                end

                /*
                    Finaliza a operação.
                    done sobe por um ciclo.
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