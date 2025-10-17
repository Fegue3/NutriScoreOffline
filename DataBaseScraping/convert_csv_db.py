import sqlite3, pandas as pd

df = pd.read_csv("products_clean.csv")

con = sqlite3.connect("catalog.db")
cur = con.cursor()

# aplica o teu schema
with open("offline_schema.sql", "r") as f:
    cur.executescript(f.read())

# insere apenas nas colunas da Product
df.to_sql("Product", con, if_exists="append", index=False)

# meta info
cur.execute("CREATE TABLE IF NOT EXISTS AppMeta (bundleVersion TEXT, schemaVersion INTEGER, rowCount INTEGER)")
cur.execute("INSERT INTO AppMeta VALUES (?, ?, ?)", ("pt-2025-10", 1, len(df)))

con.commit()
con.close()
