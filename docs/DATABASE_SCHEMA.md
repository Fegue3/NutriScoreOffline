# DATABASE_SCHEMA.md — NutriScore (SQLite)

Documento de referência do **esquema de base de dados** (`offline_schema.sql`) usado pela aplicação **NutriScore**. O foco é descrever **tabelas, chaves, índices, regras de integridade** e **padrões de acesso** — sem diagramas nem trechos de código de aplicação.

---

## 1) Convenções Gerais

- **Engine**: SQLite (on‑device).  
- **FKs**: `PRAGMA foreign_keys = ON` (ativado no schema).  
- **Datas**: guardadas em `TEXT` no formato **ISO 8601** (UTC quando aplicável).  
- **Auditoria**: campos `createdAt` (default `datetime('now')`) e `updatedAt` (atualizado por *triggers* em várias tabelas).  
- **Enums**: simuladas via `CHECK` (ex.: `nutriScore` A–E; `Meal.type`; `Unit`).  
- **Chaves naturais**: `Product.barcode` é **UNIQUE**; existe também `Product.id` (UUID).  
- **Upserts**: efetuados pela app, respeitando as chaves/índices aqui descritos.

---

## 2) Tabelas

### 2.1 `User`
- **PK**: `id` (TEXT, UUID).  
- **Campos**: `email` (UNIQUE, NOT NULL), `passwordHash` (hash local), `refreshTokenHash` (não usado no MVP offline), `name`, `onboardingCompleted` (0/1), `createdAt`, `updatedAt`.  
- **Trigger**: `trg_User_updatedAt` — atualiza `updatedAt` em `UPDATE`.

**Notas**: Utilizador local da app. Sem sincronização remota no MVP.

---

### 2.2 `UserGoals`
- **PK**: `userId` (1:1 com `User`).  
- **FK**: `userId` → `User(id)` (**ON DELETE CASCADE**).  
- **Campos**: dados demográficos (`sex` com `CHECK`, `dateOfBirth`, `heightCm`, pesos, `activityLevel`), preferências (`lowSalt`, `lowSugar`, `vegetarian`, `vegan`, `allergens`), metas (`dailyCalories`, `carbPercent`, `proteinPercent`, `fatPercent`), `updatedAt`.  
- **Trigger**: `trg_UserGoals_updatedAt`.

**Notas**: Uma única linha por utilizador (modelo 1‑para‑1).

---

### 2.3 `Product`
- **PK**: `id` (TEXT, UUID).  
- **Chave natural**: `barcode` (**UNIQUE**, NOT NULL).  
- **Campos**: identificação (`name`, `brand`, `quantity`, `servingSize`, `imageUrl`, `countries`), classificação (**`nutriScore`** A–E + `nutriScoreScore`, `novaGroup`, `ecoScore`), rotulagem (`categories`, `labels`, `allergens`, `ingredientsText`), **nutrição por 100g** e **por porção** (`*_100g`, `*_serv`), auditoria (`lastFetchedAt`, `createdAt`, `updatedAt`), `off_raw` (payload OFF).  
- **Índices**: `idx_Product_name`, `idx_Product_brand`, `idx_Product_categories`. (*UNIQUE* em `barcode` cria índice implícito.)  
- **Trigger**: `trg_Product_updatedAt`.

**Notas**: Fonte primária para composição de refeições e pesquisas por texto.

---

### 2.4 `ProductHistory`
- **PK**: `id` (INTEGER AUTOINCREMENT).  
- **FKs**:  
  - `userId` → `User(id)` (**ON DELETE CASCADE**).  
  - `barcode` → `Product(barcode)` (**ON DELETE SET NULL**).  
- **Campos**: `scannedAt` (default now), `nutriScore`, `calories`, `proteins`, `carbs`, `fat`.  
- **Índices**: `idx_ProductHistory_user_date` (`userId`, `scannedAt`), `idx_ProductHistory_barcode`.

**Notas**: Auditoria de scans/consultas. Mantém histórico independente da vida do produto (por isso `SET NULL`).

---

### 2.5 `FavoriteProduct`
- **PK composta**: (`userId`, `barcode`).  
- **FKs**: `userId` → `User(id)` (**CASCADE**), `barcode` → `Product(barcode)` (**CASCADE**).  
- **Campos**: `createdAt` (default now).

**Notas**: Relação N:M simplificada entre utilizador e produtos via chave composta.

---

### 2.6 `CustomFood` *(opcional no MVP, mas suportado no schema)*
- **PK**: `id` (TEXT, UUID).  
- **FK**: `userId` → `User(id)` (**CASCADE**).  
- **Campos**: `name` (NOT NULL), `brand`, `defaultUnit` (`CHECK` em 'GRAM'/'ML'/'PIECE'), `gramsPerUnit`, nutrição por 100g (`*_100g`), `createdAt`, `updatedAt`.  
- **Trigger**: `trg_CustomFood_updatedAt`.

**Notas**: Itens personalizados definidos pelo utilizador.

---

### 2.7 `CustomMeal` *(opcional)*
- **PK**: `id` (TEXT).  
- **FK**: `userId` → `User(id)` (**CASCADE**).  
- **Campos**: `name` (NOT NULL), totais (`totalKcal`, `totalProtein`, `totalCarb`, `totalFat`), `createdAt`, `updatedAt`.  
- **Trigger**: `trg_CustomMeal_updatedAt`.

**Notas**: Composições reutilizáveis de alimentos/itens.

---

### 2.8 `CustomMealItem` *(opcional)*
- **PK**: `id` (TEXT).  
- **FKs**:  
  - `customMealId` → `CustomMeal(id)` (**CASCADE**).  
  - `customFoodId` → `CustomFood(id)` (**SET NULL**).  
  - `productBarcode` → `Product(barcode)` (**SET NULL**).  
- **Campos**: `unit` (`CHECK`), `quantity`, `gramsTotal`, macros `kcal/protein/carb/fat`, `position` (ordenação).

**Notas**: Cada item aponta **ou** para `CustomFood` **ou** para `Product` (regra de negócio; não há `CHECK` a garantir exclusividade).

---

### 2.9 `Meal`
- **PK**: `id` (TEXT).  
- **FK**: `userId` → `User(id)` (**CASCADE**).  
- **Campos**: `date` (UTC canónico), `type` (`CHECK` em BREAKFAST/LUNCH/DINNER/SNACK), `notes`, totais (`totalKcal`, `totalProtein`, `totalCarb`, `totalFat`), `createdAt`, `updatedAt`.  
- **Restrição**: **`UNIQUE (userId, date, type)`** — uma refeição por dia/tipo por utilizador.  
- **Índice**: `idx_Meal_user_date`.  
- **Trigger**: `trg_Meal_updatedAt`.

**Notas**: Cabeçalho da refeição diária por tipo.

---

### 2.10 `MealItem`
- **PK**: `id` (TEXT).  
- **FKs**:  
  - `mealId` → `Meal(id)` (**CASCADE**).  
  - `productBarcode` → `Product(barcode)` (**SET NULL**).  
  - `customFoodId` → `CustomFood(id)` (**SET NULL**).  
  - `userId` → `User(id)` (opcional; sem ação definida).  
- **Campos**: `unit` (`CHECK`), `quantity`, `gramsTotal`, macros (`kcal`, `protein`, `carb`, `fat`, `sugars`, `fiber`, `salt`), `position`.

**Notas**: Item de refeição associado a **um** produto **ou** a um alimento personalizado (exclusividade garantida pela lógica da app).

---

### 2.11 `DailyStats`
- **PK composta**: (`userId`, `date`).  
- **FK**: `userId` → `User(id)` (**CASCADE**).  
- **Campos**: totais diários (`kcal`, `protein`, `carb`, `fat`, `sugars`, `fiber`, `salt`), `createdAt`, `updatedAt`.  
- **Índice**: `idx_DailyStats_user_date` (redundante com a PK, útil para leitura ordenada).  
- **Trigger**: `trg_DailyStats_updatedAt`.

**Notas**: Tabela de agregados para leituras rápidas no dashboard.

---

### 2.12 `WeightLog`
- **PK**: `id` (TEXT).  
- **FK**: `userId` → `User(id)` (**CASCADE**).  
- **Campos**: `day` (YYYY‑MM‑DD), `weightKg` (NOT NULL), `source`, `note`, `createdAt`.  
- **Índice**: `idx_WeightLog_user_day`.

**Notas**: Registo de evolução de peso por utilizador.

---

## 3) Relacionamentos (texto)

- **User 1–1 UserGoals** (PK partilhada por `userId`).  
- **User 1–N Meal**; **Meal 1–N MealItem**.  
- **MealItem N–1 Product** *(opcional)* **/ N–1 CustomFood** *(opcional)*.  
- **User 1–N DailyStats** (PK composta por data).  
- **User 1–N WeightLog**.  
- **User 1–N ProductHistory** (cada histórico pode referenciar **0/1** `Product` por `barcode`).  
- **User N–N Product** via **FavoriteProduct** (PK composta).  
- **User 1–N CustomFood**.  
- **User 1–N CustomMeal**; **CustomMeal 1–N CustomMealItem**; **CustomMealItem N–1 Product** *(opcional)* **/ N–1 CustomFood** *(opcional)*.

**Invariantes de negócio (enforcadas pela app):**
- Em `MealItem` e `CustomMealItem`, **exatamente um** dos campos de referência (`productBarcode` **ou** `customFoodId`) deve estar preenchido.  
- Horas/datas devem ser persistidas em UTC para consistência de agregados.  
- Totais em `Meal` e `DailyStats` devem refletir a soma dos itens correspondentes.

---

## 4) Índices & Performance

- **Pesquisa por texto**: `Product(name|brand|categories)` para listagens e auto‑complete.  
- **Chaves naturais**: `Product.barcode` é **UNIQUE** (índice implícito para *lookups* por scan).  
- **Consultas temporais**: índices em `Meal(userId, date)`, `DailyStats(userId, date)`, `WeightLog(userId, day)`, `ProductHistory(userId, scannedAt)`.  
- **Sugestões (opcional)**:  
  - `ProductHistory(userId, barcode)` para frequências por utilizador.  
  - `MealItem(mealId, position)` para ordenação eficiente.

---

## 5) Integridade & Regras

- **Cascatas**: remoção de `User` apaga `Meal`, `DailyStats`, `WeightLog`, `FavoriteProduct`, `ProductHistory`, `CustomFood`, `CustomMeal` (via FKs).  
- **Set NULL**: histórico/itens mantêm integridade mesmo que o `Product`/`CustomFood` seja removido.  
- **Triggers `updatedAt`**: em `User`, `UserGoals`, `Product`, `CustomFood`, `CustomMeal`, `Meal`, `DailyStats`.  
- **Enums**: `CHECK`s em `nutriScore`, `Meal.type` e `Unit` (GRAM/ML/PIECE).

---

## 6) Padrões de Acesso (consultas típicas)

- **Lookup por scan**: `SELECT * FROM Product WHERE barcode = ?`.  
- **Pesquisa por texto**: `WHERE name LIKE 'abc%' OR brand LIKE 'abc%' OR categories LIKE '%abc%'`.  
- **Refeições do dia**: `SELECT * FROM Meal WHERE userId = ? AND date BETWEEN ...`.  
- **Itens de uma refeição**: `SELECT * FROM MealItem WHERE mealId = ? ORDER BY position`.  
- **Dashboard**: `SELECT * FROM DailyStats WHERE userId = ? AND date = ?`.  
- **Evolução de peso**: `SELECT * FROM WeightLog WHERE userId = ? ORDER BY day`.  
- **Favoritos**: `SELECT p.* FROM FavoriteProduct f JOIN Product p ON p.barcode=f.barcode WHERE f.userId=?`.

---

## 7) Migrações & Compatibilidade

- **Versão do schema** controlada pela app (ex.: via Drift `schemaVersion`).  
- **Migrações seguras**: usar `ALTER TABLE` aditivo; para alterações destrutivas, criar nova tabela, migrar dados e renomear.  
- **Backfill**: manter `createdAt`/`updatedAt`; recalcular agregados de `DailyStats` quando necessário.  
- **Validação**: `PRAGMA foreign_key_check` e testes instrumentados após migração.

---

## 8) Qualidade & Manutenção

- **Dados OFF**: armazenados também em `off_raw` para rastreabilidade.  
- **Consistência**: totais em `Meal`/`DailyStats` são derivados de itens; preferir cálculo determinístico e atualizar agregados via *use cases*.  
- **Backups** (opcional): exportação local/CSV em funcionalidades futuras.

---

**Resumo**: O esquema prioriza **offline-first**, consultas rápidas (índices), integridade relacional (FKs/`CHECK`s), e auditabilidade (`*_At`, `off_raw`). O modelo suporta itens personalizados e composições reutilizáveis, mantendo sempre a **fonte única de verdade** no dispositivo.
