# =============================================================================
# run_existing_benchmarks.do
# -----------------------------------------------------------------------------
# Reproduz as duas curvas ja existentes no projeto (slides 10 e 12 da
# apresentacao final):
#
#   tb_hawkeye_proof              -> HR-L2 (hit/miss) vs TOTAL_ACCESSES
#   tb_cache_final_integrated_proof -> % Friendly/Averse vs WARMUP_PAIRS
#
# nas 9 cargas documentadas: 1K, 3K, 5K, 10K, 30K, 50K, 100K, 300K, 500K.
#
# Cada rodada grava seu proprio log (transcript file), rotulado com "echo"
# para facilitar a conferencia visual e a extracao automatica depois.
#
# IMPORTANTE:
# - Ajuste os caminhos de vlog abaixo (rtl/cache, rtl/hawkeye, sim) para a
#   estrutura real do seu clone.
# - As cargas de 100K+ demoram bastante em modo -c; rode primeiro so 1K/3K/5K
#   para validar que nao ha erro/timeout antes de deixar a bateria completa
#   rodando.
# =============================================================================

vlib work
vmap work work

# -----------------------------------------------------------------------------
# Biblioteca altera_mf ISOLADA, so-Verilog.
# -----------------------------------------------------------------------------
# A ModelSim-Altera Starter Edition (ASE) so simula com uma unica linguagem
# HDL por elaboracao. O mapeamento global "altera_mf" que vem com a
# instalacao do Quartus normalmente mistura conteudo Verilog e VHDL, o que
# faz a ASE recusar a elaboracao (erro "ALTERA version supports only a
# single HDL"). A solucao e compilar nossa propria copia, so com a fonte
# Verilog (altera_mf.v), numa biblioteca dedicada.
#
# AJUSTE o caminho abaixo para onde o Quartus II 13.1 esta instalado na sua
# maquina, se for diferente do padrao.
# -----------------------------------------------------------------------------
set QUARTUS_SIM_LIB "C:/intelFPGA/18.1/modelsim_ase/altera/verilog/src"

vlib altera_mf_local
vmap altera_mf_local altera_mf_local
vlog -work altera_mf_local "$QUARTUS_SIM_LIB/altera_primitives.v"
vlog -work altera_mf_local "$QUARTUS_SIM_LIB/altera_mf.v"

echo "=== Compilando RTL ==="
vlog +define+SIMULATION rtl/cache/*.v
vlog +define+SIMULATION rtl/hawkeye/*.v

# -----------------------------------------------------------------------------
# Bateria 1: tb_hawkeye_proof (HR-L2 vs TOTAL_ACCESSES)
# -----------------------------------------------------------------------------
echo "=== BATERIA 1: tb_hawkeye_proof ==="

foreach n {1000 3000 5000 10000 30000 50000 100000 300000 500000} {
    echo "--- tb_hawkeye_proof TOTAL_ACCESSES=$n ---"

    transcript file log_hawkeyeproof_$n.txt

    vsim -c -novopt \
         -L altera_mf_local \
         -GTOTAL_ACCESSES=$n \
         -GWARMUP_ACCESSES=[expr {$n / 2}] \
         -GREPORT_EVERY=[expr {$n / 4 + 1}] \
         work.tb_hawkeye_proof

    run -all
    quit -sim

    transcript file ""
}

# -----------------------------------------------------------------------------
# Bateria 2: tb_cache_final_integrated_proof (% Friendly/Averse vs WARMUP_PAIRS)
# -----------------------------------------------------------------------------
echo "=== BATERIA 2: tb_cache_final_integrated_proof ==="

foreach n {1000 3000 5000 10000 30000 50000 100000 300000 500000} {
    echo "--- tb_cache_final_integrated_proof WARMUP_PAIRS=$n ---"

    transcript file log_finalproof_$n.txt

    vsim -c -novopt \
         -L altera_mf_local \
         -GWARMUP_PAIRS=$n \
         -GREPORT_EVERY=[expr {$n / 4 + 1}] \
         -GRETEST_AFTER_RESET=0 \
         work.tb_cache_final_integrated_proof

    run -all
    quit -sim

    transcript file ""
}

echo "=== Todas as rodadas concluidas. Arquivos: log_hawkeyeproof_*.txt e log_finalproof_*.txt ==="
