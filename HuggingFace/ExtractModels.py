import requests
import pandas as pd
import re
import time
from datetime import datetime
from tqdm import tqdm

BASE_URL = "https://huggingface.co/api/models"
CUTOFF_DATE = datetime(2024, 1, 1)  # últimos 2 anos (desde jan/2024)

# -----------------------------
# Utils
# -----------------------------
def safe_get(data, key):
    value = data.get(key)
    return value if value else None


def infer_type(model_id):
    name = model_id.lower()
    if "chat" in name:
        return "chat"
    if "instruct" in name:
        return "instruction-tuned"
    return "base"


# -----------------------------
# Fetch models with pagination
# -----------------------------
def fetch_models():
    models = []
    limit = 100

    for offset in range(0, 1000, limit):
        params = {
            "pipeline_tag": "text-generation",
            "sort": "likes",
            "direction": -1,
            "limit": limit,
            "offset": offset,
            "full": True
        }

        try:
            response = requests.get(BASE_URL, params=params, timeout=15)
            response.raise_for_status()
            batch = response.json()

            if not batch:
                break

            models.extend(batch)

        except Exception as e:
            print(f"Erro ao buscar modelos (offset={offset}): {e}")
            continue

        time.sleep(0.5)  # rate limiting

    return models


# -----------------------------
# Extract info from README
# -----------------------------
def extract_from_readme(model_id):
    url = f"https://huggingface.co/{model_id}/raw/main/README.md"

    try:
        r = requests.get(url, timeout=10)
        if r.status_code != 200:
            return {}

        text = r.text.lower()

    except Exception as e:
        print(f"Erro ao baixar README ({model_id}): {e}")
        return {}

    data = {}

    # parâmetros
    match = re.search(r'(\d+(\.\d+)?)\s?(b|m)\s?parameters', text)
    if match:
        data["parameters"] = match.group(0)

    # dataset
    match = re.search(r'dataset:\s*(.+)', text)
    if match:
        data["dataset"] = match.group(1).strip()

    # idioma
    match = re.search(r'language:\s*(.+)', text)
    if match:
        data["languages"] = match.group(1).strip()

    # epochs
    match = re.search(r'epochs?:\s*(\d+)', text)
    if match:
        data["epochs"] = match.group(1)

    # batch size
    match = re.search(r'batch size:\s*(\d+)', text)
    if match:
        data["batch_size"] = match.group(1)

    # optimizer
    match = re.search(r'optimizer:\s*(.+)', text)
    if match:
        data["optimizer"] = match.group(1).strip()

    # learning rate
    match = re.search(r'learning rate:\s*([\de\-\+\.]+)', text)
    if match:
        data["learning_rate"] = match.group(1)

    return data


# -----------------------------
# Process models
# -----------------------------
def process_models(models):
    rows = []

    for m in tqdm(models):
        last_modified = m.get("lastModified")
        if not last_modified:
            continue

        try:
            date_obj = datetime.fromisoformat(last_modified.replace("Z", ""))
        except:
            continue

        # filtro de data
        if date_obj < CUTOFF_DATE:
            continue

        model_id = m.get("id")
        if not model_id:
            continue

        readme_data = extract_from_readme(model_id)

        row = {
            "model_id": model_id,
            "likes": m.get("likes"),
            "downloads": m.get("downloads"),
            "last_modified": last_modified,
            "architecture": ",".join(m.get("tags", [])) if m.get("tags") else None,
            "parameters": safe_get(readme_data, "parameters"),
            "type": infer_type(model_id),
            "license": m.get("license"),
            "languages": safe_get(readme_data, "languages"),
            "dataset": safe_get(readme_data, "dataset"),
            "epochs": safe_get(readme_data, "epochs"),
            "batch_size": safe_get(readme_data, "batch_size"),
            "optimizer": safe_get(readme_data, "optimizer"),
            "learning_rate": safe_get(readme_data, "learning_rate"),
        }

        rows.append(row)

        time.sleep(0.5)  # evitar bloqueio ao baixar READMEs

    return pd.DataFrame(rows)


# -----------------------------
# Main
# -----------------------------
def main():
    print("Buscando modelos...")
    models = fetch_models()

    print(f"Total coletado: {len(models)} modelos")

    print("Processando modelos...")
    df = process_models(models)

    output_path = "hf_llm_catalog.csv"
    df.to_csv(output_path, index=False)

    print(f"CSV gerado com sucesso em: {output_path}")

    # análise rápida de dados faltantes
    print("\nResumo de valores nulos:")
    print(df.isnull().sum())


if __name__ == "__main__":
    main()
