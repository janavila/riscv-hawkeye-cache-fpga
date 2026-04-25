# riscv-hawkeye-cache-fpga
Implementation of the Hawkeye replacement algorithm for L1/L2 caches in a RISC-V processor targeting Altera Cyclone III FPGA.

Compilação & execução
-> Windows 
    -> gcc -Wall -Wextra main.c cache.c file_io.c lru.c -o simulador_cache.exe
    -> .\simulador_cache.exe

-> Linux
    -> make run