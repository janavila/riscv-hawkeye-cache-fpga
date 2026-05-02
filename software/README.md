# riscv-hawkeye-cache-fpga
Implementation of the Hawkeye replacement algorithm for L1/L2 caches in a RISC-V processor targeting Altera Cyclone III FPGA.

Compilação & execução
-> Windows 
    -> gcc -Wall -Wextra main.c cache.c file_io.c lru.c hawkeye.c sampler.c optgen.c -o simulador_cache.exe
    -> .\simulador_cache.exe

-> Linux
    -> make run


->Benchmark + trace padronizado para nosso simulador
    ->gcc -Wall benchmark_trace.c -o benchmark_trace
    ->./benchmark_trace

-> Modo de uso. 
--> Executar o benchmark (Ex: opção 5)
--> Executar simulador
---> Opção 10
---> Digite qual trace deseja executar