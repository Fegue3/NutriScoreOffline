import sqlite3
import pandas as pd
import uuid
import os

# === Caminhos ===
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FRONTEND_DB_PATH = os.path.join(BASE_DIR, "../Frontend/assets/db/nutriscore.db")

SRC_CSV = os.path.join(BASE_DIR, "products_clean.csv")
SCHEMA_SQL = os.path.join(BASE_DIR, "offline_schema.sql")

# Garantir que a pasta de destino existe
os.makedirs(os.path.dirname(FRONTEND_DB_PATH), exist_ok=True)

# === Ler CSV ===
df = pd.read_csv(SRC_CSV, encoding="utf-8", low_memory=False)

# === Criar / abrir BD no destino final ===
con = sqlite3.connect(FRONTEND_DB_PATH)
cur = con.cursor()

# === Aplicar schema ===
with open(SCHEMA_SQL, "r", encoding="utf-8") as f:
    cur.executescript(f.read())

# === Mapear colunas ===
rename_map = {
    "product_name": "name",
    "brands": "brand",
    "categories": "categories",
    "quantity": "quantity",
    "nutriscore_score": "nutriScoreScore",
    "nova_group": "novaGroup",
    "energy-kcal_100g": "energyKcal_100g",
    "proteins_100g": "proteins_100g",
    "carbohydrates_100g": "carbs_100g",
    "sugars_100g": "sugars_100g",
    "fat_100g": "fat_100g",
    "saturated-fat_100g": "satFat_100g",
    "fiber_100g": "fiber_100g",
    "salt_100g": "salt_100g",
    "sodium_100g": "sodium_100g",
    "countries_tags": "countries",
}

cols_present = [c for c in rename_map.keys() if c in df.columns]
df_m = df[cols_present].rename(columns=rename_map)

df_m["barcode"] = df["code"].astype(str).str.strip()
if "name" not in df_m.columns:
    df_m["name"] = df["product_name"].astype(str).str.strip()
df_m["id"] = [str(uuid.uuid4()) for _ in range(len(df_m))]

valid = {"A", "B", "C", "D", "E"}

def norm_grade(x):
    if pd.isna(x):
        return None
    s = str(x).strip().upper()
    return s[0] if s and s[0] in valid else None

if "nutriscore_grade" in df.columns:
    df_m["nutriScore"] = df["nutriscore_grade"].map(norm_grade)
else:
    df_m["nutriScore"] = None

num_cols = [
    "nutriScoreScore", "novaGroup", "energyKcal_100g", "proteins_100g",
    "carbs_100g", "sugars_100g", "fat_100g", "satFat_100g",
    "fiber_100g", "salt_100g", "sodium_100g"
]
for c in num_cols:
    if c in df_m.columns:
        df_m[c] = pd.to_numeric(df_m[c], errors="coerce")

df_m = df_m[(df_m["barcode"].notna()) & (df_m["barcode"] != "")
            & (df_m["name"].notna()) & (df_m["name"] != "")]
df_m = df_m.drop_duplicates(subset=["barcode"], keep="first")

product_cols = [
    "id", "barcode", "name", "brand", "quantity", "countries",
    "nutriScore", "nutriScoreScore", "novaGroup",
    "categories", "energyKcal_100g", "proteins_100g", "carbs_100g",
    "sugars_100g", "fat_100g", "satFat_100g", "fiber_100g",
    "salt_100g", "sodium_100g"
]
df_m = df_m[[c for c in product_cols if c in df_m.columns]]

# === Inserir ===
df_m.to_sql("Product", con, if_exists="append", index=False)
con.commit()
con.close()

print(f"✅ Inseridos {df_m.shape[0]:,} produtos em {FRONTEND_DB_PATH}")
