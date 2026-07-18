# riscv-hawkeye-cache-fpga

Implementação em Verilog RTL do algoritmo de substituição de cache **Hawkeye** em uma hierarquia de cache de dois níveis para um processador **RISC-V (RV32I)**, com síntese direcionada ao FPGA **Altera Cyclone III (EP3C25F324C6)**.

Projeto Integrador IV — Engenharia de Computação, UNIPAMPA (Campus Bagé).
Orientador: Prof. Bruno Silveira Neves.
Equipe: Jansen Ávila, Filipe Teixeira e Leonardo Borges.

---

## Objetivo

Avaliar, em hardware real, o custo e o benefício de substituir uma política de substituição clássica (LRU) por uma política preditiva baseada no comportamento passado dos acessos. O trabalho parte de um modelo de referência em C, valida a taxa de acertos contra o baseline LRU e então descreve a mesma lógica em RTL, medindo:

- **Área**: elementos lógicos (LEs), registradores e blocos de memória adicionais;
- **Timing**: impacto na frequência máxima (Fmax);
- **Latência**: ciclos necessários para a decisão;
- **IEC**: ganho percentual de hit rate dividido pelo custo em LEs.

## O algoritmo Hawkeye

O Hawkeye (Jain & Lin, ISCA 2016) parte de uma ideia simples: o algoritmo ótimo de Belady (1966) é impossível de implementar em tempo real, porque exigiria conhecer o futuro — mas é perfeitamente possível aplicá-lo **ao passado**. O Hawkeye então aprende com essas decisões ótimas retroativas e usa esse aprendizado para prever o futuro.

O fluxo tem quatro peças:

1. **Sampler** — observa apenas um subconjunto de conjuntos da cache e guarda o histórico recente de acessos (PC de origem, assinatura e instante do acesso). Amostrar reduz drasticamente o custo em área.
2. **OPTgen** — reconstrói, sobre esse histórico, o que Belady teria feito. Ele verifica se havia *espaço disponível* no vetor de ocupação durante todo o intervalo de uso do bloco; se havia, o bloco é marcado como **cache-friendly** (Belady o teria mantido); caso contrário, **cache-averse**.
3. **Preditor** — uma tabela de contadores saturados indexada por uma assinatura do PC (obtida por hash CRC). O veredito do OPTgen treina o contador do PC correspondente. A predição final é simplesmente o **bit mais significativo** do contador — sem comparador.
4. **Política de inserção/evicção (RRIP)** — linhas previstas como *averse* entram com prioridade de evicção máxima; linhas *friendly* entram com prioridade alta de retenção. A vítima escolhida é sempre a linha averse mais antiga, ou, na falta dela, a de maior RRPV.

Em resumo: o passado é resolvido de forma ótima, o PC é usado como "impressão digital" do comportamento, e o futuro é decidido por um contador de 1 bit de decisão.

## Organização da hierarquia

| | L1 | L2 |
|---|---|---|
| Capacidade | 4 KB | 32 KB |
| Associatividade | 2 vias | 8 vias |
| Tamanho de bloco | 32 bytes | 64 bytes |
| Conjuntos | 64 | 64 |
| Política | LRU | Hawkeye |

## Estrutura do repositório

```
/docs      Relatório final (PDF), diagramas e documentação das sprints
/rtl       Código-fonte Verilog
  cache/       hierarquia, cache L1 e L2, seleção de vítima
  hawkeye/     CRC hash, sampler, OPTgen, preditor e FSM de treinamento
  riscv_core/  núcleo RV32I e integração
/sim       Testbenches e scripts de simulação (ModelSim)
/software  Benchmarks em C/Assembly e o modelo de referência
/synth     Relatórios de síntese (utilização e timing) do Quartus
```

## Referências

- Jain, A.; Lin, C. *Back to the Future: Leveraging Belady's Algorithm for Improved Cache Replacement*. ISCA, 2016.
- Belady, L. A. *A study of replacement algorithms for a virtual-storage computer*. IBM Systems Journal, 1966.
- Jaleel, A. et al. *High Performance Cache Replacement Using Re-Reference Interval Prediction (RRIP)*. ISCA, 2010.
- Patterson, D.; Hennessy, J. *Computer Organization and Design: RISC-V Edition*, 2017.
