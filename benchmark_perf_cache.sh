#!/usr/bin/env bash
# =============================================================================
# benchmark_perf_cache.sh
# Roda perf stat 5x para Llama 1B e Qwen 1.5B (prompt medio)
# Coleta: instrucoes, ciclos, cache references/misses, L1/L2/L3 hits e misses
# Gera: results/perf_cache/perf_summary.csv + analise estatistica
# Uso: sudo ./benchmark_perf_cache.sh
# =============================================================================

set -euo pipefail

LLAMA_CLI="./build/bin/llama-cli"
OUT_DIR="results/perf_cache"
CSV="$OUT_DIR/perf_summary.csv"
N_TOKENS=1000
N_REPS=5
PROMPT="Explique o que e aprendizado de maquina em 3 paragrafos."

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
section() { echo -e "\n${CYAN}==========================================${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}==========================================${NC}"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }

# ---------------------------------------------------------------------------
# Modelos
# ---------------------------------------------------------------------------
declare -A MODELS
MODELS["llama-1b"]="models/llama-1b/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
MODELS["qwen-1.5b"]="models/qwen-1.5b/qwen2.5-1.5b-instruct-q4_k_m.gguf"
MODEL_ORDER=("llama-1b" "qwen-1.5b")

# ---------------------------------------------------------------------------
# Verificacoes
# ---------------------------------------------------------------------------
command -v perf  &>/dev/null || { echo "perf nao encontrado."; exit 1; }
command -v python3 &>/dev/null || { echo "python3 nao encontrado."; exit 1; }
[[ -f "$LLAMA_CLI" ]] || { echo "llama-cli nao encontrado."; exit 1; }

mkdir -p "$OUT_DIR"

# Eventos perf
EVENTS="instructions,cycles,cache-references,cache-misses,\
mem_load_retired.l1_hit,mem_load_retired.l1_miss,\
mem_load_retired.l2_hit,mem_load_retired.l2_miss,\
mem_load_retired.l3_hit,mem_load_retired.l3_miss"

# ---------------------------------------------------------------------------
# CSV cabecalho
# ---------------------------------------------------------------------------
echo "modelo,repeticao,instructions,cycles,cache_references,cache_misses,\
l1_hit,l1_miss,l2_hit,l2_miss,l3_hit,l3_miss,\
ipc,cache_miss_rate_pct" > "$CSV"

# ---------------------------------------------------------------------------
# Funcao: extrair valor numerico do output do perf stat
# Formato: "   1.234.567      instructions"
# ---------------------------------------------------------------------------
extract_perf() {
    local file="$1"
    local event="$2"
    # Remove pontos de milhar e extrai o numero da linha do evento
    grep -w "$event" "$file" 2>/dev/null \
        | grep -oP '^\s+\K[\d\.,]+' \
        | head -1 \
        | tr -d '.' \
        | tr ',' '.' \
        || echo "0"
}

# ---------------------------------------------------------------------------
# Loop principal
# ---------------------------------------------------------------------------
TOTAL=$(( ${#MODEL_ORDER[@]} * N_REPS ))
COUNT=0

for model_key in "${MODEL_ORDER[@]}"; do
    MODEL_PATH="${MODELS[$model_key]}"
    [[ -f "$MODEL_PATH" ]] || { warn "Modelo nao encontrado: $MODEL_PATH"; continue; }

    section "Modelo: $model_key"

    # Warmup antes das 5 repeticoes
    info "Warmup..."
    "$LLAMA_CLI" -m "$MODEL_PATH" -p "Ola" -n 5 -t 4 --temp 0 --single-turn \
        > /dev/null 2>&1 || true

    for rep in $(seq 1 $N_REPS); do
        COUNT=$(( COUNT + 1 ))
        PERF_FILE="$OUT_DIR/${model_key}_rep${rep}_perf.txt"

        info "[$COUNT/$TOTAL] $model_key — repeticao $rep/$N_REPS"

        # Roda perf stat — stderr contem as metricas
        sudo perf stat \
            -e "$EVENTS" \
            "$LLAMA_CLI" \
            -m "$MODEL_PATH" \
            -p "$PROMPT" \
            -n $N_TOKENS \
            -t 4 \
            --temp 0 \
            --single-turn \
            > /tmp/llama_perf_out.txt 2>"$PERF_FILE" || true

        # Extrai cada metrica
        instructions=$(extract_perf "$PERF_FILE" "instructions")
        cycles=$(extract_perf "$PERF_FILE" "cycles")
        cache_ref=$(extract_perf "$PERF_FILE" "cache-references")
        cache_miss=$(extract_perf "$PERF_FILE" "cache-misses")
        l1_hit=$(extract_perf "$PERF_FILE" "mem_load_retired.l1_hit")
        l1_miss=$(extract_perf "$PERF_FILE" "mem_load_retired.l1_miss")
        l2_hit=$(extract_perf "$PERF_FILE" "mem_load_retired.l2_hit")
        l2_miss=$(extract_perf "$PERF_FILE" "mem_load_retired.l2_miss")
        l3_hit=$(extract_perf "$PERF_FILE" "mem_load_retired.l3_hit")
        l3_miss=$(extract_perf "$PERF_FILE" "mem_load_retired.l3_miss")

        # IPC e cache miss rate calculados via python
        read ipc cache_miss_rate <<< $(python3 - "$instructions" "$cycles" "$cache_ref" "$cache_miss" << 'PYEOF'
import sys
instr = float(sys.argv[1]) if sys.argv[1] != '0' else 0
cyc   = float(sys.argv[2]) if sys.argv[2] != '0' else 0
cref  = float(sys.argv[3]) if sys.argv[3] != '0' else 0
cmiss = float(sys.argv[4]) if sys.argv[4] != '0' else 0
ipc  = instr / cyc  if cyc  > 0 else 0
cmr  = cmiss / cref * 100 if cref > 0 else 0
print(f"{ipc:.4f} {cmr:.4f}")
PYEOF
)

        echo "$model_key,$rep,$instructions,$cycles,$cache_ref,$cache_miss,\
$l1_hit,$l1_miss,$l2_hit,$l2_miss,$l3_hit,$l3_miss,\
$ipc,$cache_miss_rate" >> "$CSV"

        info "  IPC=$ipc | cache_miss_rate=${cache_miss_rate}% | L1_hit=$l1_hit | L3_miss=$l3_miss"
        echo ""
    done
done

# ---------------------------------------------------------------------------
# Analise estatistica via Python
# ---------------------------------------------------------------------------
section "ANALISE ESTATISTICA"

python3 - "$CSV" << 'PYEOF'
import csv, sys, statistics, os
from collections import defaultdict

path = sys.argv[1]
with open(path) as f:
    rows = list(csv.DictReader(f))

METRICS = [
    "instructions", "cycles", "cache_references", "cache_misses",
    "l1_hit", "l1_miss", "l2_hit", "l2_miss", "l3_hit", "l3_miss",
    "ipc", "cache_miss_rate_pct"
]

LABELS = {
    "instructions":       "Instructions",
    "cycles":             "Cycles",
    "cache_references":   "Cache References",
    "cache_misses":       "Cache Misses",
    "l1_hit":             "L1 Hit",
    "l1_miss":            "L1 Miss",
    "l2_hit":             "L2 Hit",
    "l2_miss":            "L2 Miss",
    "l3_hit":             "L3 Hit",
    "l3_miss":            "L3 Miss",
    "ipc":                "IPC",
    "cache_miss_rate_pct":"Cache Miss Rate (%)",
}

groups = defaultdict(list)
for row in rows:
    groups[row["modelo"]].append(row)

out_csv = path.replace("perf_summary.csv", "perf_stats.csv")
stat_rows = []
fieldnames = ["modelo"] + \
             [f"{m}_mean" for m in METRICS] + \
             [f"{m}_std"  for m in METRICS] + \
             [f"{m}_cv"   for m in METRICS]

print(f"\n{'='*72}")
print(f"{'Metrica':<22} {'llama-1b':>20} {'qwen-1.5b':>20}")
print(f"{'':22} {'media ± std':>20} {'media ± std':>20}")
print(f"{'='*72}")

model_stats = {}
for model, reps in groups.items():
    stats = {}
    for m in METRICS:
        vals = []
        for r in reps:
            try:
                v = float(r[m])
                if v > 0:
                    vals.append(v)
            except:
                pass
        mean = statistics.mean(vals) if vals else 0
        std  = statistics.stdev(vals) if len(vals) > 1 else 0
        cv   = std / mean * 100 if mean > 0 else 0
        stats[m] = (mean, std, cv)
    model_stats[model] = stats

for m in METRICS:
    row_out = {"modelo": "comparativo"}
    vals_by_model = []
    for model in ["llama-1b", "qwen-1.5b"]:
        if model not in model_stats:
            vals_by_model.append("N/A")
            continue
        mean, std, cv = model_stats[model][m]
        if m in ("ipc", "cache_miss_rate_pct"):
            fmt = f"{mean:.3f} ±{std:.3f} (CV:{cv:.1f}%)"
        elif mean > 1e9:
            fmt = f"{mean/1e9:.2f}G ±{std/1e9:.2f}G"
        elif mean > 1e6:
            fmt = f"{mean/1e6:.2f}M ±{std/1e6:.2f}M"
        else:
            fmt = f"{mean:.1f} ±{std:.1f}"
        vals_by_model.append(fmt)
    print(f"{LABELS[m]:<22} {vals_by_model[0]:>20} {vals_by_model[1]:>20}")

print(f"{'='*72}\n")

# Gera CSV de stats
for model in ["llama-1b", "qwen-1.5b"]:
    if model not in model_stats:
        continue
    row_out = {"modelo": model}
    for m in METRICS:
        mean, std, cv = model_stats[model][m]
        row_out[f"{m}_mean"] = round(mean, 4)
        row_out[f"{m}_std"]  = round(std,  4)
        row_out[f"{m}_cv"]   = round(cv,   2)
    stat_rows.append(row_out)

with open(out_csv, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(stat_rows)
print(f"CSV de estatisticas salvo em: {out_csv}")

# Alertas
print("\n--- Alertas CV > 10% ---")
found = False
for model, stats in model_stats.items():
    for m, (mean, std, cv) in stats.items():
        if cv > 10:
            print(f"  {model} | {LABELS[m]}: CV={cv:.1f}%")
            found = True
if not found:
    print("  Nenhum alerta.")
PYEOF

section "CONCLUIDO"
info "CSV raw:   $CSV"
info "CSV stats: ${OUT_DIR}/perf_stats.csv"
info "Logs perf: ${OUT_DIR}/*_perf.txt"
