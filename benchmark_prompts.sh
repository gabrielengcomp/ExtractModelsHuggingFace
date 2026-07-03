#!/usr/bin/env bash
# =============================================================================
# benchmark_prompts.sh
# Roda 3 modelos x 3 niveis de dificuldade de prompt
# Coleta: LIKWID (FLOPS_DP, BRANCH, DATA) + RAM + tokens/s
# Gera: results/benchmark_summary.csv
# Uso: sudo ./benchmark_prompts.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuracoes
# ---------------------------------------------------------------------------
LLAMA_CLI="./build/bin/llama-cli"
OUT_DIR="results/prompt_benchmark"
CSV="$OUT_DIR/benchmark_summary.csv"
N_TOKENS=1000
CORES="0-3"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
section() { echo -e "\n${CYAN}==========================================${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}==========================================${NC}"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------------------------------------------------------------------------
# Modelos
# ---------------------------------------------------------------------------
declare -A MODELS
MODELS["llama-1b"]="models/llama-1b/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
MODELS["qwen-1.5b"]="models/qwen-1.5b/qwen2.5-1.5b-instruct-q4_k_m.gguf"
MODELS["llama-3b"]="models/llama-3b/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
MODEL_ORDER=("llama-1b" "qwen-1.5b" "llama-3b")

# ---------------------------------------------------------------------------
# Prompts por dificuldade
# ---------------------------------------------------------------------------
declare -A PROMPTS
PROMPTS["facil"]="Ola, como vai?"
PROMPTS["medio"]="Explique o que e aprendizado de maquina em 3 paragrafos."
PROMPTS["dificil"]="Compare detalhadamente as arquiteturas Transformer e LSTM, discutindo vantagens, desvantagens, complexidade computacional e casos de uso reais de cada uma."
DIFFICULTY_ORDER=("facil" "medio" "dificil")

# ---------------------------------------------------------------------------
# Pre-verificacoes
# ---------------------------------------------------------------------------
info "Verificando dependencias..."
command -v likwid-perfctr &>/dev/null || error "likwid-perfctr nao encontrado."
[[ -f "$LLAMA_CLI" ]]               || error "Binario nao encontrado: $LLAMA_CLI"
command -v python3 &>/dev/null      || error "python3 nao encontrado."
python3 -c "import psutil" 2>/dev/null || error "psutil nao instalado. Execute: pip install psutil --break-system-packages"

for key in "${MODEL_ORDER[@]}"; do
    [[ -f "${MODELS[$key]}" ]] || warn "Modelo nao encontrado (sera pulado): ${MODELS[$key]}"
done

mkdir -p "$OUT_DIR"

# Ajusta perf_event_paranoid se necessario
PARANOID=$(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null || echo "99")
if [[ "$PARANOID" -gt 1 ]]; then
    sudo sh -c 'echo 0 > /proc/sys/kernel/perf_event_paranoid' 2>/dev/null \
        && info "perf_event_paranoid ajustado para 0." \
        || warn "Nao foi possivel ajustar perf_event_paranoid."
fi

# ---------------------------------------------------------------------------
# CSV - cabecalho
# ---------------------------------------------------------------------------
echo "modelo,dificuldade,prompt_tokens_s,gen_tokens_s,ram_pico_mb,ram_media_mb,duracao_s,cpi_medio,cpi_thread_principal,mflops_total,clock_principal_mhz,vectorization_ratio,runtime_likwid_s,loads_mops,stores_mops,load_store_ratio" > "$CSV"

# ---------------------------------------------------------------------------
# Funcao: extrair tokens/s do output do llama-cli
# ---------------------------------------------------------------------------
extract_tps() {
    local output_file="$1"
    local prompt_tps gen_tps
    # Formato: "[ Prompt: 162,8 t/s | Generation: 31,1 t/s ]" ou sem colchetes
    prompt_tps=$(grep -oP 'Prompt:\s*\K[\d,\.]+(?=\s*t/s)' "$output_file" 2>/dev/null | tr ',' '.' | tail -1 || echo "0")
    gen_tps=$(grep -oP 'Generation:\s*\K[\d,\.]+(?=\s*t/s)' "$output_file" 2>/dev/null | tr ',' '.' | tail -1 || echo "0")
    # fallback: formato alternativo com virgula como separador decimal
    [[ "$prompt_tps" == "0" ]] && prompt_tps=$(grep -oP 'prompt processing.*?\K[0-9,]+(?=\s*tokens per second)' "$output_file" 2>/dev/null | tr ',' '.' | tail -1 || echo "0")
    [[ "$gen_tps" == "0" ]]    && gen_tps=$(grep -oP 'eval time.*?\K[0-9,]+(?=\s*tokens per second)' "$output_file" 2>/dev/null | tr ',' '.' | tail -1 || echo "0")
    echo "$prompt_tps $gen_tps"
}

# ---------------------------------------------------------------------------
# Funcao: extrair metricas do output LIKWID
# ---------------------------------------------------------------------------
extract_likwid() {
    local likwid_file="$1"
    local cpi_avg cpi_t0 mflops clock vr runtime
    # CPI medio (STAT Avg)
    cpi_avg=$(grep -A1 'CPI STAT' "$likwid_file" 2>/dev/null | grep -oP '\|\s+\K[\d\.]+(?=\s*\|$)' | tail -1 || echo "0")
    # CPI thread 0
    cpi_t0=$(grep -P '^\|\s+CPI\s+\|' "$likwid_file" 2>/dev/null | grep -oP '\|\s+\K[\d\.]+' | head -1 || echo "0")
    # MFLOP/s total (STAT Sum)
    mflops=$(grep 'DP \[MFLOP/s\] STAT' "$likwid_file" 2>/dev/null | grep -oP '\|\s+\K[\d\.]+' | head -1 || echo "0")
    # Clock thread 0
    clock=$(grep -P '^\|\s+Clock \[MHz\]\s+\|' "$likwid_file" 2>/dev/null | grep -oP '\|\s+\K[\d\.]+' | head -1 || echo "0")
    # Vectorization ratio thread 0
    vr=$(grep -P '^\|\s+Vectorization ratio\s+\|' "$likwid_file" 2>/dev/null | grep -oP '\|\s+\K[\d\.]+' | head -1 || echo "0")
    # Runtime RDTSC
    runtime=$(grep -P '^\|\s+Runtime \(RDTSC\) \[s\]\s+\|' "$likwid_file" 2>/dev/null | grep -oP '\|\s+\K[\d\.]+' | head -1 || echo "0")
    echo "$cpi_avg $cpi_t0 $mflops $clock $vr $runtime"
}

# ---------------------------------------------------------------------------
# Funcao: coletar RAM diretamente via psutil
# ---------------------------------------------------------------------------
collect_ram() {
    local model_path="$1"
    local prompt="$2"
    local ram_file="$3"

    "$LLAMA_CLI" \
        -m "$model_path" \
        -p "$prompt" \
        -n "$N_TOKENS" \
        -t 4 \
        --temp 0 \
        --single-turn \
        > /tmp/llama_ram_output.txt 2>&1 &

    local pid=$!

    python3 - "$pid" "$ram_file" << 'PYEOF'
import sys, psutil, time

pid     = int(sys.argv[1])
out     = sys.argv[2]
samples = []
ts_list = []

try:
    proc = psutil.Process(pid)
except psutil.NoSuchProcess:
    open(out, 'w').write("0 0 0 0\n")
    sys.exit(0)

while True:
    try:
        if not proc.is_running() or proc.status() == psutil.STATUS_ZOMBIE:
            break
        mem_mb = proc.memory_info().rss / 1e6
        samples.append(mem_mb)
        ts_list.append(time.time())
    except (psutil.NoSuchProcess, psutil.AccessDenied):
        break
    time.sleep(0.1)

duracao = ts_list[-1] - ts_list[0] if len(ts_list) > 1 else 0
with open(out, 'w') as f:
    if samples:
        f.write(f"{max(samples):.1f} {sum(samples)/len(samples):.1f} {duracao:.1f}\n")
    else:
        f.write("0 0 0\n")
PYEOF

    wait "$pid" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Loop principal: modelo x dificuldade
# ---------------------------------------------------------------------------
TOTAL=$(( ${#MODEL_ORDER[@]} * ${#DIFFICULTY_ORDER[@]} ))
COUNT=0

for model_key in "${MODEL_ORDER[@]}"; do
    MODEL_PATH="${MODELS[$model_key]}"

    if [[ ! -f "$MODEL_PATH" ]]; then
        warn "Pulando $model_key - arquivo nao encontrado."
        continue
    fi

    section "Modelo: $model_key"

    for diff in "${DIFFICULTY_ORDER[@]}"; do
        COUNT=$(( COUNT + 1 ))
        PROMPT="${PROMPTS[$diff]}"
        TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        PREFIX="$OUT_DIR/${model_key}_${diff}_${TIMESTAMP}"

        info "[$COUNT/$TOTAL] $model_key x $diff"
        info "Prompt: \"${PROMPT:0:60}...\""

        LIKWID_FILE="${PREFIX}_likwid.txt"
        RAM_FILE="${PREFIX}_ram.txt"
        TPS_FILE="${PREFIX}_tps.txt"

        # --- WARMUP: carrega o modelo na RAM antes de medir ---
        # Roda uma inferencia curta sem medicao para garantir que o modelo
        # ja esta carregado e os dados estao quentes no cache quando o
        # LIKWID comecar a medir. Evita contaminar as metricas com I/O de disco.
        info "  -> Warmup (carregando modelo na RAM)..."
        "$LLAMA_CLI" \
            -m "$MODEL_PATH" \
            -p "Ola" \
            -n 5 \
            -t 4 \
            --temp 0 \
            --single-turn \
            > /dev/null 2>&1 || true

        # --- tokens/s: usa script para capturar output do tty ---
        info "  -> Coletando tokens/s..."
        script -q -c "$LLAMA_CLI -m \"$MODEL_PATH\" -p \"$PROMPT\" -n $N_TOKENS -t 4 --temp 0 --single-turn" "$TPS_FILE" > /dev/null 2>&1 || true
        # remove escape sequences ANSI do arquivo capturado
        sed -i 's/\x1b\[[0-9;]*[mGKHF]//g; s/\r//g' "$TPS_FILE" 2>/dev/null || true

        # --- LIKWID FLOPS_DP (pos-warmup: mede so inferencia quente) ---
        info "  -> Coletando LIKWID (FLOPS_DP)..."
        sudo likwid-perfctr \
            -C "$CORES" \
            -g FLOPS_DP \
            "$LLAMA_CLI" \
            -m "$MODEL_PATH" \
            -p "$PROMPT" \
            -n "$N_TOKENS" \
            -t 4 \
            --temp 0 \
            --single-turn \
            > "$LIKWID_FILE" 2>&1 || true

        # --- LIKWID DATA (loads/stores pos-warmup) ---
        DATA_FILE="${PREFIX}_data.txt"
        info "  -> Coletando LIKWID (DATA)..."
        sudo likwid-perfctr \
            -C "$CORES" \
            -g DATA \
            "$LLAMA_CLI" \
            -m "$MODEL_PATH" \
            -p "$PROMPT" \
            -n "$N_TOKENS" \
            -t 4 \
            --temp 0 \
            --single-turn \
            > "$DATA_FILE" 2>&1 || true

        # --- RAM ---
        info "  -> Coletando RAM..."
        collect_ram "$MODEL_PATH" "$PROMPT" "$RAM_FILE"

        # --- Extracao ---
        read prompt_tps gen_tps <<< $(extract_tps "$TPS_FILE")
        read cpi_avg cpi_t0 mflops clock vr runtime <<< $(extract_likwid "$LIKWID_FILE")
        read ram_pico ram_media duracao_s <<< $(cat "$RAM_FILE" 2>/dev/null || echo "0 0 0")

        # --- Extracao DATA (loads/stores) ---
        # STAT Sum = total de loads/stores nos 4 threads
        loads=$(grep "MEM_INST_RETIRED_ALL_LOADS STAT" "$DATA_FILE" 2>/dev/null | grep -oP "\|\s+\K[0-9e\.\+]+" | head -1 || echo "0")
        stores=$(grep "MEM_INST_RETIRED_ALL_STORES STAT" "$DATA_FILE" 2>/dev/null | grep -oP "\|\s+\K[0-9e\.\+]+" | head -1 || echo "0")
        ratio=$(grep "Load to store ratio STAT" "$DATA_FILE" 2>/dev/null | grep -oP "\|\s+\K[0-9e\.\+]+" | head -1 || echo "0")

        # --- Linha CSV ---
        echo "$model_key,$diff,$prompt_tps,$gen_tps,$ram_pico,$ram_media,$duracao_s,$cpi_avg,$cpi_t0,$mflops,$clock,$vr,$runtime,$loads,$stores,$ratio" >> "$CSV"

        info "  OK gen=${gen_tps} t/s | RAM pico=${ram_pico} MB | CPI=${cpi_avg}"
        echo ""
    done
done

# ---------------------------------------------------------------------------
# Resumo final
# ---------------------------------------------------------------------------
section "BENCHMARK CONCLUIDO"
echo ""
info "CSV gerado em: $CSV"
echo ""
echo "-------------------------------------------------------------------"
column -t -s',' "$CSV"
echo "-------------------------------------------------------------------"
echo ""
info "Para gerar graficos: python3 plot_prompts.py $CSV"
