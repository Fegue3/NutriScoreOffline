import pandas as pd, csv

SRC = "en.openfoodfacts.org.products.csv.gz"
OUT = "products_clean.csv"

# Colunas úteis para o bundle offline
usecols = [
    "code","product_name","brands","categories","quantity",
    "nutriscore_grade","nutriscore_score","nova_group",
    "energy-kcal_100g","proteins_100g","carbohydrates_100g",
    "sugars_100g","fat_100g","saturated-fat_100g",
    "fiber_100g","salt_100g","sodium_100g","countries_tags"
]

chunk_size = 100_000
header_written = False
total_kept = 0

print("A processar por chunks (QUOTE_NONE) — Portugal + Espanha, sem limite.\n")

for i, chunk in enumerate(pd.read_csv(
    SRC,
    sep="\t",
    engine="python",        # parser tolerante
    on_bad_lines="skip",    # ignora linhas corrompidas
    usecols=usecols,
    quoting=csv.QUOTE_NONE, # desativa parsing de aspas
    escapechar="\\",        # evita crash em linhas mal escapadas
    dtype=str,              # mantém tudo em string (mais rápido/seguro)
    chunksize=chunk_size
)):
    # 🇵🇹🇪🇸 Filtrar apenas Portugal e Espanha
    mask = chunk["countries_tags"].fillna("").str.contains("portugal|spain", case=False, regex=True)

    # Selecionar colunas e limpar nulos essenciais
    filtered = chunk.loc[mask, [
        "code","product_name","brands","categories","quantity",
        "nutriscore_grade","nutriscore_score","nova_group",
        "energy-kcal_100g","proteins_100g","carbohydrates_100g",
        "sugars_100g","fat_100g","saturated-fat_100g",
        "fiber_100g","salt_100g","sodium_100g"
    ]].dropna(subset=["product_name","energy-kcal_100g"])

    if filtered.empty:
        print(f"⏭️  Chunk {i+1}: 0 válidos (total {total_kept})")
        continue

    # Acrescentar ao CSV final incrementalmente
    filtered.to_csv(OUT, mode="a", index=False, header=not header_written)
    if not header_written:
        header_written = True

    total_kept += len(filtered)
    print(f"Chunk {i+1}: +{len(filtered)} (total {total_kept})")

print(f"\n Feito! {total_kept} produtos PT/ES gravados em {OUT}")
