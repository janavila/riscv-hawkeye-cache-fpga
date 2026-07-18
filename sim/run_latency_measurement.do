# =============================================================================
# run_latency_measurement.do
# -----------------------------------------------------------------------------
# Compila e roda o tb_latency_measurement, medindo as 3 latencias pedidas
# pela Tabela 3 da especificacao (hit L2, selecao de vitima RRIP,
# treinamento do preditor).
#
# Uso, pelo Prompt de Comando (modo batch, sem popup):
#   "C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe" -c -do run_latency_measurement.do
# =============================================================================

vlib work
vmap work work

set QUARTUS_SIM_LIB "C:/intelFPGA/18.1/modelsim_ase/altera/verilog/src"

vlib altera_mf_local
vmap altera_mf_local altera_mf_local
vlog -work altera_mf_local "$QUARTUS_SIM_LIB/altera_primitives.v"
vlog -work altera_mf_local "$QUARTUS_SIM_LIB/altera_mf.v"

echo "=== Compilando RTL ==="
vlog +define+SIMULATION rtl/cache/*.v
vlog +define+SIMULATION rtl/hawkeye/*.v

echo "=== Compilando tb_latency_measurement ==="
vlog sim/tb_latency_measurement.v

echo "=== Rodando medicao de latencia ==="
transcript file log_latency.txt

vsim -c -novopt -L altera_mf_local work.tb_latency_measurement
run -all
quit -sim

transcript file ""

echo "=== Concluido. Verifique log_latency.txt ==="

quit -f
