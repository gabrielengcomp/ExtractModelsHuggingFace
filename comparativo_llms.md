# Análise Empírica Comparativa — Llama 3.2 1B vs 3B
**Hardware:** Intel Core i5-1135G7 (Tigerlake) @ 2.40 GHz · 16 GB RAM  
**Ferramenta:** LIKWID 5.x + psutil  
**Prompt:** "Escreva um texto longo sobre inteligência artificial."  
**Tokens gerados:** 1000  
**Quantização:** Q4_K_M (GGUF via llama.cpp)

---

## 1. Uso de Memória RAM

| Métrica | Llama 3.2 1B | Llama 3.2 3B |
|---|---|---|
| RAM pico | 5.656 MB (~5,5 GB) | 11.877 MB (~11,6 GB) |
| RAM média | 5.337 MB | 5.824 MB¹ |
| RAM mínima | 26 MB | 18 MB |
| Amostras coletadas | 239 | 68 |
| Duração monitorada | 23,9 s | 6,7 s (OOM) |

> ¹ O modelo 3B foi encerrado pelo sistema operacional (OOM killer) antes de concluir a geração — a RAM média reflete apenas a fase de carregamento.

**Observação:** O modelo 3B consome ~2,1× mais RAM que o 1B. Com 16 GB de RAM e outros processos ativos, o 3B ultrapassa o limite disponível e é terminado pelo kernel. O 1B completa a geração com folga (~10 GB livres).

---

## 2. Desempenho de Geração (tokens/s)

| Métrica | Llama 3.2 1B | Llama 3.2 3B |
|---|---|---|
| Prompt processing | 236,6 t/s | N/A (encerrado) |
| Geração de tokens | **38,3 t/s** | N/A (encerrado) |

O 1B gerou tokens a 38,3 t/s — velocidade confortável para uso interativo em CPU. O 3B não concluiu a geração devido ao OOM.

---

## 3. Métricas LIKWID — FLOPS_DP (grupo de ponto flutuante)

### 3.1 CPI — Cycles Per Instruction

CPI mede quantos ciclos de CPU são necessários por instrução. Valores baixos indicam execução eficiente; valores altos indicam que o processador está ocioso esperando dados (tipicamente da memória).

| Thread | 1B (CPI) | 3B (CPI) |
|---|---|---|
| Thread 0 (principal) | 0,683 | 0,669 |
| Thread 1 | 7,486 | 6,627 |
| Thread 2 | 3,379 | 3,191 |
| Thread 3 | — | — |
| **Média (STAT)** | **13,52** | **12,77** |

O CPI médio alto em ambos os modelos é esperado — as threads secundárias ficam ociosas na maior parte do tempo, inflando a média. O thread principal opera com CPI ~0,68–0,67, indicando boa eficiência de execução no core ativo.

O 3B apresenta CPI médio ligeiramente menor (12,77 vs 13,52), sugerindo uso um pouco mais equilibrado das threads.

---

### 3.2 MFLOP/s — Operações de Ponto Flutuante

| Métrica | 1B | 3B |
|---|---|---|
| DP MFLOP/s (thread principal) | 31,45 | 33,13 |
| DP MFLOP/s (total — STAT) | 31,46 | 33,13 |
| AVX MFLOP/s | 0 | 0 |
| AVX512 MFLOP/s | 0 | 0 |
| Vectorization ratio | **0%** | **0%** |

Ambos os modelos operam **exclusivamente em modo escalar** — nenhuma instrução vetorial (AVX, AVX512) é utilizada. Isso é comportamento esperado do llama.cpp com quantização Q4_K_M em CPU, que descompacta pesos de 4 bits para operações escalares em tempo de execução.

O 3B apresenta MFLOP/s ligeiramente maior (33,13 vs 31,45), mas a diferença é pequena, indicando que o tamanho do modelo não altera significativamente a taxa de operações por segundo — o gargalo é memória, não computação.

---

### 3.3 Clock Real (MHz)

| Thread | 1B (MHz) | 3B (MHz) |
|---|---|---|
| Thread 0 | 3.779 | 3.789 |
| Thread 1 | 2.352 | 2.190 |
| Thread 2 | 3.348 | 3.174 |
| **Média** | **3.160** | **3.051** |

O i5-1135G7 (base 2,4 GHz) ativou Turbo Boost no core principal, atingindo ~3,78–3,79 GHz em ambos os modelos. Isso mostra que o hardware foi aproveitado ao máximo no core ativo.

---

### 3.4 Runtime

| Métrica | 1B | 3B |
|---|---|---|
| Runtime (RDTSC) | 0,0176 s | 0,0167 s |
| Runtime unhalted | 0,0107 s | 0,0109 s |

O runtime medido pelo LIKWID é curto porque a medição captura apenas uma janela de execução (não a inferência completa). A duração real de geração foi de ~23,9s para o 1B (medida pelo psutil).

---

## 4. Análise do Gargalo Computacional

| Indicador | Conclusão |
|---|---|
| Vectorization ratio = 0% | Nenhum uso de AVX/AVX512 — execução escalar pura |
| CPI alto nas threads secundárias | Threads ociosas esperando trabalho do thread principal |
| MFLOP/s baixo (~31–33) | Throughput de FP baixo — gargalo é largura de banda de memória |
| Turbo Boost ativo (~3,78 GHz) | CPU não é o limitante — RAM é o bottleneck |
| RAM 1B: 5,5 GB · 3B: 11,6 GB | Modelos maiores são limitados pela capacidade de RAM disponível |

O perfil de execução de ambos os modelos é **memory-bound**: a CPU passa a maior parte do tempo buscando pesos da RAM, não realizando cálculos. Isso é característico de inferência LLM em CPU com quantização de baixo bit.

---

## 5. Resumo Comparativo

| Métrica | Llama 3.2 1B | Llama 3.2 3B | Vantagem |
|---|---|---|---|
| RAM pico | ~5,5 GB | ~11,6 GB | **1B** |
| Tokens/s (geração) | 38,3 | N/A | **1B** |
| CPI médio | 13,52 | 12,77 | **3B** (menor) |
| MFLOP/s | 31,45 | 33,13 | **3B** (maior) |
| Clock pico | 3.779 MHz | 3.789 MHz | Empate |
| Vectorization | 0% | 0% | Empate |
| Viabilidade 16 GB RAM | ✅ Sim | ❌ OOM | **1B** |

---

## 6. Conclusões

1. **O Llama 3.2 1B é a escolha viável para o hardware disponível.** Com ~5,5 GB de RAM e 38,3 t/s de geração, ele roda confortavelmente no i5-1135G7 com 16 GB de RAM.

2. **O Llama 3.2 3B excede a memória disponível** ao gerar tokens (11,6 GB apenas para o modelo + sistema operacional), sendo encerrado pelo OOM killer antes de concluir.

3. **O gargalo dominante é a largura de banda de memória**, não a capacidade de computação. Ambos os modelos têm vectorization ratio de 0% e MFLOP/s baixo, confirmando execução escalar pura em CPU.

4. **O Turbo Boost é aproveitado ao máximo** — o i5-1135G7 atinge ~3,78 GHz no core principal em ambos os casos, indicando que a CPU não está sendo subutilizada, mas sim bloqueada por acesso à memória.

5. **Para melhorar o desempenho** nesse hardware, as opções seriam: usar modelos com quantização mais agressiva (Q2_K ou Q3_K_M) para reduzir uso de RAM e aumentar tokens/s, ou utilizar GPU offload parcial caso haja GPU discreta disponível.

---

## 7. Ambiente e Metodologia

| Item | Detalhe |
|---|---|
| CPU | Intel Core i5-1135G7 (Tigerlake, 4 P-cores) |
| RAM | 16 GB |
| OS | Linux (Ubuntu) |
| llama.cpp | build b9660-7dad2f1a1 |
| LIKWID | Grupo FLOPS_DP (único disponível para TGL) |
| Monitor RAM | psutil, intervalo 100ms, PID direto |
| Modelos | meta-llama/Llama-3.2-1B-Instruct e 3B-Instruct (GGUF Q4_K_M via bartowski) |
| Prompt | "Escreva um texto longo sobre inteligência artificial." |
| Tokens | 1000 (geração) |
| Threads llama.cpp | 4 |
| Temperatura | 0 (determinístico) |
