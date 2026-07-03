# Análise de Cache via perf stat — 5 Repetições
**Hardware:** Intel Core i5-1135G7 (Tigerlake) · 16 GB RAM  
**Modelos:** Llama 3.2 1B · Qwen 2.5 1.5B (Q4_K_M GGUF)  
**Prompt:** "Explique o que é aprendizado de máquina em 3 parágrafos." (nível médio)  
**Tokens gerados:** 1000 · **Threads:** 4 · **Repetições:** 5  
**Ferramenta:** `perf stat` com eventos de cache L1/L2/L3

---

## 1. IPC — Instructions Per Cycle

| Modelo | Média | StdDev | CV% |
|---|---|---|---|
| Llama 3.2 1B | 1,418 | 0,105 | 7,4% |
| Qwen 2.5 1.5B | 1,599 | 0,043 | 2,7% |

O Qwen apresenta IPC superior (1,60 vs 1,42) e significativamente mais estável (CV 2,7% vs 7,4%). O maior CV do Llama é correlacionado à variação do Turbo Boost capturada nas repetições — o clock mais instável afeta diretamente o IPC calculado.

---

## 2. Cache Miss Rate Geral

Taxa de misses sobre o total de referências ao cache (`cache-misses / cache-references`).

| Modelo | Média (%) | StdDev | CV% |
|---|---|---|---|
| Llama 3.2 1B | 67,57 | 2,45 | 3,6% |
| Qwen 2.5 1.5B | 60,81 | 3,47 | 5,7% |

Ambos os modelos apresentam taxa de miss elevada (>60%), indicando que a hierarquia de cache não consegue absorver o padrão de acesso aos pesos durante a inferência. O Llama 1B tem miss rate ~7 pontos percentuais maior que o Qwen.

---

## 3. L1 Cache

| Modelo | L1 Hit (média) | L1 Miss (média) | L1 Miss Rate (%) | StdDev | CV% |
|---|---|---|---|---|---|
| Llama 3.2 1B | 37,01G | 563,2M | 1,50 | 0,02 | 1,3% |
| Qwen 2.5 1.5B | 33,83G | 677,1M | 1,96 | 0,02 | 1,0% |

Taxa de miss de L1 baixa em ambos (~1,5–2,0%) — a maioria dos loads é satisfeita no L1. O Qwen tem mais misses de L1 em termos absolutos (677M vs 563M), porém o total de loads do Llama é maior (37,6G vs 34,5G), resultando em miss rate proporcionalmente menor. CV abaixo de 2% em ambos — **métrica altamente estável**.

---

## 4. L2 Cache

| Modelo | L2 Hit (média) | L2 Miss (média) | L2 Miss Rate (%) | StdDev | CV% |
|---|---|---|---|---|---|
| Llama 3.2 1B | 445,7M | 117,5M | 20,86 | 0,75 | 3,6% |
| Qwen 2.5 1.5B | 562,5M | 114,3M | 16,89 | 0,29 | 1,7% |

O Llama perde mais no L2 (20,86% vs 16,89% do Qwen). O Qwen tem mais hits no L2 em absoluto (562M vs 445M), sugerindo melhor localidade temporal dos dados que escapam do L1. CV estável nos dois modelos (< 4%).

---

## 5. L3 Cache

| Modelo | L3 Hit (média) | L3 Miss (média) | L3 Miss Rate (%) | StdDev | CV% |
|---|---|---|---|---|---|
| Llama 3.2 1B | 32,7M | 76,3M | 69,99 | 1,38 | 2,0% |
| Qwen 2.5 1.5B | 33,8M | 71,1M | 67,76 | 0,80 | 1,2% |

**Achado principal:** ~68–70% dos loads que chegam ao L3 falham e vão para a RAM. Esse é o dado mais direto que evidencia execução *memory-bound* — os pesos do modelo não cabem na hierarquia de cache e precisam ser buscados da memória principal a cada etapa de geração. CV abaixo de 2% — **métrica confiável**.

---

## 6. Volume de Instruções e Ciclos

| Modelo | Instructions (média) | Cycles (média) |
|---|---|---|
| Llama 3.2 1B | 248,88G | 176,28G |
| Qwen 2.5 1.5B | 242,26G | 151,62G |

O Llama executa mais instruções (~6,6G a mais) e mais ciclos (~24,7G a mais) para gerar a mesma quantidade de tokens. Combinado com o menor IPC, indica que o Llama 1B é computacionalmente menos eficiente por token gerado, apesar de ter maior throughput em t/s.

---

## 7. Resumo Comparativo

| Métrica | Llama 3.2 1B | Qwen 2.5 1.5B | Vantagem |
|---|---|---|---|
| IPC | 1,418 (CV 7,4%) | 1,599 (CV 2,7%) | **Qwen** |
| Cache Miss Rate (%) | 67,57 | 60,81 | **Qwen** |
| L1 Miss Rate (%) | 1,50 | 1,96 | **Llama** |
| L2 Miss Rate (%) | 20,86 | 16,89 | **Qwen** |
| L3 Miss Rate (%) | 69,99 | 67,76 | **Qwen** |
| Instructions | 248,88G | 242,26G | **Qwen** |
| Cycles | 176,28G | 151,62G | **Qwen** |

---

## 8. Confiabilidade das Métricas

| Métrica | CV% | Confiável? |
|---|---|---|
| L1 Miss Rate | 1,0–1,3% | ✅ Alta |
| L3 Miss Rate | 1,2–2,0% | ✅ Alta |
| L2 Miss Rate | 1,7–3,6% | ✅ Alta |
| Cache Miss Rate | 3,6–5,7% | ✅ Alta |
| IPC (Qwen) | 2,7% | ✅ Alta |
| IPC (Llama) | 7,4% | ⚠️ Moderada — variação de clock |

Todas as métricas de cache apresentam CV abaixo de 6%, indicando alta reprodutibilidade. O IPC do Llama tem variabilidade moderada, correlacionada ao comportamento instável do Turbo Boost já observado nas coletas LIKWID.

---

## 9. Conclusão

O perfil de cache confirma e complementa os achados do LIKWID: ambos os modelos operam em regime *memory-bound*, com ~68–70% dos acessos ao L3 resultando em misses para a RAM. O Qwen 2.5 1.5B apresenta desempenho de cache superior em quase todas as métricas (menor miss rate no L2 e L3, maior IPC), enquanto o Llama 3.2 1B compensa com maior throughput de geração em t/s — possivelmente por diferenças no padrão de acesso aos pesos decorrentes da arquitetura GQA do Qwen.

A L3 miss rate de ~70% é a evidência mais direta de que o gargalo computacional está na largura de banda de memória RAM, e não na capacidade de cômputo do processador — resultado consistente com o vectorization ratio de 0% obtido via LIKWID.
