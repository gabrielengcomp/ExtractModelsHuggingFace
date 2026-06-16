#!/usr/bin/env bash
# =============================================================================
# collect_ram.sh — coleta RAM do llama-cli diretamente (sem LIKWID)
# Uso: sudo ./collect_ram.sh [modelo.gguf] [prompt] [n_tokens]
# =============================================================================

LLAMA_CLI="./build/bin/llama-cli"
MODEL="${1:-models/llama-1b/Llama-3.2-1B-Instruct-Q4_K_M.gguf}"
PROMPT="${2:-Escreva um texto longo sobre inteligência artificial.}"
N_TOKENS="${3:-1000}"
OUT_DIR="results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MODEL_NAME=$(basename "$MODEL" .gguf)
RAM_FILE="$OUT_DIR/${MODEL_NAME}_RAM_DIRECT_${TIMESTAMP}.txt"

mkdir -p "$OUT_DIR"

echo "[INFO] Iniciando coleta de RAM para: $MODEL_NAME"
echo "[INFO] Tokens: $N_TOKENS"

# Inicia llama-cli em background
"$LLAMA_CLI" \
    -m "$MODEL" \
    -p "$PROMPT" \
    -n "$N_TOKENS" \
    -t 4 \
    --temp 0 \
    --single-turn \
    > /tmp/llama_output.txt 2>&1 &

LLAMA_PID=$!
echo "[INFO] PID do llama-cli: $LLAMA_PID"

# Monitor de RAM via psutil rastreando o PID diretamente
python3 - "$LLAMA_PID" "$RAM_FILE" "$MODEL_NAME" << 'PYEOF'
import sys, psutil, time

pid      = int(sys.argv[1])
out      = sys.argv[2]
model    = sys.argv[3]
samples  = []
ts_list  = []

try:
    proc = psutil.Process(pid)
except psutil.NoSuchProcess:
    with open(out, 'w') as f:
        f.write("Processo não encontrado\n")
    sys.exit(0)

print(f"[RAM] Monitorando PID {pid}...")

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

with open(out, 'w') as f:
    f.write(f"Modelo:        {model}\n")
    if samples:
        f.write(f"RAM_pico_MB:   {max(samples):.1f}\n")
        f.write(f"RAM_media_MB:  {sum(samples)/len(samples):.1f}\n")
        f.write(f"RAM_min_MB:    {min(samples):.1f}\n")
        f.write(f"amostras:      {len(samples)}\n")
        duracao = ts_list[-1] - ts_list[0] if len(ts_list) > 1 else 0
        f.write(f"duracao_s:     {duracao:.1f}\n")
        f.write("\n# serie temporal (MB a cada 100ms)\n")
        for t, m in zip(ts_list, samples):
            f.write(f"{t - ts_list[0]:.1f}  {m:.1f}\n")
    else:
        f.write("Nenhuma amostra coletada.\n")

print(f"[RAM] Salvo em: {out}")
PYEOF

wait $LLAMA_PID 2>/dev/null

echo ""
echo "[INFO] === RESULTADO ==="
cat "$RAM_FILE" | head -10
echo ""
echo "[INFO] Output completo do modelo salvo em /tmp/llama_output.txt"
