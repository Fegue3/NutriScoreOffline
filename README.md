# NutriScore — Alimentação Consciente (Offline-First)

Aplicação móvel **offline** para registo de refeições, análise nutricional simplificada (incl. **NutriScore A–E**), histórico e estatísticas — pensada para estudantes, famílias e pessoas que precisam de controlar sal, açúcar e gordura.

> **Stack:** Flutter · Dart · SQLite (on-device) · Python (pré-processamento de dados) · Dados baseados em **Open Food Facts (OFF)**

---

## ✨ Principais Funcionalidades

- **Leitor de código de barras/QR** para identificar produtos rapidamente.  
- **Consulta offline** a uma base de dados local derivada do **Open Food Facts**.  
- **NutriScore (A–E)** com cores (verde→vermelho) e informação simplificada: calorias, açúcares, gorduras, sal.  
- **Registo de refeições** por tipo (Pequeno-almoço, Almoço, Lanche, Jantar) e cálculo automático de **calorias e macronutrientes**.  
- **Dashboard diário**: progresso de calorias e macros vs. meta.  
- **Estatísticas** (calorias/macros por dia) e **evolução de peso**.  
- **Histórico de produtos pesquisados**, favoritos e itens personalizados.  
- **Autenticação local** (hash em SQLite) + **metas** (calorias/percentuais de macros, preferências).

> **Visão:** tornar simples e acessível monitorizar a ingestão calórica e de macronutrientes, ajudando a cumprir objetivos de saúde — **sem depender de internet**.

---

## 🧱 Abordagem Offline-First (Resumo)

- **SQLite on-device** com esquema otimizado (índices, enums via `CHECK`, triggers em `updatedAt`).  
- **Pipeline local (Python)** que converte CSVs do OFF para **`nutriscore.db`**.  
- App Flutter lê/escreve diretamente na base local — sem API externa para o fluxo principal.  
- Sincronização/online pode ser adicionada depois **sem quebrar** o MVP.

**Fluxo (offline):**
1. **CSV OFF → Python** (`convert_csv_db.py`) limpa/normaliza campos.  
2. **SQLite** é criado com `offline_schema.sql` e populado.  
3. A app consulta por **barcode** e por **texto** (com índices em nome/marca/categoria).

---

## 🌐 Modo Online (Fallback) — Open Food Facts

Quando um produto **não existe** na base local, a NutriScore faz uma consulta **online** à OFF e **guarda** o resultado para uso **offline** futuro.

**Pipeline (4 passos):**
1. Procura local pelo código de barras/QR.  
2. Se não encontrar, faz pedido à OFF com **rate-limit**.  
3. Normaliza (NutriScore A–E, score numérico, NOVA, macros 100g/porção, alergénios, categorias, imagem).  
4. **Upsert** no `nutriscore.db` (inclui JSON original em `off_raw`) e apresenta na UI.

**Boas práticas:** rate-limit + backoff; cache condicional (ETag/Last-Modified); privacidade (envia só o **barcode**); User-Agent “**NutriScore/<versão> (+contacto)**”.

**Estados de UI:**  
Sem rede/erro → “Tentar novamente” · 404 → “Adicionar alimento personalizado” · Sucesso → guarda e mostra.

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
   │  ├─ core/              # theme.dart, estilos/shared widgets
   │  ├─ domain/            # models.dart, entities
   │  ├─ data/              # SQLite (Drift/DAO/queries) + DI
   │  └─ features/
   │     ├─ nutrition/      # log refeições, estatísticas, add food
   │     ├─ home/           # dashboard (progresso diário)
   │     └─ weight/         # gráfico evolução de peso
   └─ assets/
```

---

## 🎨 Design System (NutriScore)

> **Usa sempre as variáveis do `theme.dart`** (cores, tipografia e spacing) — não colocar hex diretamente em widgets.

**Paleta**  
Fresh Green `#4CAF6D` · Warm Tangerine `#FF8A4C` · Leafy Green `#66BB6A` · Golden Amber `#FFC107` · Ripe Red `#E53935`  
Neutros: Charcoal `#333333` · Cool Gray `#666666` · Soft Off-White `#FAFAF7` · Light Sage `#E8F5E9`

**Tipografia**  
Títulos → **Nunito Sans** · Corpo → **Inter** · Números/Dados → **Roboto Mono**

**Regras rápidas**  
- Fresh Green **só** para CTAs principais.  
- Não misturar acentos (verde + laranja) no mesmo componente.  
- Manter contraste **WCAG AA** e animações subtis.  
- Spacing em múltiplos de **4px** (4pt grid).

---

## ▶️ Setup & Execução

### 1) Pré-requisitos
- **Flutter** (canal stable): `flutter doctor` OK.  
- **Python 3.10+** com `pip` (p. ex. `pandas`).

### 2) Construir a base de dados offline

**macOS / Linux (bash)**
```bash
cd DataBaseScraping
python3 convert_csv_db.py
```

**Windows (PowerShell)**
```powershell
cd .\DataBaseScrapingpy -3 .\convert_csv_db.py
# (alternativa, se 'py' não existir)
python .\convert_csv_db.py
```

**Windows (CMD)**
```cmd
cd DataBaseScraping
py -3 convert_csv_db.py
```

O script:
- Lê `products_clean.csv` (derivado OFF)  
- Cria **`nutriscore.db`** a partir de **`offline_schema.sql`**  
- Popula tabelas `Product` e relacionadas

### 3) Correr a aplicação Flutter (debug)

**macOS / Linux (bash)**
```bash
cd ..
cd Frontend
flutter pub get
flutter run
```

**Windows (PowerShell)**
```powershell
cd ..
cd .\Frontendflutter pub get
flutter run
```

**Windows (CMD)**
```cmd
cd ..
cd Frontend
flutter pub get
flutter run
```

### 4) Versão final (otimizada)

- **Executar em modo release (device ligado):**
  ```bash
  flutter run --release
  ```

- **Android – gerar APK/AAB:**
  ```bash
  # APK por ABI (instalação direta)
  flutter build apk --release --split-per-abi

  # App Bundle para Play Store
  flutter build appbundle --release
  ```
  *Instalar APK (exemplo arm64):*
  ```bash
  adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
  ```

- **iOS (macOS + Xcode):**
  ```bash
  flutter build ios --release
  # Depois abrir no Xcode (Runner) e Archive/Distribute (assinatura obrigatória)
  ```

---

## 🗃️ Esquema (SQLite) — Extracto

> Ficheiro: **`DataBaseScraping/offline_schema.sql`** (ver original para o completo)

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
  day TEXT NOT NULL,
  weightKg REAL NOT NULL,
  createdAt TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (userId) REFERENCES User(id) ON DELETE CASCADE
);
```

> O esquema inclui ainda `UserGoals`, `ProductHistory`, `FavoriteProduct`, `CustomFood`, `CustomMeal`, `CustomMealItem`, `MealItem`, `DailyStats` e triggers `updatedAt`.

---

## 📲 Funcionalidades de App (Flutter)

- **Scanner de código de barras/QR** → lookup local por `barcode`.  
- **Pesquisa por nome/marca/categoria** com índices para rapidez.  
- **Detalhe do produto**: NutriScore, NOVA, macros por 100g/porção, alergénios, rótulos.  
- **Adicionar aos registos**: seleciona refeição e quantidade (g/ml/unidade), grava em `Meal`/`MealItem`.  
- **Dashboard**: progresso vs. meta; distribuição por refeição.  
- **Estatísticas**: cartões de macros e gráfico de peso.  
- **Favoritos & Histórico**: atalhos para itens frequentes; auditoria de scans.

> **Acessibilidade & UI:** cores/tipografia do **Design System NutriScore**, progress rings/barras animadas, contrastes AA e *motion* subtil. **Não misturar acentos de cor no mesmo componente**; **verdes** reservados a ações primárias.

---

## 🔧 Configuração da BD na App

- Carregar `nutriscore.db` por **asset** (copiar para diretório de dados na 1ª execução) **ou** apontar para um caminho conhecido.  
- Ativar `PRAGMA foreign_keys = ON`.  
- Índices de pesquisa já incluídos no schema.

**Inspecionar BD local (Android)**
```bash
adb shell run-as <package.name> ls databases
adb shell run-as <package.name> cp databases/nutriscore.db /sdcard/
adb pull /sdcard/nutriscore.db .
# Abrir no desktop com DB Browser for SQLite
```

---

## 🧪 Qualidade & Performance

- Consultas preparadas + índices (`name`, `brand`, `categories`).  
- Cálculos de macros/calorias no registo; agregados diários em `DailyStats`.  
- Triggers `updatedAt` para debug e futura sincronização.  
- Fallback online com rate-limit, cache condicional e upsert transacional.

---

## 🚀 Roadmap (extra)

- Perfil com preferências (ex.: alerta “muito sal” para hipertensos).  
- Sugestões de alternativas por categoria.  
- Rankings por categoria (ex.: “melhor iogurte”).  
- Notificações de lembrete de registo.  
- Gráficos semanais/mensais.  
- Exportação CSV.

---

## 👩‍💻 Contribuir

1. `flutter format .` / `dart analyze`  
2. PRs pequenos e mensagens claras  
3. Issues com *steps to reproduce* e *logs*

---

## 📜 Licenças

- Dados **Open Food Facts**: sujeitos à licença do OFF.  
- Código da app: ver ficheiro `LICENSE` do repositório.

---

## 🧭 TL;DR (Setup Rápido)

**macOS / Linux (bash)**
```bash
# 1) Construir BD offline
cd DataBaseScraping
python3 convert_csv_db.py

# 2) Correr a app (debug)
cd ..
cd Frontend
flutter pub get
flutter run

# 3) Executar versão final (release)
flutter run --release
```

**Windows (PowerShell)**
```powershell
# 1) Construir BD offline
cd .\DataBaseScrapingpy -3 .\convert_csv_db.py

# 2) Correr a app (debug)
cd ..
cd .\Frontendflutter pub get
flutter run

# 3) Executar versão final (release)
flutter run --release
```

> Projeto **NutriScore** — manter nomes, cores e tipografia conforme `theme.dart`. 💚
