# Análise da Hierarquia de Cache utilizando o `perf`

## Objetivo

Esta etapa teve como objetivo avaliar o comportamento da hierarquia de memória durante a inferência de modelos de linguagem (LLMs), analisando a eficiência de utilização das caches L1, L2 e L3 através dos contadores de hardware disponibilizados pela ferramenta **perf** do Linux.

Os experimentos foram realizados utilizando o mesmo ambiente de execução, mantendo constantes:

- Hardware;
- Sistema operacional;
- Quantização dos modelos (Q4_K_M);
- Número de threads (`-t 4`);
- Temperatura (`--temp 0`);
- Número máximo de tokens (`-n 1000`);
- Prompt de complexidade média.

Dessa forma, as diferenças observadas podem ser atribuídas principalmente ao comportamento dos modelos durante a inferência.

---

# Prompt utilizado

Foi escolhido o prompt de complexidade média:

> "Explique o que é aprendizado de máquina em 3 parágrafos."

O objetivo foi produzir uma carga de trabalho suficientemente longa para gerar uma quantidade significativa de acessos à memória, sem tornar o tempo de execução excessivamente elevado.

---

# Ferramenta utilizada

A coleta foi realizada utilizando a ferramenta **perf**, disponível no Linux.

O comando utilizado foi:

```bash
sudo perf stat \
-e instructions,\
cycles,\
cache-references,\
cache-misses,\
mem_load_retired.l1_hit,\
mem_load_retired.l1_miss,\
mem_load_retired.l2_hit,\
mem_load_retired.l2_miss,\
mem_load_retired.l3_hit,\
mem_load_retired.l3_miss \
./build/bin/llama-cli \
-m <modelo.gguf> \
-p "Explique o que é aprendizado de máquina em 3 parágrafos." \
-n 1000 \
-t 4 \
--temp 0 \
--single-turn
```

Foram coletados os seguintes contadores:

- instructions
- cycles
- cache-references
- cache-misses
- mem_load_retired.l1_hit
- mem_load_retired.l1_miss
- mem_load_retired.l2_hit
- mem_load_retired.l2_miss
- mem_load_retired.l3_hit
- mem_load_retired.l3_miss

---

# Significado das métricas

## Instructions

Quantidade total de instruções aposentadas pelo processador durante a execução.

---

## Cycles

Quantidade total de ciclos de clock utilizados.

---

## IPC

Calculado como

```
IPC = instructions / cycles
```

Representa quantas instruções foram executadas por ciclo de clock.

Quanto maior o IPC, maior a utilização dos recursos do processador.

---

## L1 Hit

Quantidade de leituras encontradas diretamente na cache L1.

---

## L1 Miss

Quantidade de leituras que não estavam presentes na L1.

Esses acessos precisam consultar a cache L2.

---

## L2 Hit

Quantidade de acessos provenientes da L1 que foram resolvidos pela L2.

---

## L2 Miss

Quantidade de acessos que também falharam na L2.

Esses acessos seguem para a cache L3.

---

## L3 Hit

Quantidade de acessos resolvidos pela cache L3.

---

## L3 Miss

Quantidade de acessos que não estavam presentes nem na L3.

Nesses casos o processador precisa acessar a memória RAM, operação significativamente mais lenta.

---

# Como calcular as taxas de miss

As comparações entre modelos não devem utilizar os valores absolutos dos contadores, pois cada modelo realiza quantidades diferentes de acessos.

Por isso foram utilizadas as taxas de miss.

## L1

```
L1 Miss Rate =
L1 Miss /
(L1 Hit + L1 Miss)
```

---

## L2

```
L2 Miss Rate =
L2 Miss /
(L2 Hit + L2 Miss)
```

---

## L3

```
L3 Miss Rate =
L3 Miss /
(L3 Hit + L3 Miss)
```

---

# Resultados obtidos

## Llama 3.2 1B

| Métrica | Valor |
|---------|-------:|
| IPC | 1.70 |
| L1 Miss | 1.48 % |
| L2 Miss | 19.69 % |
| L3 Miss | 67.83 % |

---

## Qwen2.5 1.5B

| Métrica | Valor |
|---------|-------:|
| IPC | 1.77 |
| L1 Miss | 1.92 % |
| L2 Miss | 16.75 % |
| L3 Miss | 67.90 % |

---

# Comparação

| Métrica | Llama | Qwen |
|---------|------:|------:|
| IPC | 1.70 | **1.77** |
| L1 Miss | **1.48 %** | 1.92 % |
| L2 Miss | 19.69 % | **16.75 %** |
| L3 Miss | **67.83 %** | 67.90 % |

---

# Interpretação

Os resultados mostram que ambos os modelos apresentam comportamento bastante semelhante quanto ao uso da hierarquia de memória.

O Qwen apresentou um IPC ligeiramente superior (1.77 contra 1.70), indicando melhor aproveitamento dos ciclos de processamento.

Na cache L1, o Llama apresentou menor taxa de miss (1.48%), sugerindo maior localidade dos dados mais frequentemente utilizados.

Entretanto, quando ocorre um miss na L1, o Qwen aproveita melhor a cache L2, reduzindo sua taxa de miss para 16.75%, enquanto o Llama apresenta 19.69%.

Na cache L3 os dois modelos possuem comportamento praticamente idêntico, com aproximadamente 68% dos acessos seguindo para a memória principal.

---

# Observações importantes

Os contadores

- cache-references
- cache-misses

foram coletados apenas como informação complementar.

Em processadores Intel modernos esses eventos representam aliases genéricos do PMU e não necessariamente correspondem ao total de acessos realizados em cada nível da hierarquia.

Por esse motivo, a análise foi baseada principalmente nos eventos:

- mem_load_retired.l1_hit
- mem_load_retired.l1_miss
- mem_load_retired.l2_hit
- mem_load_retired.l2_miss
- mem_load_retired.l3_hit
- mem_load_retired.l3_miss

que descrevem diretamente o comportamento das cargas de memória.

---

# Conclusão

A utilização dos contadores de hardware permitiu caracterizar o comportamento da hierarquia de memória durante a inferência dos modelos.

Embora o Llama apresente uma taxa de misses ligeiramente menor na cache L1, o Qwen demonstra melhor aproveitamento da cache L2 e um IPC superior, indicando uma utilização mais eficiente dos recursos do processador.

As diferenças observadas na cache L3 foram praticamente inexistentes, sugerindo que ambos os modelos possuem comportamento semelhante em relação aos acessos à memória principal.
