# ER_DIAGRAM.md — NutriScore (SQLite)

Diagrama **ASCII** das relações principais, gerado a partir do `offline_schema.sql`.  
Sem Mermaid, compatível com qualquer renderer Markdown.

## Legenda rápida
- `1` = um; `0..1` = zero ou um; `0..n` = zero ou muitos; `1..n` = um ou muitos
- Caixas = tabelas; linhas = relações (via FKs)
- Alguns relacionamentos são opcionais (SET NULL) e ficam marcados como `0..1`

```
 [User] 1
    │
    ├──────────────< 1..n ─────────────── [Meal]
    │                                      │
    │                                      └──────────< 1..n ─────────── [MealItem]
    │                                                     │
    │                                   0..1 ─────────────┴──────────── 0..1
    │                                                 [Product]       [CustomFood]
    │
    ├──────────────< 1..n ─────────────── [DailyStats]
    │
    ├──────────────< 1..n ─────────────── [WeightLog]
    │
    ├──────────────< 1..n ─────────────── [ProductHistory] ── 0..1 ──> [Product]
    │
    ├──────────────< 1..n ─────────────── [CustomFood]
    │
    └──────────────< 1..n ─────────────── [CustomMeal] ───────────< 1..n ─── [CustomMealItem]
                                                      │
                                   0..1 ──────────────┴────────────── 0..1
                                                [Product]          [CustomFood]


 [User] 1 ───────────< 1..n ── [FavoriteProduct] ── n..1 >────────── 1 [Product]
```

## Relações (texto)
- **User 1–1 UserGoals** (PK partilhada em `userId`).
- **User 1–N Meal**; **Meal 1–N MealItem**.
- **MealItem N–1 Product (0..1)** e/ou **N–1 CustomFood (0..1)** — exclusividade garantida pela app.
- **User 1–N DailyStats**; **User 1–N WeightLog**.
- **User 1–N ProductHistory**, cada histórico pode referenciar **0..1 Product** por `barcode` (SET NULL).
- **User 1–N CustomFood**.
- **User 1–N CustomMeal**; **CustomMeal 1–N CustomMealItem**; cada `CustomMealItem` pode referenciar **0..1 Product** e/ou **0..1 CustomFood** (exclusividade via lógica da app).
- **User N–N Product** através de **FavoriteProduct** (PK composta `userId, barcode`).

## Observações
- `Product.barcode` é **UNIQUE** e usado como FK em várias tabelas.
- Cascatas: remoção de `User` apaga `Meal`, `DailyStats`, `WeightLog`, `ProductHistory`, `FavoriteProduct`, `CustomFood`, `CustomMeal`.
- `SET NULL` em históricos/itens preserva registos mesmo que `Product`/`CustomFood` sejam removidos.
