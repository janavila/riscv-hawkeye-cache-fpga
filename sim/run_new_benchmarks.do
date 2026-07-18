# =============================================================================
# run_new_benchmarks.do
# -----------------------------------------------------------------------------
# Compila e roda os 4 testbenches equivalentes aos benchmarks em C
# (Streaming+Hot, Convolucao 256x256, Linked List, Pattern Search), todos
# com o MESMO TOTAL_ACCESSES, para gerar HR-L1/HR-L2/ciclos comparaveis.
#
# Uso, direto pelo Prompt de Comando (sem abrir a GUI do ModelSim, para
# evitar o popup de confirmacao do $finish):
#
#   "C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe" -c -do run_new_benchmarks.do
#
# Ajuste QUARTUS_SIM_LIB e os caminhos de vlog abaixo se necessario.
# =============================================================================

vlib work
vmap work work

# -----------------------------------------------------------------------------
# Biblioteca altera_mf isolada, so-Verilog (necessaria pois cache_l2.v e
# sampler.v instanciam altsyncram para inferencia de M9K).
# -----------------------------------------------------------------------------
set QUARTUS_SIM_LIB "C:/intelFPGA/18.1/modelsim_ase/altera/verilog/src"

vlib altera_mf_local
vmap altera_mf_local altera_mf_local
vlog -work altera_mf_local "$QUARTUS_SIM_LIB/altera_primitives.v"
vlog -work altera_mf_local "$QUARTUS_SIM_LIB/altera_mf.v"

echo "=== Compilando RTL ==="
vlog +define+SIMULATION rtl/cache/*.v
vlog +define+SIMULATION rtl/hawkeye/*.v

echo "=== Compilando os 4 novos testbenches ==="
vlog tb_bench_streaming_hot.v
vlog tb_bench_convolucao.v
vlog tb_bench_linkedlist.v
vlog tb_bench_pattern_search.v

# -----------------------------------------------------------------------------
# Mesma quantidade de requisicoes para os 4 benchmarks -> comparacao
# equivalente a que ja foi feita em software.
# -----------------------------------------------------------------------------
set TOTAL [expr {50000}]
set REPEV [expr {5000}]

# --- 1) Streaming + Hot ---
echo "=== Rodando: STREAMING + HOT ==="
transcript file log_streaming.txt
vsim -c -novopt -L altera_mf_local -GTOTAL_ACCESSES=$TOTAL -GREPORT_EVERY=$REPEV work.tb_bench_streaming_hot
run -all
quit -sim
transcript file ""

# --- 2) Convolucao ---
echo "=== Rodando: CONVOLUCAO 256x256 ==="
transcript file log_convolucao.txt
vsim -c -novopt -L altera_mf_local -GTOTAL_ACCESSES=$TOTAL -GREPORT_EVERY=$REPEV work.tb_bench_convolucao
run -all
quit -sim
transcript file ""

# --- 3) Linked List ---
echo "=== Rodando: LINKED LIST ==="
transcript file log_linkedlist.txt
vsim -c -novopt -L altera_mf_local -GTOTAL_ACCESSES=$TOTAL -GREPORT_EVERY=$REPEV work.tb_bench_linkedlist
run -all
quit -sim
transcript file ""

# --- 4) Pattern Search ---
echo "=== Rodando: PATTERN SEARCH ==="
transcript file log_pattern.txt
vsim -c -novopt -L altera_mf_local -GTOTAL_ACCESSES=$TOTAL -GREPORT_EVERY=$REPEV work.tb_bench_pattern_search
run -all
quit -sim
transcript file ""

echo "=== Todas as rodadas concluidas. Arquivos: log_streaming.txt, log_convolucao.txt, log_linkedlist.txt, log_pattern.txt ==="

quit -f
