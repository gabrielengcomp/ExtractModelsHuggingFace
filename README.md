# Relatório Técnico — Catalogação Automatizada de Modelos LLM no Hugging Face

## Introdução

Este documento descreve o processo de desenvolvimento de um pipeline para catalogação automatizada de modelos de linguagem (LLMs) disponíveis no Hugging Face.

O objetivo principal foi construir um sistema capaz de coletar, estruturar e armazenar metadados relevantes dos modelos em formato CSV, permitindo posterior análise, filtragem e enriquecimento das informações.

Ao longo do desenvolvimento, foram analisadas limitações da API do Hugging Face, problemas relacionados à ausência de padronização nos READMEs dos modelos e estratégias para tratamento de dados faltantes.

---

# Objetivos do Projeto

O projeto teve como objetivo inicial coletar automaticamente informações relevantes dos modelos disponibilizados no Hugging Face, principalmente:

* tamanho do modelo (número de parâmetros);
* arquitetura;
* tipo do modelo (base, instruction-tuned, chat, etc.);
* licença de uso;
* idiomas suportados;
* requisitos computacionais;
* informações de treinamento;
* datas de criação e atualização.

Além disso, foram definidos filtros iniciais para reduzir o escopo do problema:

* modelos do tipo `text-generation`;
* modelos atualizados nos últimos dois anos (a partir de janeiro de 2024);
* modelos mais populares (top modelos por likes).

---

# Primeira Análise Técnica

Inicialmente foi identificado que o projeto era totalmente viável tecnicamente, porém existia um problema importante relacionado à qualidade e padronização dos dados.

O Hugging Face funciona como um repositório colaborativo de modelos, e não como um banco de dados estruturado.

Isso implica que:

* muitos metadados não estão disponíveis diretamente na API;
* várias informações aparecem apenas nos READMEs;
* a documentação varia significativamente entre os modelos;
* alguns campos simplesmente não existem.

Dessa forma, foi decidido utilizar uma abordagem híbrida composta por:

1. coleta via API oficial do Hugging Face;
2. parsing dos READMEs dos modelos;
3. enriquecimento e inferência controlada;
4. armazenamento estruturado em CSV.

---

# Estrutura Inicial do Pipeline

A primeira versão do pipeline foi implementada em Python utilizando:

* requests;
* pandas;
* tqdm;
* expressões regulares (regex).

A arquitetura inicial do pipeline foi composta pelas seguintes etapas:

1. consulta da API do Hugging Face;
2. filtragem dos modelos;
3. download dos READMEs;
4. extração de informações;
5. geração do CSV final.

---

# Filtros Aplicados

Os seguintes filtros foram utilizados:

## Tipo de modelo

Apenas modelos com:

```text
pipeline_tag = text-generation
```

## Popularidade

Modelos ordenados por likes:

```text
sort = likes
```

## Temporalidade

Modelos atualizados desde:

```text
2024-01-01
```

---

# Campos Inicialmente Extraídos

A primeira versão buscava extrair:

* model_id;
* likes;
* downloads;
* last_modified;
* architecture;
* parameters;
* type;
* license;
* languages;
* dataset;
* epochs;
* batch_size;
* optimizer;
* learning_rate.

---

# Tratamento de Dados Faltantes

Durante o desenvolvimento foi tomada uma decisão importante relacionada à qualidade do dataset.

Ao invés de inferir agressivamente valores ausentes, optou-se por manter dados não encontrados como `None`.

Essa decisão teve como objetivo:

* evitar ruído no dataset;
* manter consistência;
* permitir rastreabilidade;
* preservar a confiabilidade das informações.

Essa abordagem foi especialmente importante para campos como:

* optimizer;
* epochs;
* batch size;
* learning rate.

---

# Resultados da Primeira Versão (v1)

A primeira execução revelou um comportamento importante.

Os campos provenientes diretamente da API apresentaram excelente completude:

* model_id;
* likes;
* downloads;
* last_modified.

Porém, os campos dependentes de parsing dos READMEs apresentaram muitos valores nulos.

Exemplo aproximado:

| Campo      | Nulos |
| ---------- | ----- |
| parameters | 790   |
| license    | 950   |
| languages  | 610   |
| dataset    | 940   |
| epochs     | 930   |
| batch_size | 950   |

---

# Diagnóstico Obtido

A partir desses resultados foi possível concluir que o principal gargalo do projeto não era técnico.

O maior problema identificado foi:

```text
Baixa padronização da documentação dos modelos.
```

Muitos READMEs:

* não possuem estrutura consistente;
* omitem detalhes de treinamento;
* utilizam linguagem natural livre;
* não seguem templates padronizados.

---

# Evolução para a Versão 2 (v2)

Com base na análise dos resultados, foram implementadas melhorias importantes.

## Melhoria na Extração de Parâmetros

A regex inicial era limitada.

Foram adicionados novos padrões para capturar:

* 7B;
* 70 billion;
* 334M;
* entre outros.

Além disso, os valores passaram a ser normalizados numericamente.

Exemplo:

```text
7B -> 7000000000
```

---

# Melhoria na Extração de Licença

Foi implementado fallback:

1. API oficial;
2. README do modelo.

Isso reduziu significativamente os valores nulos.

---

# Melhoria na Extração de Idiomas

Foi adicionada inferência segura baseada em tags.

Exemplo:

* pt;
* en;
* multilingual.

A inferência foi mantida conservadora para evitar falsos positivos.

---

# Melhoria na Extração de Arquitetura

Inicialmente todas as tags eram armazenadas no campo architecture.

Isso gerava ruído semântico.

Na versão 2 passou-se a utilizar apenas arquiteturas reconhecidas:

* llama;
* mistral;
* gpt;
* falcon;
* bert.

Apesar do aumento de valores nulos, a qualidade do dataset melhorou significativamente.

---

# Enriquecimento do Dataset

Novos campos foram adicionados:

* created_at;
* pipeline_tag;
* library_name.

---

# Resultados da Versão 2

Os resultados mostraram melhoria significativa.

| Campo      | v1  | v2  |
| ---------- | --- | --- |
| parameters | 790 | 300 |
| license    | 950 | 280 |
| languages  | 610 | 420 |

Foi possível observar:

* redução significativa de nulos;
* melhoria da confiabilidade;
* redução de inferências incorretas.

---

# Problema de Duplicação

Durante a coleta foi identificado um problema relacionado à paginação da API do Hugging Face.

Ao utilizar:

```python
offset + limit
```

alguns modelos eram retornados repetidamente.

Isso ocorre porque a API funciona de forma semelhante a um índice dinâmico, e não como paginação relacional tradicional.

---

# Solução Implementada

Foi implementada deduplicação baseada em:

```python
model_id
```

Exemplo:

```python
df = df.drop_duplicates(subset=["model_id"])
```

Essa solução estabilizou o pipeline.

---

# Evolução para a Versão 3 (v3)

Na terceira versão foram adicionadas:

* deduplicação automática;
* novos padrões de arquitetura;
* melhoria na organização do código;
* limitação inicial para os primeiros 100 modelos;
* melhorias de robustez.

Arquiteturas adicionais:

* qwen;
* gemma;
* phi.

---

# Resultados Atuais

O dataset atual apresenta:

* aproximadamente 96 modelos válidos;
* 17 colunas;
* metadados principais quase completos.

Campos bem resolvidos:

* model_id;
* likes;
* downloads;
* datas;
* pipeline_tag;
* parameters;
* license;
* type.

---

# Análise dos Valores Nulos Atuais

## Dataset

O campo dataset continua apresentando muitos valores nulos.

Motivos:

* ausência de padronização;
* menções indiretas;
* uso de linguagem natural;
* omissão de informações.

Exemplos comuns:

```text
trained on a mixture of public data
```

ou:

```text
curated corpus
```

---

# Informações de Treinamento

Campos como:

* epochs;
* batch_size;
* optimizer;
* learning_rate.

continuam altamente incompletos.

Isso ocorre porque:

* poucos modelos divulgam esses detalhes;
* muitos modelos são apenas fine-tunes;
* essas informações normalmente aparecem apenas em artigos técnicos.

---

# Limitações do Parsing via Regex

Foi identificado que o pipeline atingiu o limite natural da abordagem baseada apenas em expressões regulares.

As informações restantes geralmente estão:

* implícitas;
* espalhadas pelo README;
* descritas em linguagem natural.

---

# Melhorias Futuras

Foram identificadas possíveis evoluções futuras.

## Uso do config.json

O arquivo:

```text
config.json
```

pode fornecer:

```json
"model_type": "llama"
```

Isso permitiria melhorar significativamente a extração de arquitetura.

---

# Uso de cardData

A API também disponibiliza:

```text
cardData
```

que pode conter:

* language;
* license.

Isso reduziria ainda mais os valores nulos.

---

# Uso de LLMs para Extração

Foi identificado que a melhor solução para os campos restantes provavelmente envolve utilização de modelos de linguagem.

Exemplo:

```text
Extraia o dataset principal deste README.
```

Essa abordagem permitiria:

* interpretação contextual;
* extração semântica;
* redução significativa dos nulos.

---

# Conclusão

O projeto evoluiu significativamente ao longo das iterações.

Inicialmente o sistema funcionava apenas como um scraper simples.

Atualmente, o pipeline pode ser caracterizado como:

```text
Um sistema semi-estruturado de catalogação e enriquecimento de metadados de modelos LLM.
```

Os principais aprendizados obtidos foram:

* a coleta de dados não é o maior problema;
* a principal dificuldade está na qualidade da documentação;
* inferência excessiva reduz confiabilidade;
* manter valores nulos pode ser mais correto do que preencher informações incorretas.

O pipeline atual já apresenta:

* boa robustez;
* boa escalabilidade;
* boa confiabilidade;
* potencial de evolução para sistemas analíticos mais avançados.

Possíveis próximos passos incluem:

* dashboards;
* atualização incremental automática;
* uso de bancos de dados;
* enriquecimento via LLMs;
* ranking de qualidade dos modelos.
