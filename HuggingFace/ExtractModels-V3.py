import requests
import pandas as pd
import re
import time
from datetime import datetime
from tqdm import tqdm

BASE_URL = "https://huggingface.co/api/models"

# -----------------------------------
# CONFIG
# -----------------------------------
CUTOFF_DATE = datetime(2024, 1, 1)

# limitar aos primeiros 100 modelos
MAX_MODELS = 100

# delay entre requests
REQUEST_DELAY = 0.5


# -----------------------------------
# Utils
# -----------------------------------
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


def normalize_params(value):
    if not value:
        return None

    value = value.lower()

    num_match = re.search(r'\d+(\.\d+)?', value)

    if not num_match:
        return None

    num = float(num_match.group())

    if "billion" in value or "b" in value:
        return int(num * 1e9)

    if "million" in value or "m" in value:
        return int(num * 1e6)

    return None


def extract_language_from_tags(tags):
    if not tags:
        return None

    known_langs = [
        "pt",
        "en",
        "es",
        "fr",
        "de",
        "it",
        "multilingual"
    ]

    langs = []

    for t in tags:
        if t.lower() in known_langs:
            langs.append(t.lower())

    return ",".join(langs) if langs else None


def extract_architecture(tags):
    if not tags:
        return None

    known_archs = [
        "llama",
        "mistral",
        "gpt",
        "falcon",
        "bert",
        "qwen",
        "gemma",
        "phi"
    ]

    for t in tags:
        for arch in known_archs:
            if arch in t.lower():
                return arch

    return None


# -----------------------------------
# Fetch models
# -----------------------------------
def fetch_models():
    models = []

    params = {
        "pipeline_tag": "text-generation",
        "sort": "likes",
        "direction": -1,
        "limit": MAX_MODELS,
        "full": True
    }

    try:
        response = requests.get(
            BASE_URL,
            params=params,
            timeout=15
        )

        response.raise_for_status()

        batch = response.json()

        models.extend(batch)

    except Exception as e:
        print(f"Erro ao buscar modelos: {e}")

    return models


# -----------------------------------
# README extraction
# -----------------------------------
def extract_from_readme(model_id):

    url = f"https://huggingface.co/{model_id}/raw/main/README.md"

    try:
        r = requests.get(url, timeout=10)

        if r.status_code != 200:
            return {}

        text = r.text.lower()

    except Exception as e:
        print(f"Erro README ({model_id}): {e}")
        return {}

    data = {}

    # -----------------------------------
    # PARAMETERS
    # -----------------------------------
    match = re.search(
        r'(\d+(\.\d+)?)\s?(billion|million|b|m)',
        text
    )

    if match:
        raw = match.group(0)
        data["parameters"] = normalize_params(raw)

    # -----------------------------------
    # DATASET
    # -----------------------------------
    dataset_patterns = [
        r'dataset:\s*(.+)',
        r'trained on:\s*(.+)',
        r'fine-tuned on:\s*(.+)'
    ]

    for pattern in dataset_patterns:
        match = re.search(pattern, text)

        if match:
            data["dataset"] = match.group(1).strip()
            break

    # -----------------------------------
    # LANGUAGE
    # -----------------------------------
    match = re.search(r'language:\s*(.+)', text)

    if match:
        data["languages"] = match.group(1).strip()

    # -----------------------------------
    # EPOCHS
    # -----------------------------------
    match = re.search(r'epochs?:\s*(\d+)', text)

    if match:
        data["epochs"] = match.group(1)

    # -----------------------------------
    # BATCH SIZE
    # -----------------------------------
    match = re.search(r'batch size:\s*(\d+)', text)

    if match:
        data["batch_size"] = match.group(1)

    # -----------------------------------
    # OPTIMIZER
    # -----------------------------------
    match = re.search(r'optimizer:\s*(.+)', text)

    if match:
        data["optimizer"] = match.group(1).strip()

    # -----------------------------------
    # LEARNING RATE
    # -----------------------------------
    match = re.search(
        r'learning rate:\s*([\de\-\+\.]+)',
        text
    )

    if match:
        data["learning_rate"] = match.group(1)

    # -----------------------------------
    # LICENSE FALLBACK
    # -----------------------------------
    match = re.search(r'license:\s*(.+)', text)

    if match:
        data["license"] = match.group(1).strip()

    return data


# -----------------------------------
# Process models
# -----------------------------------
def process_models(models):

    rows = []

    for m in tqdm(models):

        last_modified = m.get("lastModified")

        if not last_modified:
            continue

        try:
            date_obj = datetime.fromisoformat(
                last_modified.replace("Z", "")
            )

        except Exception:
            continue

        # filtro temporal
        if date_obj < CUTOFF_DATE:
            continue

        model_id = m.get("id")

        if not model_id:
            continue

        tags = m.get("tags", [])

        readme_data = extract_from_readme(model_id)

        row = {

            # -----------------------------
            # API DATA
            # -----------------------------
            "model_id": model_id,
            "likes": m.get("likes"),
            "downloads": m.get("downloads"),
            "last_modified": last_modified,
            "created_at": m.get("createdAt"),
            "pipeline_tag": m.get("pipeline_tag"),
            "library": m.get("library_name"),

            # -----------------------------
            # ENRICHED DATA
            # -----------------------------
            "architecture": extract_architecture(tags),

            "parameters":
                safe_get(readme_data, "parameters"),

            "type":
                infer_type(model_id),

            "license":
                m.get("license")
                or safe_get(readme_data, "license"),

            "languages":
                safe_get(readme_data, "languages")
                or extract_language_from_tags(tags),

            "dataset":
                safe_get(readme_data, "dataset"),

            # -----------------------------
            # TRAINING INFO
            # -----------------------------
            "epochs":
                safe_get(readme_data, "epochs"),

            "batch_size":
                safe_get(readme_data, "batch_size"),

            "optimizer":
                safe_get(readme_data, "optimizer"),

            "learning_rate":
                safe_get(readme_data, "learning_rate"),
        }

        rows.append(row)

        time.sleep(REQUEST_DELAY)

    return pd.DataFrame(rows)


# -----------------------------------
# Remove duplicates
# -----------------------------------
def remove_duplicates(df):

    before = len(df)

    df = df.drop_duplicates(
        subset=["model_id"]
    )

    after = len(df)

    removed = before - after

    print(f"\nDuplicados removidos: {removed}")

    return df


# -----------------------------------
# Main
# -----------------------------------
def main():

    print("Buscando modelos...")

    models = fetch_models()

    print(f"Total bruto coletado: {len(models)}")

    print("\nProcessando modelos...")

    df = process_models(models)

    # remover duplicados
    df = remove_duplicates(df)

    output_path = "hf_llm_catalog_v3.csv"

    df.to_csv(
        output_path,
        index=False
    )

    print(f"\nCSV gerado com sucesso em:")
    print(output_path)

    print("\nResumo de valores nulos:")
    print(df.isnull().sum())

    print(f"\nTotal final de modelos: {len(df)}")


if __name__ == "__main__":
    main()