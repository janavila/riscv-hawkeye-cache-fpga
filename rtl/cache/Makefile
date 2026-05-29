# =============================================================================
# Makefile - projeto cache
# -----------------------------------------------------------------------------
#   make contador / cont-wave   -> Sessao 1 (contador)
#   make l1       / l1-wave      -> cache L1 (LRU, single-cycle)
#   make l2       / l2-wave      -> cache L2 (FSM, interface de politica aberta)
#   make clean
#
# Se 'make' nao estiver instalado: pacman -S make
# =============================================================================

# ---------- Contador (Sessao 1) ----------
contador: contador.v tb_contador.v
	iverilog -o tb_contador.vvp -s tb_contador contador.v tb_contador.v
	vvp tb_contador.vvp
cont-wave: ondas.vcd
	gtkwave ondas.vcd &

# ---------- Cache L1 ----------
l1: cache_l1.v tb_cache_l1.v
	iverilog -Wall -o tb_l1.vvp -s tb_cache_l1 cache_l1.v tb_cache_l1.v
	vvp tb_l1.vvp
l1-wave: ondas_l1.vcd
	gtkwave ondas_l1.vcd &

# ---------- Cache L2 (+ politica placeholder) ----------
# Quando o Hawkeye entrar, troque lru_policy_l2.v pelos arquivos do hawkeye
# e ajuste a instancia no testbench/integracao.
l2: cache_l2.v lru_policy_l2.v tb_cache_l2.v
	iverilog -Wall -o tb_l2.vvp -s tb_cache_l2 cache_l2.v lru_policy_l2.v tb_cache_l2.v
	vvp tb_l2.vvp
l2-wave: ondas_l2.vcd
	gtkwave ondas_l2.vcd &

clean:
	rm -f *.vvp *.vcd

.PHONY: contador cont-wave l1 l1-wave l2 l2-wave clean
