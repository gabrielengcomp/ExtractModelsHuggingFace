# Análise Estatística do Benchmark — 5 Repetições
**Hardware:** Intel Core i5-1135G7 (Tigerlake) @ 2.40 GHz · 16 GB RAM  
**Modelos:** Llama 3.2 1B · Qwen 2.5 1.5B · Llama 3.2 3B (Q4_K_M GGUF)  
**Repetições:** 5 por combinação modelo × dificuldade  
**Total de execuções:** 45 (3 modelos × 3 níveis × 5 repetições)

---

## 1. Throughput de Geração — tokens/s

| Modelo | Dificuldade | Média | ±StdDev | CV% |
|---|---|---|---|---|
| Llama 3.2 1B | Fácil | 41,60 | ±1,24 | 3,0% |
| Llama 3.2 1B | Médio | 37,24 | ±1,16 | 3,1% |
| Llama 3.2 1B | Difícil | 32,80 | ±0,95 | 2,9% |
| Qwen 2.5 1.5B | Fácil | 33,18 | ±0,62 | 1,9% |
| Qwen 2.5 1.5B | Médio | 29,38 | ±0,42 | 1,4% |
| Qwen 2.5 1.5B | Difícil | 27,64 | ±0,42 | 1,5% |
| Llama 3.2 3B | Fácil | — | — | OOM |
| Llama 3.2 3B | Médio | — | — | OOM |
| Llama 3.2 3B | Difícil | — | — | OOM |

**Observações:**
- CV entre 1,4% e 3,1% — métrica altamente reproduzível
- Queda total do fácil ao difícil: **21,2%** no 1B e **16,7%** no Qwen
- O Llama 1B é consistentemente mais rápido (~8 t/s de vantagem em todos os níveis)

---

## 2. Throughput de Prefill — tokens/s

| Modelo | Dificuldade | Média | ±StdDev | CV% |
|---|---|---|---|---|
| Llama 3.2 1B | Fácil | 218,74 | ±38,17 | 17,4% ⚠️ |
| Llama 3.2 1B | Médio | 190,12 | ±25,70 | 13,5% ⚠️ |
| Llama 3.2 1B | Difícil | 162,96 | ±7,67 | 4,7% |
| Qwen 2.5 1.5B | Fácil | 117,98 | ±6,93 | 5,9% |
| Qwen 2.5 1.5B | Médio | 109,52 | ±5,28 | 4,8% |
| Qwen 2.5 1.5B | Difícil | 109,18 | ±4,39 | 4,0% |
| Llama 3.2 3B | Todos | — | — | OOM |

**Observações:**
- CV alto no 1B fácil/médio (13–17%) causado pelo tamanho reduzido do prompt — poucos tokens de entrada amplificam pequenas variações absolutas de tempo
- No Qwen e no 1B difícil o prefill é estável (CV < 6%)
- Llama 1B processa o contexto de entrada ~2x mais rápido que o Qwen em todos os níveis

---

## 3. Uso de Memória RAM

| Modelo | Dificuldade | Pico (MB) | ±StdDev | CV% |
|---|---|---|---|---|
| Llama 3.2 1B | Fácil | 5.654,72 | ±0,04 | 0,0% |
| Llama 3.2 1B | Médio | 5.656,76 | ±0,09 | 0,0% |
| Llama 3.2 1B | Difícil | 5.659,68 | ±0,08 | 0,0% |
| Qwen 2.5 1.5B | Fácil | 2.754,46 | ±0,05 | 0,0% |
| Qwen 2.5 1.5B | Médio | 2.755,90 | ±0,00 | 0,0% |
| Qwen 2.5 1.5B | Difícil | 2.759,22 | ±0,04 | 0,0% |
| Llama 3.2 3B | Fácil | 13.119,38 | ±19,71 | 0,2% |
| Llama 3.2 3B | Médio | 12.996,76 | ±143,72 | 1,1% |
| Llama 3.2 3B | Difícil | 13.118,08 | ±155,72 | 1,2% |

**Observações:**
- **Métrica mais reproduzível do experimento** — CV de 0,0% no 1B e Qwen
- RAM pico é determinada exclusivamente pelo tamanho do modelo, não pelo prompt
- O 3B excede 12,9 GB em todos os cenários, inviabilizando a execução completa em 16 GB de RAM com sistema operacional ativo
- A leve variação do 3B (CV 0,2–1,2%) é atribuída ao ponto exato em que o OOM killer encerra o processo

---

## 4. Duração da Inferência

| Modelo | Dificuldade | Média (s) | ±StdDev | CV% |
|---|---|---|---|---|
| Llama 3.2 1B | Fácil | 3,76 | ±0,05 | 1,5% |
| Llama 3.2 1B | Médio | 15,28 | ±0,30 | 2,0% |
| Llama 3.2 1B | Difícil | 34,66 | ±0,46 | 1,3% |
| Qwen 2.5 1.5B | Fácil | 2,38 | ±0,13 | 5,5% |
| Qwen 2.5 1.5B | Médio | 14,16 | ±0,19 | 1,4% |
| Qwen 2.5 1.5B | Difícil | 27,94 | ±0,89 | 3,2% |
| Llama 3.2 3B | Fácil | 6,74 | ±0,27 | 4,0% |
| Llama 3.2 3B | Médio | 6,24 | ±0,32 | 5,1% |
| Llama 3.2 3B | Difícil | 6,34 | ±0,34 | 5,3% |

**Observações:**
- CV entre 1,3% e 5,5% — métrica estável e confiável
- Crescimento de duração fácil → difícil: **9,2×** no 1B e **11,7×** no Qwen
- O 3B apresenta duração uniforme (~6,4s) em todos os níveis pois é encerrado pelo OOM antes de gerar tokens suficientes

---

## 5. CPI — Thread Principal

| Modelo | Dificuldade | Média | ±StdDev | CV% |
|---|---|---|---|---|
| Llama 3.2 1B | Fácil | 0,682 | ±0,040 | 5,8% |
| Llama 3.2 1B | Médio | 0,701 | ±0,026 | 3,7% |
| Llama 3.2 1B | Difícil | 0,714 | ±0,082 | 11,5% ⚠️ |
| Qwen 2.5 1.5B | Fácil | 0,668 | ±0,021 | 3,1% |
| Qwen 2.5 1.5B | Médio | 0,698 | ±0,035 | 5,0% |
| Qwen 2.5 1.5B | Difícil | 0,686 | ±0,039 | 5,7% |
| Llama 3.2 3B | Fácil | 0,755 | ±0,118 | 15,7% ⚠️ |
| Llama 3.2 3B | Médio | 0,766 | ±0,059 | 7,6% |
| Llama 3.2 3B | Difícil | 0,776 | ±0,153 | 19,7% ⚠️ |

**Observações:**
- Todos os valores abaixo de 1,0 — pipeline do processador bem aproveitado em todos os casos
- CV alto no 3B (15–20%) e no 1B difícil (11,5%) correlacionado com a variabilidade do clock (Turbo Boost)
- CPI do Qwen é o mais estável (CV < 6% em todos os níveis)

---

## 6. Clock Real — Thread Principal (MHz)

| Modelo | Dificuldade | Média (MHz) | ±StdDev | CV% |
|---|---|---|---|---|
| Llama 3.2 1B | Fácil | 3.520,10 | ±359,25 | 10,2% ⚠️ |
| Llama 3.2 1B | Médio | 3.688,31 | ±181,15 | 4,9% |
| Llama 3.2 1B | Difícil | 3.312,79 | ±607,30 | 18,3% ⚠️ |
| Qwen 2.5 1.5B | Fácil | 3.511,46 | ±619,55 | 17,6% ⚠️ |
| Qwen 2.5 1.5B | Médio | 3.576,64 | ±233,59 | 6,5% |
| Qwen 2.5 1.5B | Difícil | 3.784,00 | ±21,05 | 0,6% |
| Llama 3.2 3B | Fácil | 2.190,53 | ±688,43 | 31,4% ⚠️ |
| Llama 3.2 3B | Médio | 2.325,84 | ±929,90 | 40,0% ⚠️ |
| Llama 3.2 3B | Difícil | 2.416,22 | ±835,56 | 34,6% ⚠️ |

**Observações:**
- **Métrica mais instável do experimento** — CV entre 0,6% e 40,0%
- A variabilidade reflete o comportamento do Turbo Boost do i5-1135G7, que oscila livremente conforme temperatura e carga do sistema
- O LIKWID captura uma janela curta (~14–100ms) que pode coincidir com diferentes estados da rampa de Turbo entre execuções
- **Não recomendada para comparações diretas** sem controle de frequência (ex: `cpupower frequency-set`)
- O 3B apresenta clock sistematicamente mais baixo (~2.300 MHz vs ~3.500 MHz dos outros), indicando throttling por pressão de memória

---

## 7. Resumo de Confiabilidade das Métricas

| Métrica | CV típico | Confiável? | Causa da variabilidade |
|---|---|---|---|
| RAM pico | 0,0–1,2% | ✅ Alta | Determinística |
| gen_tokens_s | 1,4–3,1% | ✅ Alta | Execução estável |
| duracao_s | 1,3–5,5% | ✅ Alta | Leve variação de EOS |
| cpi_thread_principal | 3,1–11,5% | ✅ Moderada (1B/Qwen) | Correlacionado ao clock |
| prompt_tokens_s | 4,0–17,4% | ⚠️ Moderada | Prompt curto amplifica variação |
| clock_principal_mhz | 0,6–40,0% | ❌ Baixa | Turbo Boost não controlado |
| mflops_total | — | ⚠️ Snapshot | Janela LIKWID < 1% da inferência |
| load_store_ratio | 0,0% | ✅ Alta | Estável após warmup |

---

## 8. Alertas de Alta Variabilidade (CV > 10%)

| Modelo | Dificuldade | Métrica | CV% | Causa provável |
|---|---|---|---|---|
| Llama 3.2 1B | Fácil | prompt_tokens_s | 17,4% | Prompt muito curto (~5 tokens) |
| Llama 3.2 1B | Fácil | clock_principal_mhz | 10,2% | Turbo Boost instável |
| Llama 3.2 1B | Médio | prompt_tokens_s | 13,5% | Prompt curto relativo |
| Llama 3.2 1B | Difícil | cpi_thread_principal | 11,5% | Variação de clock |
| Llama 3.2 1B | Difícil | clock_principal_mhz | 18,3% | Turbo Boost instável |
| Qwen 2.5 1.5B | Fácil | clock_principal_mhz | 17,6% | Turbo Boost instável |
| Llama 3.2 3B | Fácil | cpi_thread_principal | 15,7% | Dependência do clock |
| Llama 3.2 3B | Fácil | clock_principal_mhz | 31,4% | Throttling por pressão de memória |
| Llama 3.2 3B | Médio | clock_principal_mhz | 40,0% | Throttling por pressão de memória |
| Llama 3.2 3B | Difícil | cpi_thread_principal | 19,7% | Dependência do clock |
| Llama 3.2 3B | Difícil | clock_principal_mhz | 34,6% | Throttling por pressão de memória |

---

## 9. Conclusões Estatísticas

**Métricas recomendadas para o paper** (CV < 6% em todos os cenários viáveis):
- `ram_pico_mb` — perfeita reprodutibilidade
- `gen_tokens_s` — altamente estável
- `duracao_s` — estável com ressalva sobre EOS antecipado
- `load_store_ratio` — estável após warmup

**Métricas a citar com ressalva:**
- `prompt_tokens_s` — estável apenas em prompts longos (difícil); mencionar variabilidade no fácil
- `cpi_thread_principal` — confiável no 1B e Qwen; excluir 3B da análise de CPI

**Métrica a não citar como comparativa:**
- `clock_principal_mhz` — CV de até 40%, Turbo Boost não controlado; mencionar apenas como limitação metodológica

**Limitação a declarar no paper:**
A frequência do processador não foi fixada durante os experimentos, permitindo que o Turbo Boost variasse livremente entre execuções. Para estudos futuros, recomenda-se fixar a frequência via `cpupower frequency-set -f 2400MHz` para eliminar essa fonte de variabilidade.
