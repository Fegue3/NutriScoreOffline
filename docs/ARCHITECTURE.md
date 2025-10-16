# 🧠 ARQUITETURA – NutriScore

Documentação técnica detalhada da **arquitetura do projeto NutriScore (MVP)**.  
Abrange camadas, fluxos de dados, integrações externas e componentes principais.

---

## 🏗️ 1. Visão Geral da Arquitetura

O NutriScore é composto por três camadas principais:

```
┌────────────────────────────────────────────────────────────┐
│                        FRONTEND (Flutter)                  │
│  - Interface móvel/web (Android, iOS, Web)                 │
│  - Gestão de estado local, UI e chamadas HTTP (Dio)        │
│  - Leitura de código de barras / QR Code                   │
└───────────────▲────────────────────────────────────────────┘
                │ Requisições REST (JSON, HTTPS)
┌───────────────┴────────────────────────────────────────────┐
│                        BACKEND (NestJS)                    │
│  - API REST modular: Auth, Meals, Products, Weight, Stats  │
│  - Prisma ORM → PostgreSQL                                 │
│  - JWT Auth, validação DTO, rate limiting                  │
│  - Integração externa: Open Food Facts (OFF)               │
└───────────────▲────────────────────────────────────────────┘
                │ ORM (SQL, Prisma)
┌───────────────┴────────────────────────────────────────────┐
│                      BASE DE DADOS (PostgreSQL)            │
│  - Tabelas: Users, Meals, MealItems, Products, WeightLog   │
│  - Índices compostos e constraints (UNIQUE userId+day)     │
│  - Migrações Prisma versionadas                            │
└────────────────────────────────────────────────────────────┘
```

---

## 🔐 2. Autenticação e Autorização

### 2.1 Fluxo de Login

```
[Flutter App]
     │  (POST /auth/login)
     ▼
[AuthController → AuthService]
     │  valida credenciais → compara hash (bcrypt)
     │  gera JWT + refresh token
     ▼
[Frontend recebe tokens]
     │
     ├─ guarda accessToken (secure storage)
     └─ usa Authorization: Bearer <token> nas próximas requisições
```

### 2.2 Tokens

| Tipo | Tempo de vida | Uso |
|------|----------------|-----|
| **Access Token (JWT)** | 15 min – 1 h | Autenticação de cada requisição |
| **Refresh Token** | 7 dias | Renovar sessão sem novo login |

### 2.3 Middleware

- `JwtAuthGuard` → protege rotas privadas.  
- `LocalStrategy` → valida credenciais no login.  
- `RefreshStrategy` → emite novo token quando o anterior expira.  

---

## 🍽️ 3. Gestão de Refeições (Meals)

### 3.1 Estrutura

```
User ──< Meal ──< MealItem ── Product
```

- **Meal**: representa uma refeição (Breakfast, Lunch, Dinner, Snack).  
- **MealItem**: alimento específico dentro da refeição.  
- **Product**: referência cruzada com tabela de produtos OFF (cache local).

### 3.2 Fluxo de criação

```
[App Flutter → POST /meals]
      │  envia tipo (LUNCH), hora e lista de items
      ▼
[MealsService]
      │  cria Meal + MealItems
      ▼
[Prisma ORM]
      │  grava na BD
      ▼
[Resposta → Frontend]
```

### 3.3 Validações

- **1 refeição por tipo/hora configurável**
- **Produtos referenciados por código de barras**
- **Calorias totais** calculadas via somatório `Product.kcal * quantidade`

---

## 🛒 4. Produtos e Integração com Open Food Facts (OFF)

### 4.1 Estratégia de cache-first

```
[App] → GET /products/:barcode
       │
       ▼
[ProductsService]
       │ Verifica cache local (tabela Product)
       ├── encontrado (HIT) → retorna
       ├── não encontrado (MISS) → chama OFF API
       │
       ▼
[OpenFoodFacts API]
       │ retorna JSON → mapeado em DTO → gravado em cache
       ▼
[Resposta final → App]
```

### 4.2 Rate limiting

- Implementado em `off.rate-limit.ts`  
- Permite ~60 requisições/minuto/utilizador  
- Em caso de *limit exceeded*, retorna `429 Too Many Requests`

### 4.3 Estrutura de cache

| Campo | Descrição |
|--------|-----------|
| `barcode` | Identificador único |
| `name` | Nome comercial |
| `nutriments` | Açúcares, gordura, sal, kcal |
| `nutriScore` | A–E |
| `lastUpdated` | ISO datetime |
| `isStale` | boolean (se precisa refresh) |

---

## 🧮 5. Cálculo de Calorias e Metas

### 5.1 Lógica principal

- Cada `MealItem` possui valor energético (`kcal`) obtido do `Product`.  
- O total diário é somado e comparado com a meta (`UserGoals.dailyCalories`).  
- O frontend mostra:
  - Círculo de progresso (calorias consumidas vs meta)
  - Percentagem e cores (`Fresh Green` → dentro da meta, `Ripe Red` → excedido)

### 5.2 API envolvida

| Endpoint | Descrição |
|-----------|------------|
| `GET /calories/today` | Soma calorias do dia atual |
| `GET /goals` | Retorna metas do utilizador |
| `POST /goals` | Atualiza metas diárias |

---

## 🏋️‍♂️ 6. Histórico de Peso (Weight)

### 6.1 Estrutura

| Campo | Tipo | Observações |
|--------|------|-------------|
| `id` | UUID | PK |
| `userId` | FK → User | |
| `day` | Date | único por user |
| `weightKg` | Decimal(5,2) | |
| `source` | string | manual/import/sync |

### 6.2 Regras

- 1 registo por dia/utilizador (`@@unique([userId, day])`).  
- API: `GET /weight/range?days=30`, `POST /weight/upsert`.  
- Frontend mostra gráfico (`WeightTrendCard`) com `fl_chart`.

---

## 📊 7. Estatísticas (Stats)

### 7.1 Objetivo
Fornecer ao utilizador **resumos de consumo** (kcal, macros, progresso) e **tendências semanais**.

### 7.2 Cálculo

- `StatsService` agrega dados de `MealItem` e `WeightLog`.  
- `StatsController` expõe endpoints:
  - `GET /stats/daily`
  - `GET /stats/range?from=...&to=...`

### 7.3 Agregação SQL

```sql
SELECT day,
       SUM(kcal) AS totalKcal,
       SUM(protein_g) AS protein,
       SUM(fat_g) AS fat,
       SUM(sugar_g) AS sugar
FROM "MealItem"
WHERE "userId" = $1
GROUP BY day
ORDER BY day DESC;
```

---

## 📱 8. Frontend (Flutter)

### 8.1 Camadas principais

```
UI → Features → Data → API → Backend
```

| Camada | Descrição |
|--------|------------|
| **UI** | Widgets e ecrãs (`home`, `nutrition`, `settings`, `weight`) |
| **Data** | APIs e repositórios (`auth_api.dart`, `meals_api.dart`, etc.) |
| **Core** | Tema, tipografia, componentes comuns |
| **App** | Router (`GoRouter`) + Injeção (`di.dart`) |

### 8.2 Comunicação com o Backend

- HTTP com `Dio` (timeout 10 s connect / 15 s receive)  
- Headers automáticos (`Authorization: Bearer <token>`)  
- JSON serializado manualmente em cada modelo.  

### 8.3 Gestão de estado
- `StatefulWidget` local → simples e eficaz no MVP.  
- Atualização por setState (sem Bloc/Provider nesta versão).  

---

## 🔁 9. Fluxos de Dados Principais

### 9.1 Login e sessão
```
[User] → Login
   ↓
[AuthController] → JWT
   ↓
[App] guarda token
   ↓
[Subsequent calls → Authorization: Bearer token]
```

### 9.2 Registar refeição
```
[UI - NutritionScreen]
   ↓
POST /meals
   ↓
MealsService (NestJS)
   ↓
Meal + Items gravados (Prisma)
   ↓
Resposta → atualização imediata do dashboard
```

### 9.3 Consulta produto (Scanner)
```
[Flutter Scanner]
   ↓
GET /products/:barcode
   ↓
ProductsService
   ├─ Cache HIT → retorna
   └─ MISS → chama OFF API → grava em cache
   ↓
Frontend mostra NutriScore + info simplificada
```

---

## ⚙️ 10. Boas Práticas Arquiteturais

| Área | Diretriz |
|------|-----------|
| **Backend** | Seguir arquitetura modular (controller/service/module). |
| **Frontend** | Feature-first, UI separada de lógica de dados. |
| **DB** | Índices compostos em campos críticos (`userId+day`). |
| **Auth** | Tokens JWT curtos, refresh seguro, CORS ativo. |
| **OFF** | Cache-first, rate limit respeitado, fallback amigável. |
| **Erros** | Mensagens HTTP consistentes (400/401/403/404/500). |
| **Deploy** | Containers separados (db + api + front). |

---

## 📐 11. Diagrama Global de Fluxo (MVP)

```
┌──────────────────────────────┐
│         Utilizador           │
│  (App NutriScore Flutter)    │
└──────────────┬───────────────┘
               │
               │  HTTPS (JSON, JWT)
               ▼
┌──────────────────────────────┐
│        API NestJS            │
│ Auth / Meals / Products / ...│
│ Prisma ORM + Validations     │
└──────────────┬───────────────┘
               │
               │ SQL (via Prisma)
               ▼
┌──────────────────────────────┐
│      PostgreSQL DB           │
│ users / meals / products /   │
│ weight_logs / goals          │
└──────────────────────────────┘
               │
               │ External API (quando necessário)
               ▼
┌──────────────────────────────┐
│    Open Food Facts (OFF)     │
│  Consulta e cache produtos   │
└──────────────────────────────┘
```

---

## ✅ 12. Conclusão

A arquitetura do NutriScore foi desenhada para ser:
- **Modular** → cada domínio independente (Auth, Meals, Products, Weight, Stats)  
- **Escalável** → fácil extensão futura (ranking, notificações, IA)  
- **Eficiente** → cache local, chamadas otimizadas à OFF, migrações seguras  
- **Portável** → containers Docker, Flutter multiplataforma  

Esta base garante uma **aplicação sólida, documentada e sustentável** para evoluções futuras.

---

🟩 **NutriScore – Arquitetura Técnica do MVP**
