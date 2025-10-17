# NutriScore — Alimentação Consciente (Offline-First)

Aplicação móvel **offline** para registo de refeições, análise nutricional simplificada (incl. **NutriScore A–E**), histórico e estatísticas — pensada para estudantes, famílias e pessoas que precisam de controlar sal, açúcar e gordura.

> **Stack:** Flutter · Dart · SQLite (on-device) · Python (pré-processamento de dados) · Dados baseados em **Open Food Facts** (OFF)

---

## ✨ Principais Funcionalidades

* **Leitor de código de barras/QR** para identificar produtos rapidamente.
* **Consulta offline** a uma base de dados local derivada do **Open Food Facts**.
* **NutriScore (A–E)** com cores (verde→vermelho) e informação simplificada: calorias, açúcares, gorduras, sal.
* **Registo de refeições** por tipo (Pequeno‑almoço, Almoço, Lanche, Jantar) e cálculo automático de **calorias e macronutrientes**.
* **Dashboard diário**: progresso de calorias e macros vs. meta.
* **Estatísticas de nutrição** (calorias/macros por dia) e **evolução de peso** (gráfico de tendência).
* **Histórico de produtos pesquisados**, favoritos e itens personalizados.
* **Autenticação local** (hash em SQLite) e **metas do utilizador** (calorias/percentuais de macros, preferências).

> **Visão:** tornar simples e acessível monitorizar ingestão calórica e de macronutrientes, ajudando a cumprir objetivos de saúde — **sem depender de internet**.

---

## 🧱 Arquitetura & Stack Offline

**Offline-first** significa que todas as operações principais funcionam sem rede:

* **SQLite on‑device** com um **esquema otimizado** (índices, enums via `CHECK`, triggers para `updatedAt`).
* **Pipeline local** (Python) que **converte CSVs** do Open Food Facts para um **ficheiro SQLite** pronto a usar.
* App Flutter lê/escreve diretamente na base local — sem API externa.
* Sincronização/online pode ser adicionada no futuro sem alterar o núcleo do MVP.

### Fluxo de dados

1. **CSV OFF → Python** (`convert_csv_db.py`) limpa/normaliza campos.
2. **SQLite** é criado com `offline_schema.sql` e populado.
3. A **app Flutter** consulta por **barcode** e por **texto** (com índices em nome, marca, categorias).

---

## 📦 Estrutura de Pastas (sugerida)

```
NutriScore/
├─ DataBaseScraping/        # Pipeline Python (CSV → SQLite)
│  ├─ convert_csv_db.py
│  ├─ offline_schema.sql
│  └─ products_clean.csv    # Fonte trabalhada (derivada do OFF)
└─ Frontend/                # App Flutter
   ├─ lib/
   │  ├─ core/              # theme.dart, widgets base (ex.: gráficos)
   │  ├─ domain/            # models.dart, repos interfaces
   │  ├─ data/              # SQLite (Drift/DAO/queries) + DI
   │  └─ features/
   │     ├─ nutrition/      # ecrãs: log refeições, estatísticas, add food
   │     ├─ home/           # dashboard (progresso diário)
   │     └─ weight/         # gráfico evolução de peso
   └─ assets/
```

> **Design System (NutriScore):** paleta com Fresh Green (#4CAF6D), Warm Tangerine (#FF8A4C), Leafy Green (#66BB6A), Golden Amber (#FFC107), Ripe Red (#E53935) e neutros (Charcoal #333, Cool Gray #666, Soft Off‑White #FAFAF7, Light Sage #E8F5E9). Tipografia: **Nunito Sans** (títulos), **Inter** (texto), **Roboto Mono** (números). **Usa sempre as variáveis em `theme.dart`.**

---

## ▶️ Setup & Execução (passo a passo)

### 1) Pré‑requisitos

* **Flutter** (canal stable) instalado e `flutter doctor` OK.
* **Python 3.10+** com `pip`.

> Dependências Python típicas: `pandas`.

### 2) Construir a base de dados offline

```bash
cd DataBaseScraping
python3 convert_csv_db.py
```

O script irá:

* Ler `products_clean.csv` (derivado do Open Food Facts)
* Criar **`nutriscore.db`** a partir do **`offline_schema.sql`**
* Popular tabelas `Product` e relacionadas

### 3) Correr a aplicação Flutter

```bash
cd ..              # voltar à raiz
cd Frontend
flutter pub get
flutter run
```

> A app procurará o ficheiro SQLite local (ver `di.dart`/config). Certifica‑te que `nutriscore.db` está acessível no caminho esperado (ex.: `assets` + copy on first run, ou diretório de dados da app).

---

## 🗃️ Trecho de Esquema (SQLite)

> Ficheiro: **`offline_schema.sql`** (extracto — ver original para completo)

```sql
PRAGMA foreign_keys = ON;

-- ENUMS via CHECK: NutriGrade A..E; MealType BREAKFAST/LUNCH/DINNER/SNACK; Unit GRAM/ML/PIECE; Sex MALE/FEMALE/OTHER

CREATE TABLE IF NOT EXISTS User (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  passwordHash TEXT NOT NULL,
  refreshTokenHash TEXT,
  name TEXT,
  createdAt TEXT NOT NULL DEFAULT (datetime('now')),
  updatedAt TEXT NOT NULL DEFAULT (datetime('now')),
  onboardingCompleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS Product (
  id TEXT PRIMARY KEY,
  barcode TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  brand TEXT,
  quantity TEXT,
  servingSize TEXT,
  imageUrl TEXT,
  countries TEXT,
  nutriScore TEXT CHECK (nutriScore IN ('A','B','C','D','E')),
  nutriScoreScore INTEGER,
  novaGroup INTEGER,
  ecoScore TEXT,
  categories TEXT,
  labels TEXT,
  allergens TEXT,
  ingredientsText TEXT,
  energyKcal_100g INTEGER,
  proteins_100g REAL,
  carbs_100g REAL,
  sugars_100g REAL,
  fat_100g REAL,
  satFat_100g REAL,
  fiber_100g REAL,
  salt_100g REAL,
  sodium_100g REAL,
  lastFetchedAt TEXT NOT NULL DEFAULT (datetime('now')),
  createdAt TEXT NOT NULL DEFAULT (datetime('now')),
  updatedAt TEXT NOT NULL DEFAULT (datetime('now')),
  off_raw TEXT
);

CREATE INDEX IF NOT EXISTS idx_Product_name ON Product(name);
CREATE INDEX IF NOT EXISTS idx_Product_brand ON Product(brand);
CREATE INDEX IF NOT EXISTS idx_Product_categories ON Product(categories);

CREATE TABLE IF NOT EXISTS Meal (
  id TEXT PRIMARY KEY,
  userId TEXT NOT NULL,
  date TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('BREAKFAST','LUNCH','DINNER','SNACK')),
  notes TEXT,
  totalKcal INTEGER,
  totalProtein REAL,
  totalCarb REAL,
  totalFat REAL,
  createdAt TEXT NOT NULL DEFAULT (datetime('now')),
  updatedAt TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (userId) REFERENCES User(id) ON DELETE CASCADE,
  UNIQUE (userId, date, type)
);

CREATE TABLE IF NOT EXISTS WeightLog (
  id TEXT PRIMARY KEY,
  userId TEXT NOT NULL,
  day TEXT NOT NULL,  -- YYYY-MM-DD
  weightKg REAL NOT NULL,
  createdAt TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (userId) REFERENCES User(id) ON DELETE CASCADE
);
```

> O esquema inclui ainda `UserGoals`, `ProductHistory`, `FavoriteProduct`, `CustomFood`, `CustomMeal`, `CustomMealItem`, `MealItem`, `DailyStats` e *triggers* `updatedAt`.

---

## 📲 Funcionalidades do Frontend (Flutter)

* **Scanner de código de barras/QR**: abre a câmara, lê o código e faz *lookup* local por `barcode`.
* **Pesquisa por nome/marca/categoria** com índices (`LIKE`, prefixo e início de palavra) para rapidez.
* **Detalhe do produto**: mostra NutriScore, NOVA, macros por 100g e por porção, alergénios e rótulos.
* **Adicionar aos registos**: seleciona refeição e quantidade (g/ml/unidade) e grava em `Meal`/`MealItem`.
* **Dashboard**: progresso de calorias usadas vs. meta diária; distribuição por refeição.
* **Estatísticas**: cartões de macros e gráfico da evolução de peso.
* **Favoritos & Histórico**: atalhos para itens frequentes; auditoria de scans (`ProductHistory`).

> **Acessibilidade & UI:** cores e tipografia do **NutriScore Design System**, progress rings/barras animadas, contrastes AA e *motion* subtil. **Não misturar acentos de cor no mesmo componente**; **verdes** reservados a ações primárias.

---

## 🔧 Configuração da BD na App

* Carregar `nutriscore.db` por *asset* (copiar para diretório de dados na 1ª execução) **ou** apontar para um caminho conhecido.
* Certificar‑se que `PRAGMA foreign_keys=ON` está ativo (é definido no schema).
* Índices de pesquisa já incluídos no script SQL.

### Dica: inspecionar a BD local (Android)

```bash
adb shell run-as <package.name> ls databases
adb shell run-as <package.name> cp databases/nutriscore.db /sdcard/
adb pull /sdcard/nutriscore.db .
```

No desktop, abrir com **DB Browser for SQLite**.

---

## 🧪 Qualidade & Performance

* Consultas preparadas e índices (`name`, `brand`, `categories`).
* Cálculos de macros/calorias realizados no momento do registo; agregados diários em `DailyStats`.
* *Triggers* de `updatedAt` para *debug* e futura sincronização.

---

## 🚀 Roadmap (opcional)

* Perfil com preferências (ex.: alerta “muito sal” para hipertensos).
* Sugestões de alternativas mais saudáveis por categoria.
* Rankings por categoria (ex.: “melhor iogurte”).
* Notificações de lembrete de registo.
* Gráficos semanais/mensais.
* Exportação CSV.

---

## 👩‍💻 Contribuir

1. `flutter format .` / `dart analyze`
2. PRs com commits pequenos e mensagens claras
3. Issues com *steps to reproduce* e *logs*

---

## 📜 Licença

* Dados **Open Food Facts**: sujeitos à licença do OFF.
* Código da app: ver ficheiro `LICENSE` no repositório.

---

## 🧭 Resumo do Setup (TL;DR)

```bash
# 1) Construir BD offline
cd DataBaseScraping
python3 convert_csv_db.py

# 2) Correr a app
cd ..
cd Frontend
flutter pub get
flutter run
```

> Projeto **NutriScore** — manter nomes, cores e tipografia conforme `theme.dart`. Qualquer dúvida, abre uma issue. 💚
