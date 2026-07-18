## =============================================================================
## constraints.sdc
## -----------------------------------------------------------------------------
## Restricao de clock para a sintese do cache_hierarchy_top no Quartus II.
## Alvo: 50 MHz (periodo de 20 ns), conforme especificado no artigo
## (Secao 4.5 - Sintese e otimizacao).
## =============================================================================

create_clock -name clk -period 20.000 [get_ports clk]
