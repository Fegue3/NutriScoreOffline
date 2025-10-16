# 📁 Estrutura do Projeto – NutriScore

Este documento descreve em detalhe a **estrutura técnica** do projeto **NutriScore**, abrangendo tanto o **Backend (NestJS + Prisma)** como o **Frontend (Flutter)**.  
O objetivo é fornecer uma visão clara sobre a organização do código, responsabilidades de cada módulo e boas práticas de extensão.

---

## 🏗️ Visão Geral

O **NutriScore** é composto por dois grandes componentes:

- **Backend (`Backend/api`)** → API REST construída com **NestJS** e **Prisma ORM** (PostgreSQL), responsável pela lógica de negócio, autenticação e persistência de dados.  
- **Frontend (`Frontend/`)** → Aplicação **Flutter** multiplataforma (Android, iOS, Web), responsável pela interface do utilizador, comunicação com a API e visualização dos dados.

Ambos os componentes são orquestrados via **Docker Compose**, com suporte a `.env` para configuração de ambiente.

---

## ⚙️ Backend (`Backend/api`)

### 📂 Estrutura Geral

```
Backend/
└── api/
    ├── prisma/
    │   ├── migrations/
    │   └── schema.prisma
    ├── src/
    │   ├── auth/
    │   ├── calories/
    │   ├── goals/
    │   ├── health/
    │   ├── meals/
    │   ├── prisma/
    │   ├── products/
    │   ├── stats/
    │   ├── users/
    │   ├── weight/
    │   ├── app.controller.spec.ts
    │   ├── app.controller.ts
    │   ├── app.module.ts
    │   ├── app.service.ts
    │   └── main.ts
    ├── Dockerfile
    ├── .env / .env.example
    ├── package.json
    ├── tsconfig.json / tsconfig.build.json
    └── nest-cli.json
```

---

### 🧩 Organização por Módulos

Cada domínio do sistema segue o padrão **NestJS modular**, composto por:
- `*.controller.ts` → define endpoints HTTP (REST)
- `*.service.ts` → contém a lógica de negócio e integrações
- `*.module.ts` → agrupa controladores e serviços, exportando o módulo para uso global
- `dto/` → *Data Transfer Objects* para validação e tipagem dos requests/responses

---

### 🔐 Módulo `auth/`
Responsável por autenticação e autorização de utilizadores.

- **`auth.controller.ts`** – Endpoints de login, signup e refresh tokens.  
- **`auth.service.ts`** – Lógica de hashing, verificação e emissão de tokens JWT.  
- **`auth.guards.ts`** – Guards de segurança (`JwtAuthGuard`, `LocalAuthGuard`).  
- **`auth.strategies.ts`** – Estratégias Passport (JWT + Local).  
- **`auth.module.ts`** – Declara e exporta o módulo de autenticação.

---

### 🍽️ Módulo `meals/`
Gerencia as refeições e os itens associados a cada utilizador.

- **`meals.controller.ts`** – CRUD de refeições (listar, criar, editar, apagar).  
- **`meals.service.ts`** – Integração com Prisma para manipulação de `Meal` e `MealItem`.  
- **`meals.dto.ts`** – Estrutura de dados de entrada (tipo de refeição, hora, alimentos, etc.).  
- **`meals.module.ts`** – Agrupa e exporta o módulo.

---

### 🧮 Módulo `calories/`
Responsável pelos cálculos calóricos e resumo diário.

- **`calories.controller.ts`** – Endpoints para metas e totais de calorias.  
- **`calories.service.ts`** – Funções de agregação e estatísticas.  
- **`calories.module.ts`** – Definição do módulo.

---

### 🎯 Módulo `goals/`
Gerencia as metas nutricionais e objetivos do utilizador.

- **`goals.controller.ts`** – CRUD de metas (calorias, macros, peso, etc.).  
- **`goals.service.ts`** – Armazena e recupera metas personalizadas.  
- **`goals.module.ts`** – Módulo independente, utilizado por `calories` e `stats`.

---

### 🧠 Módulo `health/`
Endpoints para **monitorização de saúde** e verificação de status da API.

- **`health.controller.ts`** – Endpoint `/health` para checagem de disponibilidade.

---

### 🏋️‍♂️ Módulo `weight/`
Gerencia o histórico de peso e progresso do utilizador.

- **`dto/`**
  - `upsert-weight.dto.ts` → Criação/atualização de registo de peso.
  - `weight-range.dto.ts` → Filtro por intervalo de datas.
- **`weight.controller.ts`** – Endpoints para CRUD de peso.
- **`weight.service.ts`** – Lógica de cálculo e persistência.
- **`weight.module.ts`** – Módulo do domínio.

---

### 🛒 Módulo `products/`
Responsável pela integração com **Open Food Facts (OFF)** e cache local de produtos.

- **`dto/`** – Modelos de produtos e resposta OFF.
- **`off.client.ts`** – Cliente HTTP para acesso à API OFF.
- **`off.rate-limit.ts`** – Implementa limites de requisição por minuto/usuário.
- **`products.controller.ts`** – Endpoints `/products` (pesquisa, detalhes, cache).
- **`products.service.ts`** – Lógica de caching (cache-first + stale refresh).
- **`products.module.ts`** – Define o módulo e dependências.

---

### 📊 Módulo `stats/`
Recolhe estatísticas diárias e médias nutricionais.

- **`dto/`**
  - `daily.dto.ts` – Estrutura para dados diários.
  - `day-nutrients.dto.ts` – Nutrientes por dia.
  - `range.dto.ts` – Intervalos personalizados.
- **`stats.controller.ts` / `stats.service.ts` / `stats.module.ts`**

---

### 👤 Módulo `users/`
Gerencia perfis de utilizadores e endpoints relacionados.

- **`users.controller.ts`** – Operações administrativas.  
- **`users.me.controller.ts`** – Operações do próprio utilizador autenticado (`/me`).  
- **`users.service.ts` / `users.module.ts`** – CRUD de perfis e integração com Auth.

---

### 🧩 Prisma (`prisma/`)
- **`schema.prisma`** – Define o modelo de dados (User, Meal, Product, WeightLog, etc.).  
- **`migrations/`** – Histórico de migrações automáticas.  
- **`prisma.module.ts` / `prisma.service.ts`** – Integração de Prisma como provider global do NestJS.

---

### ⚙️ Ficheiros Principais
- **`main.ts`** – Ponto de entrada da aplicação NestJS.  
- **`app.module.ts`** – Módulo raiz que importa todos os outros módulos.  
- **`Dockerfile`** – Build da API em container.  
- **`.env.example`** – Exemplo de variáveis de ambiente (DB, JWT, OFF, etc.).  
- **`package.json`** – Dependências e scripts (`start:dev`, `build`, `migrate`).  
- **`tsconfig*.json` / `nest-cli.json`** – Configurações de compilação e paths internos.

---

## 🎨 Frontend (`Frontend/`)

### 📂 Estrutura Geral

```
Frontend/
├── assets/
│   ├── fonts/
│   └── utils/
├── lib/
│   ├── app/
│   │   ├── router/
│   │   ├── app_shell.dart
│   │   └── di.dart
│   ├── core/
│   │   ├── widgets/
│   │   ├── constants.dart
│   │   ├── env.dart
│   │   └── theme.dart
│   ├── data/
│   │   ├── repositories/
│   │   ├── auth_api.dart
│   │   ├── meals_api.dart
│   │   ├── products_api.dart
│   │   ├── stats_api.dart
│   │   └── weight_api.dart
│   ├── features/
│   │   ├── auth/
│   │   ├── home/
│   │   ├── nutrition/
│   │   ├── scanner/
│   │   ├── settings/
│   │   └── weight/
│   ├── utils/
│   │   └── result.dart
│   └── main.dart
├── docker-compose.yml
└── pubspec.yaml
```

---

### 🧩 Estrutura Modular (Feature-based)

O projeto segue a convenção **feature-first**, onde cada área funcional possui a sua própria pasta e lógica.

---

### 🌱 `lib/app/`
Contém a configuração **base da aplicação**:
- **`router/`** → Definição de rotas com `GoRouter` (navegação principal).  
- **`app_shell.dart`** → Estrutura principal da aplicação (bottom nav + scaffold).  
- **`di.dart`** → Injeção de dependências (repositórios, APIs, storage, etc.).

---

### 🎨 `lib/core/`
Inclui **recursos reutilizáveis globais**.

- **`theme.dart`** – Define cores, tipografia e espaçamento, importando variáveis do design system.  
- **`widgets/`** – Componentes visuais genéricos (ex.: gráficos, cards, progress bars).  
- **`constants.dart`** – Constantes globais da app.  
- **`env.dart`** – Configurações de ambiente (dev/prod).  

---

### 🔗 `lib/data/`
Camada de **acesso a dados e APIs**.

- **`repositories/`** – Abstrações sobre APIs (autenticação, refeições, produtos, etc.).  
- **`*_api.dart`** – Implementações diretas com `Dio`, comunicando com o backend NestJS.  
- **`auth_storage.dart`** – Gestão segura do token JWT.  

---

### 📱 `lib/features/`
Cada pasta representa uma **funcionalidade da app**:

- **`auth/`** → Onboarding, login, registo, sessão guard.  
- **`home/`** → Dashboard diário com calorias e macros.  
- **`nutrition/`** → Ecrãs de registo e análise nutricional (com integração OFF).  
- **`scanner/`** → Leitura de código de barras / QR Code e busca de produtos.  
- **`settings/`** → Gestão de conta, exportação de dados, limpeza de cache.  
- **`weight/`** → Gráficos e histórico de peso do utilizador.  

Cada subpasta contém *screens* (`*_screen.dart`), e, quando necessário, widgets e controladores específicos.

---

### ⚙️ `lib/utils/`
Funções utilitárias genéricas e classes de resultado (`Result<T>`).

---

### 🚀 `main.dart`
Ponto de entrada da aplicação Flutter.  
Configura o tema, inicializa dependências e define o `AppRouter`.

---

## 🧭 Boas Práticas de Estrutura

- Seguir o padrão **feature-first** tanto no backend (módulos) como no frontend (features).  
- Cada módulo deve conter a sua **camada de dados**, **serviço** e **apresentação**.  
- Reutilizar componentes globais em `core/widgets`.  
- Respeitar convenções de naming:
  - `*_controller.ts` → Controladores HTTP (NestJS)
  - `*_service.ts` → Lógica de negócio / API
  - `*_dto.ts` → Estrutura de dados (DTO)
  - `*_screen.dart` → Ecrãs Flutter
- Evitar lógica duplicada entre frontend e backend.  
- Manter variáveis sensíveis fora do código (em `.env`).

---

## 🧩 Resumo Visual (simplificado)

```
┌──────────────────────────────────────────────────────────┐
│                      NUTRISCORE                           │
├──────────────────────────────────────────────────────────┤
│ Backend (NestJS + Prisma)                                │
│  ├─ Auth / Users / Meals / Products / Stats / Weight      │
│  ├─ Prisma ORM → PostgreSQL                              │
│  └─ Docker + .env + JWT + OFF API                         │
│                                                          │
│ Frontend (Flutter)                                       │
│  ├─ lib/app → Router + DI + Shell                        │
│  ├─ lib/core → Theme + Widgets + Env                     │
│  ├─ lib/data → APIs + Repositories                       │
│  ├─ lib/features → Auth / Home / Nutrition / Settings     │
│  └─ main.dart → Boot + ThemeConfig                        │
└──────────────────────────────────────────────────────────┘
```

---

## ✅ Conclusão

A estrutura do NutriScore foi desenhada para ser **modular, escalável e facilmente navegável**, permitindo evolução independente entre backend e frontend.  
A separação clara entre **domínios funcionais** e **camadas técnicas** simplifica a manutenção, favorece testes unitários e reduz o acoplamento entre componentes.

---
