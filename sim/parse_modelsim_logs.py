#!/usr/bin/env python3
# =============================================================================
# parse_modelsim_logs.py
# -----------------------------------------------------------------------------
# Le os arquivos log_streaming.txt, log_convolucao.txt, log_linkedlist.txt e
# log_pattern.txt gerados pelo run_benchmarks.do, extrai as linhas "ECHO,..."
# e monta:
#   - resultados_finais.csv   (uma linha por benchmark, formato da Tabela 2)
#   - progresso_<benchmark>.csv (evolucao do hit rate ao longo dos acessos)
#
# Uso:
#   python parse_modelsim_logs.py
# =============================================================================

import csv
import re
from pathlib import Path

try:
    import matplotlib.pyplot as plt
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False

LOGS = {
    "Streaming":     "log_streaming.txt",
    "Convolucao":    "log_convolucao.txt",
    "LinkedList":    "log_linkedlist.txt",
    "PatternSearch": "log_pattern.txt",
}

def parse_log(path):
    final = {}
    progress_rows = []

    if not Path(path).exists():
        print(f"[aviso] arquivo nao encontrado: {path}")
        return final, progress_rows

    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()

            # O ModelSim prefixa toda linha de $display com "# " no transcript.
            if line.startswith("#"):
                line = line[1:].strip()

            if not line.startswith("ECHO,"):
                continue

            parts = line.split(",")
            # ECHO,FINAL,<chave>,<valor>
            if parts[1] == "FINAL" and len(parts) >= 4:
                final[parts[2]] = parts[3]
            # ECHO,PROGRESS,idx,l1h,l1m,l2h,l2m,hr_l1,hr_l2
            elif parts[1] == "PROGRESS" and len(parts) >= 8:
                progress_rows.append({
                    "idx": int(parts[2]),
                    "l1_hits": int(parts[3]),
                    "l1_misses": int(parts[4]),
                    "l2_hits": int(parts[5]),
                    "l2_misses": int(parts[6]),
                    "hr_l1_pct": float(parts[7]),
                    "hr_l2_pct": float(parts[8]),
                })

    return final, progress_rows


def plot_resultados_finais(final_rows):
    """Grafico de barras comparando HR-L1 e HR-L2 dos 4 benchmarks -
    equivalente ao 'Inserir grafico de barras' pendente na Secao 5.1 do artigo."""
    if not HAS_MATPLOTLIB:
        print("[aviso] matplotlib nao instalado - pulei os PNGs. "
              "Rode: python3 -m pip install matplotlib")
        return

    names  = [r["benchmark"] for r in final_rows]
    hr_l1  = [float(r["hr_l1_pct"]) for r in final_rows]
    hr_l2  = [float(r["hr_l2_pct"]) for r in final_rows]

    x = list(range(len(names)))
    width = 0.35

    fig, ax = plt.subplots(figsize=(9, 5))
    ax.bar([xi - width/2 for xi in x], hr_l1, width, label="HR-L1", color="#1f77b4")
    ax.bar([xi + width/2 for xi in x], hr_l2, width, label="HR-L2", color="#ff7f0e")

    for xi, yi in zip(x, hr_l1):
        ax.annotate(f"{yi:.2f}%", (xi - width/2, yi), textcoords="offset points",
                     xytext=(0, 4), ha="center", fontsize=8)
    for xi, yi in zip(x, hr_l2):
        ax.annotate(f"{yi:.2f}%", (xi + width/2, yi), textcoords="offset points",
                     xytext=(0, 4), ha="center", fontsize=8)

    ax.set_xticks(x)
    ax.set_xticklabels(names)
    ax.set_ylabel("Taxa de acerto (%)")
    ax.set_title("HR-L1 e HR-L2 por benchmark (RTL, configuracao LRU+Hawkeye)")
    ax.legend()
    ax.grid(True, axis="y", alpha=0.3)

    fig.tight_layout()
    fig.savefig("resultados_finais.png", dpi=200)
    plt.close(fig)
    print("[ok] resultados_finais.png gerado")


def plot_progress(name, progress_rows):
    """Grafico de evolucao do HR-L1/HR-L2 ao longo dos acessos, para um benchmark."""
    if not HAS_MATPLOTLIB:
        return
    if len(progress_rows) < 2:
        print(f"[aviso] menos de 2 pontos de progresso para {name} - pulei o grafico de evolucao")
        return

    idx    = [r["idx"] for r in progress_rows]
    hr_l1  = [r["hr_l1_pct"] for r in progress_rows]
    hr_l2  = [r["hr_l2_pct"] for r in progress_rows]

    fig, ax = plt.subplots(figsize=(9, 5))
    ax.plot(idx, hr_l1, marker="o", markersize=3, color="#1f77b4", label="HR-L1")
    ax.plot(idx, hr_l2, marker="o", markersize=3, color="#ff7f0e", label="HR-L2")

    ax.set_xlabel("Numero de acessos processados")
    ax.set_ylabel("Taxa de acerto (%)")
    ax.set_title(f"Evolucao do hit rate - {name}")
    ax.legend()
    ax.grid(True, alpha=0.3)

    fig.tight_layout()
    out_name = f"progresso_{name.lower()}.png"
    fig.savefig(out_name, dpi=200)
    plt.close(fig)
    print(f"[ok] {out_name} gerado")


def render_table_png(headers, rows, title, filename, col_widths=None):
    """Renderiza uma tabela (lista de headers + lista de linhas) como PNG,
    com cabecalho destacado. Usado para complementar a tabela .tex com uma
    versao pronta para colar em slides/apresentacoes."""
    if not HAS_MATPLOTLIB:
        print(f"[aviso] matplotlib nao instalado - pulei {filename}. "
              "Rode: python3 -m pip install matplotlib")
        return

    n_rows = len(rows)
    n_cols = len(headers)
    fig_height = 1.3 + 0.4 * (n_rows + 1)
    fig_width  = max(1.5 * n_cols, 8)

    fig, ax = plt.subplots(figsize=(fig_width, fig_height))
    ax.axis("off")
    ax.set_title(title, fontsize=12, pad=22)

    table = ax.table(cellText=rows, colLabels=headers, loc="center",
                      cellLoc="center", colWidths=col_widths,
                      bbox=[0, 0, 1, 0.85])
    table.auto_set_font_size(False)
    table.set_fontsize(9 if n_cols <= 6 else 8)

    for (row, col), cell in table.get_celld().items():
        if row == 0:
            cell.set_facecolor("#1f77b4")
            cell.set_text_props(color="white", weight="bold")
            cell.set_height(0.18)
        else:
            cell.set_facecolor("#f2f2f2" if row % 2 == 0 else "white")
            cell.set_height(0.12)

    fig.savefig(filename, dpi=200, bbox_inches="tight")
    plt.close(fig)
    print(f"[ok] {filename} gerado")


def write_latex_table(final_rows):
    """Gera tabela_benchmarks_hardware.tex - HR/MR de L1 e L2, contagens de
    hit/miss e ciclos por benchmark, pronta para \\input{} no artigo."""
    lines = []
    lines.append("% Gerado automaticamente por parse_modelsim_logs.py - nao editar a mao.")
    lines.append("% Inclua no documento com \\input{tabela_benchmarks_hardware.tex}")
    lines.append("\\begin{table}[h]")
    lines.append("\\centering")
    lines.append("\\caption{Validacao em hardware -- HR/MR de L1 e L2, contagens de "
                  "acerto/falta e ciclos por padrao de acesso, RTL sintetizavel com "
                  "Hawkeye ativo na L2 (mesma quantidade de requisicoes para os "
                  "quatro padroes).}")
    lines.append("\\label{tab:hw-benchmarks}")
    lines.append("\\begin{tabular}{lccccccccc}")
    lines.append("\\hline")
    lines.append("\\textbf{Benchmark} & \\textbf{HR-L1 (\\%)} & \\textbf{Hits} & "
                  "\\textbf{MR-L1 (\\%)} & \\textbf{Miss} & \\textbf{HR-L2 (\\%)} & "
                  "\\textbf{Hits} & \\textbf{MR-L2 (\\%)} & \\textbf{Miss} & "
                  "\\textbf{Ciclos} \\\\")
    lines.append("\\hline")

    png_rows = []

    for r in final_rows:
        hr_l1 = float(r["hr_l1_pct"])
        hr_l2 = float(r["hr_l2_pct"])
        mr_l1 = 100.0 - hr_l1
        mr_l2 = 100.0 - hr_l2

        l1_hits   = int(r["l1_hits"])
        l1_misses = int(r["l1_misses"])
        l2_hits   = int(r["l2_hits"])
        l2_misses = int(r["l2_misses"])
        ciclos    = int(round(float(r["cost_model_cycles"])))

        nome = {
            "Streaming":     "Streaming + Hot Conflitante",
            "Convolucao":    "Convolucao $256\\times256$",
            "LinkedList":    "Lista encadeada",
            "PatternSearch": "Busca com conflito de via",
        }.get(r["benchmark"], r["benchmark"])

        def fmt(v):
            return f"{v:.2f}".replace(".", ",")

        def fmt_int(v):
            return f"{v:,}".replace(",", ".")

        lines.append(f"{nome} & {fmt(hr_l1)} & {fmt_int(l1_hits)} & {fmt(mr_l1)} & "
                      f"{fmt_int(l1_misses)} & {fmt(hr_l2)} & {fmt_int(l2_hits)} & "
                      f"{fmt(mr_l2)} & {fmt_int(l2_misses)} & {fmt_int(ciclos)} \\\\")

        nome_png = nome.replace("$256\\times256$", "256x256")
        png_rows.append([nome_png, fmt(hr_l1), fmt_int(l1_hits), fmt(mr_l1),
                          fmt_int(l1_misses), fmt(hr_l2), fmt_int(l2_hits),
                          fmt(mr_l2), fmt_int(l2_misses), fmt_int(ciclos)])

    lines.append("\\hline")
    lines.append("\\end{tabular}")
    lines.append("\\end{table}")

    with open("tabela_benchmarks_hardware.tex", "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print("[ok] tabela_benchmarks_hardware.tex gerado")

    render_table_png(
        headers=["Benchmark", "HR-L1 (%)", "Hits", "MR-L1 (%)", "Miss",
                  "HR-L2 (%)", "Hits", "MR-L2 (%)", "Miss", "Ciclos"],
        rows=png_rows,
        title="HR/MR, hits/misses e ciclos por benchmark (RTL, LRU+Hawkeye)",
        filename="tabela_benchmarks_hardware.png",
        col_widths=[0.20, 0.09, 0.08, 0.09, 0.08, 0.09, 0.08, 0.09, 0.08, 0.12],
    )


def main():
    final_rows = []

    for name, path in LOGS.items():
        final, progress = parse_log(path)

        if final:
            final_rows.append({
                "benchmark": name,
                "hr_l1_pct": final.get("HR_L1_PCT", ""),
                "hr_l2_pct": final.get("HR_L2_PCT", ""),
                "l1_hits": final.get("L1_HITS", ""),
                "l1_misses": final.get("L1_MISSES", ""),
                "l2_hits": final.get("L2_HITS", ""),
                "l2_misses": final.get("L2_MISSES", ""),
                "ram_accesses": final.get("RAM_ACCESSES", ""),
                "cost_model_cycles": final.get("COST_MODEL_CYCLES", ""),
                "rtl_clk_cycles": final.get("RTL_CLK_CYCLES", ""),
                "errors": final.get("ERRORS", ""),
            })

        if progress:
            out_name = f"progresso_{name.lower()}.csv"
            with open(out_name, "w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(f, fieldnames=list(progress[0].keys()))
                writer.writeheader()
                writer.writerows(progress)
            print(f"[ok] {out_name} gerado ({len(progress)} pontos)")
            plot_progress(name, progress)

    if final_rows:
        with open("resultados_finais.csv", "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(final_rows[0].keys()))
            writer.writeheader()
            writer.writerows(final_rows)
        print(f"[ok] resultados_finais.csv gerado ({len(final_rows)} benchmarks)")
        plot_resultados_finais(final_rows)
        write_latex_table(final_rows)
    else:
        print("[erro] nenhum resultado final encontrado - confira se os logs existem e se as rodadas terminaram sem timeout")


if __name__ == "__main__":
    main()
