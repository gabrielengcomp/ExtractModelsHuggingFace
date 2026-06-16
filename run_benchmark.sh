#!/usr/bin/env bash
# =============================================================================
# run_benchmark.sh
# Roda llama.cpp com coleta de métricas LIKWID (CACHE, MEM, CLOCK)
# Uso: ./run_benchmark.sh [modelo.gguf] [prompt] [n_tokens]
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configurações — ajuste conforme necessário
# ---------------------------------------------------------------------------
LLAMA_CLI="./build/bin/llama-cli"          # caminho do binário llama.cpp
MODEL="${1:-models/llama-1b/Llama-3.2-1B-Instruct-Q4_K_M.gguf}"
PROMPT="${2:-Explique o que é inteligência artificial em 3 frases.}"
N_TOKENS="${3:-100}"
CORES="0-3"                                 # núcleos do i5 (4 P-cores físicos)
OUT_DIR="results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MODEL_NAME=$(basename "$MODEL" .gguf)

# ---------------------------------------------------------------------------
# Cores no terminal
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------------------------------------------------------------------------
# Pré-verificações
# ---------------------------------------------------------------------------
info "Verificando dependências..."
command -v likwid-perfctr &>/dev/null || error "likwid-perfctr não encontrado. Instale: sudo apt install likwid"
[[ -f "$LLAMA_CLI" ]]               || error "Binário não encontrado: $LLAMA_CLI  →  compile o llama.cpp primeiro"
[[ -f "$MODEL" ]]                   || error "Modelo não encontrado: $MODEL"

mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------------------
# Fix de permissão MSR (tenta automaticamente)
# ---------------------------------------------------------------------------
PARANOID=$(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null || echo "99")
if [[ "$PARANOID" -gt 1 ]]; then
    warn "perf_event_paranoid=$PARANOID — tentando corrigir (requer sudo)..."
    sudo sh -c 'echo 1 > /proc/sys/kernel/perf_event_paranoid' \
        && info "perf_event_paranoid ajustado para 1." \
        || warn "Não foi possível ajustar. Tentando rodar com sudo..."
    USE_SUDO="sudo"
else
    USE_SUDO=""
fi

# ---------------------------------------------------------------------------
# Argumentos comuns do llama-cli
# ---------------------------------------------------------------------------
LLAMA_ARGS=(
    -m "$MODEL"
    -p "$PROMPT"
    -n "$N_TOKENS"
    -t 4          # threads = número de P-cores
    --temp 0      # determinístico (reproduzível para benchmark)
)

# ---------------------------------------------------------------------------
# Função: rodar um grupo LIKWID e salvar output
# ---------------------------------------------------------------------------
run_group() {
    local GROUP="$1"
    local OUT_FILE="$OUT_DIR/${MODEL_NAME}_${GROUP}_${TIMESTAMP}.txt"

    info "Coletando grupo: ${YELLOW}${GROUP}${NC}"
    echo "# Modelo: $MODEL_NAME | Grupo: $GROUP | Data: $(date)" > "$OUT_FILE"
    echo "# Prompt: $PROMPT"                                      >> "$OUT_FILE"
    echo "# Tokens gerados: $N_TOKENS"                           >> "$OUT_FILE"
    echo "# ---"                                                  >> "$OUT_FILE"

    $USE_SUDO likwid-perfctr \
        -C "$CORES" \
        -g "$GROUP" \
        "$LLAMA_CLI" "${LLAMA_ARGS[@]}" \
        2>&1 | tee -a "$OUT_FILE"

    info "Salvo em: ${OUT_FILE}"
    echo ""
}

# ---------------------------------------------------------------------------
# Coleta de métricas de RAM em paralelo (Python / psutil)
# ---------------------------------------------------------------------------
monitor_ram() {
    local OUT_FILE="$OUT_DIR/${MODEL_NAME}_RAM_${TIMESTAMP}.txt"
    python3 - "$OUT_FILE" <<'PYEOF'
import sys, psutil, time

out = sys.argv[1]
samples = []

# Aguarda o processo llama-cli aparecer (busca por nome e cmdline)
deadline = time.time() + 60
proc = None
while time.time() < deadline:
    for p in psutil.process_iter(['name', 'cmdline', 'pid']):
        try:
            name = p.info['name'] or ''
            cmd  = ' '.join(p.info['cmdline'] or [])
            if 'llama-cli' in name or 'llama-cli' in cmd:
                proc = p
                break
        except Exception:
            pass
    if proc:
        break
    time.sleep(0.2)

if not proc:
    with open(out, 'w') as f:
        f.write("RAM_MONITOR: processo llama-cli nao encontrado no timeout de 60s\n")
    sys.exit(0)

# Coleta amostras enquanto o processo existe
while True:
    try:
        if not proc.is_running() or proc.status() == psutil.STATUS_ZOMBIE:
            break
        mem_mb = proc.memory_info().rss / 1e6
        samples.append(mem_mb)
    except (psutil.NoSuchProcess, psutil.AccessDenied):
        break
    time.sleep(0.1)

with open(out, 'w') as f:
    if samples:
        f.write(f"RAM_pico_MB:   {max(samples):.1f}\n")
        f.write(f"RAM_media_MB:  {sum(samples)/len(samples):.1f}\n")
        f.write(f"RAM_min_MB:    {min(samples):.1f}\n")
        f.write(f"amostras:      {len(samples)}\n")
    else:
        f.write("Nenhuma amostra coletada.\n")
PYEOF
}

# ---------------------------------------------------------------------------
# Execução principal
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  LLM Benchmark com LIKWID"
echo "  Modelo : $MODEL_NAME"
echo "  Tokens : $N_TOKENS"
echo "  Núcleos: $CORES"
echo "============================================================"
echo ""

# Inicia monitor de RAM em segundo plano
monitor_ram &
RAM_PID=$!

# Roda cada grupo de métricas (grupos disponíveis no Tigerlake/TGL)
run_group "FLOPS_DP"  # operações de ponto flutuante double precision
run_group "FLOPS_SP"  # operações de ponto flutuante single precision
run_group "BRANCH"    # branch prediction — eficiência do pipeline
run_group "DATA"      # acessos a memória (loads/stores)

# Aguarda monitor de RAM terminar
wait "$RAM_PID" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Resumo final
# ---------------------------------------------------------------------------
echo ""
info "=== COLETA CONCLUÍDA ==="
echo ""
echo "Arquivos gerados em: ./$OUT_DIR/"
ls -lh "$OUT_DIR/${MODEL_NAME}"*"${TIMESTAMP}"* 2>/dev/null

# Exibe RAM coletada
RAM_FILE="$OUT_DIR/${MODEL_NAME}_RAM_${TIMESTAMP}.txt"
if [[ -f "$RAM_FILE" ]]; then
    echo ""
    info "Uso de RAM:"
    cat "$RAM_FILE"
fi

echo ""
info "Para comparar dois modelos, rode:"
echo "  ./run_benchmark.sh models/llama-1b/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
echo "  ./run_benchmark.sh models/llama-3b/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
echo ""
info "Para gerar gráficos dos resultados:"
echo "  python3 plot_results.py results/"
