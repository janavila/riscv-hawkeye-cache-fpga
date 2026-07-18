#!/usr/bin/env python3
# =============================================================================
# parse_existing_benchmarks.py  (v2 - ajustado ao formato REAL dos logs)
# -----------------------------------------------------------------------------
# Le os logs gerados por run_existing_benchmarks.do e monta dois CSVs:
#
#   hawkeye_proof_hr_l2.csv          -> HR-L1/HR-L2 vs total de acessos
#   final_proof_friendly_averse.csv  -> L1/L2 hits/misses + % friendly/averse
#                                        vs pares de warmup, MAIS uma coluna
#                                        de status (OK/FALHOU) reportada pelo
#                                        proprio testbench.
#
# Uso:
#   python parse_existing_benchmarks.py
# =============================================================================

import csv
import re
from pathlib import Path

try:
    import matplotlib.pyplot as plt
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False

LOADS = [1000, 3000, 5000, 10000, 30000, 50000, 100000, 300000, 500000]


def format_load(n):
    """1000 -> '1K', 500000 -> '500K' (mesmo formato usado nos slides)."""
    if n >= 1000:
        return f"{n // 1000}K"
    return str(n)

# -----------------------------------------------------------------------------
# tb_hawkeye_proof
# -----------------------------------------------------------------------------
RE_L1_FINAL = re.compile(r"L1: hits=(\d+) misses=(\d+) soma=(\d+)")
RE_L2_FINAL = re.compile(r"L2: hits=(\d+) misses=(\d+) soma=(\d+)")


def parse_hawkeye_proof(path):
    if not Path(path).exists():
        print(f"[aviso] nao encontrado: {path}")
        return None

    text = Path(path).read_text(encoding="utf-8", errors="ignore")

    idx = text.rfind("RESULTADO FINAL HAWKEYE PROOF")
    if idx == -1:
        print(f"[aviso] bloco final nao encontrado em {path}")
        return None

    tail = text[idx:]

    m_l1 = RE_L1_FINAL.search(tail)
    m_l2 = RE_L2_FINAL.search(tail)

    if not (m_l1 and m_l2):
        print(f"[aviso] nao consegui extrair L1/L2 finais de {path}")
        return None

    l1_hits, l1_misses = int(m_l1.group(1)), int(m_l1.group(2))
    l2_hits, l2_misses = int(m_l2.group(1)), int(m_l2.group(2))

    hr_l1 = 100.0 * l1_hits / (l1_hits + l1_misses) if (l1_hits + l1_misses) else 0.0
    hr_l2 = 100.0 * l2_hits / (l2_hits + l2_misses) if (l2_hits + l2_misses) else 0.0

    status = "OK" if "[OK] Teste Hawkeye Proof terminou sem erros estruturais." in text else "VER_LOG"

    return {
        "l1_hits": l1_hits, "l1_misses": l1_misses, "hr_l1_pct": round(hr_l1, 2),
        "l2_hits": l2_hits, "l2_misses": l2_misses, "hr_l2_pct": round(hr_l2, 2),
        "status": status,
    }


# -----------------------------------------------------------------------------
# tb_cache_final_integrated_proof
# -----------------------------------------------------------------------------
RE_L1_TOTAL   = re.compile(r"L1 total: hits=(\d+) misses=(\d+) soma=(\d+)")
RE_L2_TOTAL   = re.compile(r"L2 total: hits=(\d+) misses=(\d+) soma=(\d+)")
RE_PRED_VALID = re.compile(r"prediction_valid=(\d+) friendly=(\d+) averse=(\d+)")
RE_FALHOU     = re.compile(r"\[FALHOU\].*terminou com (\d+) erro")


def parse_final_proof(path):
    if not Path(path).exists():
        print(f"[aviso] nao encontrado: {path}")
        return None

    text = Path(path).read_text(encoding="utf-8", errors="ignore")

    idx = text.rfind("RESULTADO FINAL - CACHE FINAL INTEGRATED PROOF")
    if idx == -1:
        print(f"[aviso] bloco final nao encontrado em {path}")
        return None

    tail = text[idx:]

    m_l1 = RE_L1_TOTAL.search(tail)
    m_l2 = RE_L2_TOTAL.search(tail)
    m_pv = RE_PRED_VALID.search(tail)

    if not (m_l1 and m_l2 and m_pv):
        print(f"[aviso] nao consegui extrair todos os campos de {path}")
        return None

    l1_hits, l1_misses = int(m_l1.group(1)), int(m_l1.group(2))
    l2_hits, l2_misses = int(m_l2.group(1)), int(m_l2.group(2))
    valid, friendly, averse = int(m_pv.group(1)), int(m_pv.group(2)), int(m_pv.group(3))

    hr_l1 = 100.0 * l1_hits / (l1_hits + l1_misses) if (l1_hits + l1_misses) else 0.0
    hr_l2 = 100.0 * l2_hits / (l2_hits + l2_misses) if (l2_hits + l2_misses) else 0.0
    pct_friendly = 100.0 * friendly / valid if valid else 0.0
    pct_averse   = 100.0 * averse   / valid if valid else 0.0

    m_falhou = RE_FALHOU.search(text)
    status = f"FALHOU ({m_falhou.group(1)} erros)" if m_falhou else "OK"

    # Mesmo modelo de custo usado nos benchmarks novos: L1=1, L2=10, RAM=100 ciclos.
    cost_model_cycles = (l1_hits * 1) + (l2_hits * 10) + (l2_misses * 100)
    total_requests = l1_hits + l1_misses

    return {
        "total_requests": total_requests,
        "l1_hits": l1_hits, "l1_misses": l1_misses, "hr_l1_pct": round(hr_l1, 2),
        "l2_hits": l2_hits, "l2_misses": l2_misses, "hr_l2_pct": round(hr_l2, 2),
        "prediction_valid": valid, "friendly": friendly, "averse": averse,
        "friendly_pct": round(pct_friendly, 2), "averse_pct": round(pct_averse, 2),
        "cost_model_cycles": cost_model_cycles,
        "status": status,
    }


def plot_hawkeye_proof(rows):
    if not HAS_MATPLOTLIB:
        print("[aviso] matplotlib nao instalado - pulei a geracao do PNG. "
              "Rode: pip install matplotlib")
        return
    if len(rows) < 2:
        print("[aviso] menos de 2 pontos - grafico de tb_hawkeye_proof ficaria "
              "pouco informativo, mas vou gerar mesmo assim.")

    x_labels = [format_load(r["total_accesses"]) for r in rows]
    x_pos    = list(range(len(rows)))
    hr_l2    = [r["hr_l2_pct"] for r in rows]
    miss_l2  = [100.0 - v for v in hr_l2]

    fig, ax = plt.subplots(figsize=(9, 5))
    ax.plot(x_pos, hr_l2, marker="o", color="#1f77b4", label="Taxa de hit da L2")
    ax.plot(x_pos, miss_l2, marker="o", color="#ff7f0e", label="Taxa de miss da L2")

    for xi, yi in zip(x_pos, hr_l2):
        ax.annotate(f"{yi:.2f}%", (xi, yi), textcoords="offset points",
                     xytext=(0, 8), ha="center", fontsize=8)
    for xi, yi in zip(x_pos, miss_l2):
        ax.annotate(f"{yi:.2f}%", (xi, yi), textcoords="offset points",
                     xytext=(0, -14), ha="center", fontsize=8)

    ax.set_xticks(x_pos)
    ax.set_xticklabels(x_labels)
    ax.set_xlabel("Quantidade total de acessos")
    ax.set_ylabel("Taxa sobre os acessos a L2 (%)")
    ax.set_title("Taxas de hit e miss da cache L2")
    ax.legend()
    ax.grid(True, alpha=0.3)

    fig.tight_layout()
    fig.savefig("hawkeye_proof_hr_l2.png", dpi=200)
    plt.close(fig)
    print("[ok] hawkeye_proof_hr_l2.png gerado")


def plot_final_proof(rows):
    if not HAS_MATPLOTLIB:
        print("[aviso] matplotlib nao instalado - pulei a geracao do PNG. "
              "Rode: pip install matplotlib")
        return
    if len(rows) < 2:
        print("[aviso] menos de 2 pontos - grafico de tb_cache_final_integrated_proof "
              "ficaria pouco informativo, mas vou gerar mesmo assim.")

    x_labels = [format_load(r["warmup_pairs"]) for r in rows]
    x_pos     = list(range(len(rows)))
    friendly  = [r["friendly_pct"] for r in rows]
    averse    = [r["averse_pct"] for r in rows]

    fig, ax = plt.subplots(figsize=(9, 5))
    ax.plot(x_pos, friendly, marker="o", color="#1f77b4", label="Friendly")
    ax.plot(x_pos, averse, marker="o", color="#ff7f0e", label="Averse")

    for xi, yi in zip(x_pos, friendly):
        ax.annotate(f"{yi:.1f}%", (xi, yi), textcoords="offset points",
                     xytext=(0, 8), ha="center", fontsize=8)
    for xi, yi in zip(x_pos, averse):
        ax.annotate(f"{yi:.1f}%", (xi, yi), textcoords="offset points",
                     xytext=(0, -14), ha="center", fontsize=8)

    ax.set_xticks(x_pos)
    ax.set_xticklabels(x_labels)
    ax.set_xlabel("Quantidade de pares no warmup")
    ax.set_ylabel("Percentual das predicoes validas (%)")
    ax.set_title("Evolucao das classificacoes Friendly e Averse")
    ax.legend()
    ax.grid(True, alpha=0.3)

    fig.tight_layout()
    fig.savefig("final_proof_friendly_averse.png", dpi=200)
    plt.close(fig)
    print("[ok] final_proof_friendly_averse.png gerado")


def render_table_png(headers, rows, title, filename, col_widths=None):
    """Renderiza uma tabela (lista de headers + lista de linhas) como PNG,
    com cabecalho destacado."""
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


def fmt_pt(v):
    """Formata numero com virgula decimal (padrao pt-BR)."""
    return f"{v:.2f}".replace(".", ",")


def write_latex_table_hawkeye(rows):
    """Gera tabela_hawkeye_proof.tex - HR/MR-L2 vs total de acessos, com
    observacao automatica indicando se a taxa ja estabilizou."""
    lines = []
    lines.append("% Gerado automaticamente por parse_existing_benchmarks.py - nao editar a mao.")
    lines.append("% Inclua no documento com \\input{tabela_hawkeye_proof.tex}")
    lines.append("\\begin{table}[h]")
    lines.append("\\centering")
    lines.append("\\caption{Taxas de acerto e falta da L2 (\\textit{tb\\_hawkeye\\_proof}) "
                  "em funcao da quantidade total de acessos.}")
    lines.append("\\label{tab:hawkeye-proof}")
    lines.append("\\begin{tabular}{lcccl}")
    lines.append("\\hline")
    lines.append("\\textbf{Acessos} & \\textbf{HR-L2 (\\%)} & \\textbf{MR-L2 (\\%)} & "
                  "\\textbf{Status} & \\textbf{Observacao} \\\\")
    lines.append("\\hline")

    prev_hr = None
    png_rows = []
    for r in rows:
        hr_l2 = r["hr_l2_pct"]
        mr_l2 = 100.0 - hr_l2

        if prev_hr is None:
            obs = "Ponto inicial"
        elif abs(hr_l2 - prev_hr) < 0.1:
            obs = "Estabilizado"
        else:
            obs = "Ainda variando"
        prev_hr = hr_l2

        lines.append(f"{format_load(r['total_accesses'])} & {fmt_pt(hr_l2)} & "
                      f"{fmt_pt(mr_l2)} & {r['status']} & {obs} \\\\")
        png_rows.append([format_load(r["total_accesses"]), fmt_pt(hr_l2),
                          fmt_pt(mr_l2), r["status"], obs])

    lines.append("\\hline")
    lines.append("\\end{tabular}")
    lines.append("\\end{table}")

    with open("tabela_hawkeye_proof.tex", "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print("[ok] tabela_hawkeye_proof.tex gerado")

    render_table_png(
        headers=["Acessos", "HR-L2 (%)", "MR-L2 (%)", "Status", "Observacao"],
        rows=png_rows,
        title="HR/MR-L2 vs quantidade de acessos (tb_hawkeye_proof)",
        filename="tabela_hawkeye_proof.png",
        col_widths=[0.15, 0.15, 0.15, 0.2, 0.35],
    )


def write_latex_table_finalproof(rows):
    """Gera tabela_finalproof.tex - Requisicoes, Friendly/Averse, HR/MR de L1 e
    L2 com contagens de hit/miss, e ciclos, por carga de warmup."""
    lines = []
    lines.append("% Gerado automaticamente por parse_existing_benchmarks.py - nao editar a mao.")
    lines.append("% Inclua no documento com \\input{tabela_finalproof.tex}")
    lines.append("\\begin{table}[h]")
    lines.append("\\centering")
    lines.append("\\caption{Evolucao das classificacoes Friendly/Averse, HR/MR de L1 "
                  "e L2 e ciclos (\\textit{tb\\_cache\\_final\\_integrated\\_proof}) em "
                  "funcao da quantidade de requisicoes processadas.}")
    lines.append("\\label{tab:finalproof}")
    lines.append("\\begin{tabular}{lcccccccccccc}")
    lines.append("\\hline")
    lines.append("\\textbf{Requisicoes} & \\textbf{Friendly (\\%)} & \\textbf{Averse (\\%)} & "
                  "\\textbf{HR-L1 (\\%)} & \\textbf{Hits} & \\textbf{MR-L1 (\\%)} & \\textbf{Miss} & "
                  "\\textbf{HR-L2 (\\%)} & \\textbf{Hits} & \\textbf{MR-L2 (\\%)} & \\textbf{Miss} & "
                  "\\textbf{Ciclos} \\\\")
    lines.append("\\hline")

    def fmt_int(v):
        return f"{v:,}".replace(",", ".")

    png_rows = []
    for r in rows:
        hr_l1 = r["hr_l1_pct"]
        hr_l2 = r["hr_l2_pct"]
        mr_l1 = 100.0 - hr_l1
        mr_l2 = 100.0 - hr_l2

        row_vals = [
            fmt_int(r["total_requests"]), fmt_pt(r["friendly_pct"]), fmt_pt(r["averse_pct"]),
            fmt_pt(hr_l1), fmt_int(r["l1_hits"]), fmt_pt(mr_l1), fmt_int(r["l1_misses"]),
            fmt_pt(hr_l2), fmt_int(r["l2_hits"]), fmt_pt(mr_l2), fmt_int(r["l2_misses"]),
            fmt_int(r["cost_model_cycles"]),
        ]

        lines.append(" & ".join(row_vals) + " \\\\")
        png_rows.append(row_vals)

    lines.append("\\hline")
    lines.append("\\end{tabular}")
    lines.append("\\end{table}")

    with open("tabela_finalproof.tex", "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print("[ok] tabela_finalproof.tex gerado")

    render_table_png(
        headers=["Requisicoes", "Friendly (%)", "Averse (%)", "HR-L1 (%)", "Hits",
                  "MR-L1 (%)", "Miss", "HR-L2 (%)", "Hits", "MR-L2 (%)", "Miss", "Ciclos"],
        rows=png_rows,
        title="Friendly/Averse, HR/MR e ciclos vs requisicoes (tb_cache_final_integrated_proof)",
        filename="tabela_finalproof.png",
        col_widths=[0.09] * 11 + [0.11],
    )


def main():
    # --- tb_hawkeye_proof ---
    rows = []
    for n in LOADS:
        result = parse_hawkeye_proof(f"log_hawkeyeproof_{n}.txt")
        if result:
            row = {"total_accesses": n}
            row.update(result)
            rows.append(row)

    if rows:
        with open("hawkeye_proof_hr_l2.csv", "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
        print(f"[ok] hawkeye_proof_hr_l2.csv gerado ({len(rows)} pontos)")
        plot_hawkeye_proof(rows)
        write_latex_table_hawkeye(rows)
    else:
        print("[erro] nenhum resultado de tb_hawkeye_proof encontrado")

    # --- tb_cache_final_integrated_proof ---
    rows = []
    for n in LOADS:
        result = parse_final_proof(f"log_finalproof_{n}.txt")
        if result:
            row = {"warmup_pairs": n}
            row.update(result)
            rows.append(row)

    if rows:
        with open("final_proof_friendly_averse.csv", "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
        print(f"[ok] final_proof_friendly_averse.csv gerado ({len(rows)} pontos)")
        plot_final_proof(rows)
        write_latex_table_finalproof(rows)

        only_friendly = [r for r in rows if r["averse_pct"] == 0.0]
        if only_friendly:
            print(f"[ATENCAO] {len(only_friendly)} rodada(s) com averse_pct=0.0 "
                  f"- o preditor pode nao estar sendo treinado corretamente. "
                  f"Confira 'predictor_train/up/down' no log antes de usar esses "
                  f"pontos no grafico Friendly/Averse.")
    else:
        print("[erro] nenhum resultado de tb_cache_final_integrated_proof encontrado")


if __name__ == "__main__":
    main()
