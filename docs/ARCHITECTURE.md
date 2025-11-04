# ARCHITECTURE.md — NutriScore

> Documento de arquitetura do projeto **NutriScore — Alimentação Consciente (Offline-First)**. Foca-se na **estrutura** do sistema (o quê e como se organiza), sem detalhes de implementação nem diagramas.

---

## 1. Objetivo & Escopo
- **Objetivo**: Aplicação móvel para registo de refeições e análise nutricional simplificada, com **NutriScore (A–E)**, a operar **offline-first**.
- **Escopo**: App Flutter com base de dados local **SQLite**; **fallback online** à **Open Food Facts (OFF)** apenas quando um produto não existe na base local.
- **Fora do escopo (MVP)**: sincronização multi-dispositivo, backend próprio e telemetria externa.

---

## 2. Contexto do Sistema
- **Cliente**: Aplicação móvel Flutter (Android/iOS).
- **Fontes de dados**: 
  - **Primária**: Base local `nutriscore.db` (SQLite).
  - **Secundária**: Open Food Facts (consulta remota somente em falta de dados locais).
- **Dependências do dispositivo**: câmara (scanner), armazenamento local, rede (opcional para fallback).

---

## 3. Arquitetura por Camadas (High-Level)
- **UI (Flutter)**: ecrãs, componentes e navegação; theming centralizado via `theme.dart` (cores, tipografia e spacing).
- **Aplicação / Use Cases**: orquestra regras de negócio (registos, pesquisa, cálculo de totais).
- **Repositórios**: expõem operações de dados e decidem entre **DAO local** e **cliente OFF** (fallback).
- **Acesso a Dados (DAO/Drift)**: queries tipadas para SQLite, migrações e índices.
- **Armazenamento**: ficheiro **`nutriscore.db`** no dispositivo.

---

## 4. Modelo de Dados (visão geral textual)
- **Product**: identificação (barcode, nome, marca), **NutriScore (A–E + score)**, **NOVA**, macros por 100g/porção, metadados (categorias, alergénios, imagem) e `off_raw` (payload bruto OFF).
- **Meal**: registos por dia e tipo (BREAKFAST/LUNCH/DINNER/SNACK) com totais agregados.
- **MealItem**: itens associados a uma refeição (quantidade, unidade) com referência ao `Product`.
- **DailyStats**: agregados diários (calorias/macros) por utilizador para leitura eficiente.
- **WeightLog**: evolução de peso diária por utilizador.
- **Histórico & Favoritos**: auditoria de pesquisas/consultas e atalhos para itens frequentes.
- **Possível CustomFood**: itens personalizados definidos pelo utilizador (se incluído no MVP).
- **Índices**: `Product(name)`, `Product(brand)`, `Product(categories)` para pesquisa rápida.
- **Regras**: `CHECK` para enums (A–E, tipos de refeição); triggers `updatedAt` para auditoria.

---

## 5. Fluxos de Dados (alto nível, sem diagramas)
### 5.1 Operação Offline (principal)
1. O utilizador faz **scan** ou **pesquisa**; a app consulta **SQLite** por barcode/texto.
2. A **UI** apresenta detalhes e permite adicionar a uma refeição.
3. O **registo** atualiza `Meal`, `MealItem` e os **agregados** em `DailyStats`.

### 5.2 Fallback Online (apenas quando faltar o produto localmente)
1. Falha a consulta local → chamada à **OFF** com **rate-limit** e backoff.
2. **Normalização** dos campos para o nosso modelo.
3. **Upsert** no SQLite (inclui `off_raw`) e atualização de `lastFetchedAt`.
4. A UI mostra o produto; consultas futuras passam a ser **offline**.

---

## 6. Estratégia Offline-First
- **Local-first**: todas as operações críticas (consulta, registo, estatísticas) funcionam **sem rede**.
- **Base inicial**: `nutriscore.db` pré-construída via pipeline (CSV→SQLite).
- **Retenção**: dados remotos ficam guardados localmente para reutilização futura.
- **Atualização**: apenas quando ocorrer fallback online, com cache condicional (ETag/Last-Modified) quando disponível.

---

## 7. Integração Externa (Open Food Facts)
- **Uso**: apenas quando o produto não existe em SQLite.
- **Boas práticas**: **rate-limit**, **exponential backoff**, **User-Agent** identificável e **sem PII** (apenas barcode).
- **Cache condicional**: validação por ETag/Last-Modified para reduzir tráfego.
- **Transparência**: preservação do payload bruto em `off_raw`.

---

## 8. UX & Design System
- **Theming central** via **`theme.dart`** (Fresh Green para CTAs, Warm Tangerine como secundário, etc.).
- **Acessibilidade**: contraste mínimo **WCAG AA**; não depender apenas de cor.
- **Estados previsíveis**: carregamento/sucesso/erro consistentes e mensagens padrão (“Tentar novamente”, “Adicionar alimento personalizado”).

---

## 9. Segurança & Privacidade
- **Armazenamento local**: dados no SQLite e ficheiros dentro do sandbox da app.
- **Princípio do mínimo privilégio**: solicitar apenas câmara e rede quando necessário.
- **Privacidade**: chamadas à OFF **não** incluem PII; somente o **barcode**.
- **Autenticação local**: hashing e proteção de dados sensíveis a nível de app (se aplicável ao MVP).

---

## 10. Performance
- **Índices** para pesquisa rápida (`name`, `brand`, `categories`).
- **Cálculo** no momento do registo; **agregados** em `DailyStats` para leitura eficiente.
- **I/O**: evitar operações pesadas no main thread; gestão de imagens e cache local.

---

## 11. Configuração & Ambientes
- **Parâmetros** centralizados: caminhos da BD, limites de taxa e user-agent.
- **Ambientes**: desenvolvimento e release (flavors opcionais).

---

## 12. Observabilidade (local)
- **Logging leve** de eventos críticos: scan, fallback, upsert e erros de rede.
- **Sem telemetria externa** no MVP (pode evoluir no futuro).

---

## 13. Testes (abrangência arquitetural)
- **Unit** (mapeamentos e regras), **Widget** (componentes UI) e **Integração** (DAOs com DB in-memory; cliente OFF mockado).
- **Cenários críticos**: scan→fallback→upsert; 404/429/5xx; migrações de schema.

---

## 14. Evolução Futura
- Preferências/alertas (ex.: muito sal), alternativas saudáveis, rankings por categoria, notificações, gráficos semanais/mensais, exportação CSV e eventual sincronização.

---

**Notas finais**  
- Manter a consistência visual e comportamental via `theme.dart`.  
- O **offline-first** é a prioridade; o online serve apenas para colmatar lacunas de dados.
