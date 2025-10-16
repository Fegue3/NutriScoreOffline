# 🔗 REFERÊNCIA DE API – NutriScore (MVP)

Documentação técnica resumida da **API REST** do projeto **NutriScore**, cobrindo apenas o **MVP atual**.  
Formato profissional, com exemplos e códigos de resposta.

---

## ⚙️ Informações Gerais

- **Base URL (local)**: `http://localhost:3000`
- **Base URL (LAN física)**: `http://<ip-da-maquina>:3000`
- **Base URL (produção futura)**: `https://api.nutriscore.pt` (placeholder)

### Autenticação

- Todas as rotas (exceto `/auth/*`) requerem JWT.  
- Envia o header padrão:
  ```http
  Authorization: Bearer <access_token>
  ```

### Content-Type
```http
Content-Type: application/json
Accept: application/json
```

---

## 🔐 1. AUTHENTICAÇÃO (`/auth`)

| Método | Rota | Descrição |
|---------|------|-----------|
| `POST` | `/auth/signup` | Cria nova conta de utilizador |
| `POST` | `/auth/login` | Login e geração de tokens |
| `POST` | `/auth/refresh` | Gera novo token de acesso |
| `POST` | `/auth/logout` | Invalida refresh token ativo |

### Exemplo – Login
**Request**
```json
POST /auth/login
{
  "email": "teste@exemplo.com",
  "password": "123456"
}
```
**Response**
```json
{
  "accessToken": "eyJhbGciOi...",
  "refreshToken": "eyJhbGciOi..."
}
```

### Códigos HTTP
| Código | Significado |
|--------|--------------|
| `200 OK` | Login ou signup com sucesso |
| `400 Bad Request` | Campos inválidos |
| `401 Unauthorized` | Credenciais incorretas |
| `409 Conflict` | Email já registado |

---

## 👤 2. UTILIZADOR (`/users`)

| Método | Rota | Descrição |
|---------|------|-----------|
| `GET` | `/users/me` | Retorna perfil do utilizador autenticado |
| `PATCH` | `/users/me` | Atualiza dados básicos (nome, email, etc.) |

**Exemplo**
```json
GET /users/me
→ 200 OK
{
  "id": "uuid",
  "email": "teste@exemplo.com",
  "name": "João",
  "createdAt": "2025-10-10T12:00:00Z"
}
```

---

## 🍽️ 3. REFEIÇÕES (`/meals`)

| Método | Rota | Descrição |
|---------|------|-----------|
| `GET` | `/meals/day?date=YYYY-MM-DD` | Lista refeições de um dia |
| `POST` | `/meals` | Cria uma refeição e os seus itens |
| `DELETE` | `/meals/:id` | Remove refeição |
| `PATCH` | `/meals/:id` | Atualiza refeição existente |

### Exemplo – Criar refeição
```json
POST /meals
{
  "type": "LUNCH",
  "items": [
    { "productId": "barcode_123", "quantity": 150 }
  ]
}
```
**Response**
```json
{
  "id": "meal-uuid",
  "totalCalories": 520,
  "items": [
    { "productId": "barcode_123", "name": "Iogurte Natural", "kcal": 520 }
  ]
}
```

### Códigos HTTP
| Código | Significado |
|--------|--------------|
| `200 OK` | Sucesso |
| `201 Created` | Refeição criada |
| `400 Bad Request` | Dados inválidos |
| `401 Unauthorized` | Falha de autenticação |

---

## 🛒 4. PRODUTOS (`/products`)

| Método | Rota | Descrição |
|---------|------|-----------|
| `GET` | `/products/:barcode` | Retorna produto (cache + OFF API) |
| `GET` | `/products/search?q=termo` | Pesquisa por nome |
| `DELETE` | `/products/cache/clear` | Limpa cache local (admin/dev) |

### Exemplo – Consultar produto
```
GET /products/5601007002180
→ 200 OK
```
```json
{
  "barcode": "5601007002180",
  "name": "Bolachas Maria",
  "nutriScore": "C",
  "kcal": 432,
  "fat": 11.0,
  "sugars": 23.0,
  "salt": 0.4
}
```

**Notas**
- Estratégia **cache-first**: consulta local antes da OFF API.  
- Se `isStale = true`, a API atualiza em background.  

---

## 🧮 5. CALORIAS E METAS (`/calories`, `/goals`)

| Método | Rota | Descrição |
|---------|------|-----------|
| `GET` | `/calories/today` | Total de calorias consumidas hoje |
| `GET` | `/goals` | Retorna metas do utilizador |
| `POST` | `/goals` | Atualiza metas diárias |

**Response exemplo `/calories/today`**
```json
{
  "goal": 2200,
  "consumed": 1750,
  "remaining": 450
}
```

---

## 🏋️‍♂️ 6. PESO (`/weight`)

| Método | Rota | Descrição |
|---------|------|-----------|
| `GET` | `/weight/range?days=30` | Histórico de peso (últimos N dias) |
| `POST` | `/weight/upsert` | Cria ou atualiza registo diário |

**Request exemplo**
```json
POST /weight/upsert
{
  "day": "2025-10-10",
  "weightKg": 72.4
}
```
**Response**
```json
{
  "day": "2025-10-10",
  "weightKg": 72.4,
  "trend": "down"
}
```

---

## 📊 7. ESTATÍSTICAS (`/stats`)

| Método | Rota | Descrição |
|---------|------|-----------|
| `GET` | `/stats/daily` | Dados agregados do dia atual |
| `GET` | `/stats/range?from=2025-10-01&to=2025-10-10` | Estatísticas por intervalo |

**Response exemplo**
```json
{
  "from": "2025-10-01",
  "to": "2025-10-10",
  "averageCalories": 2100,
  "averageProtein": 95,
  "averageFat": 70,
  "averageSugar": 45
}
```

---

## ⚠️ 8. Códigos de Resposta Padrão

| Código | Descrição | Contexto |
|--------|------------|----------|
| `200 OK` | Sucesso geral | GET / POST válidos |
| `201 Created` | Novo registo criado | POST /meals, /goals |
| `204 No Content` | Remoção bem-sucedida | DELETE |
| `400 Bad Request` | Dados inválidos | Campos ausentes |
| `401 Unauthorized` | Token inválido/expirado | Sem JWT |
| `403 Forbidden` | Acesso negado | Outro utilizador |
| `404 Not Found` | Recurso inexistente | Barcode inválido |
| `429 Too Many Requests` | Rate limit OFF atingido | /products |
| `500 Internal Server Error` | Erro inesperado | Geral |

---

## ✅ 9. Boas Práticas de Uso

- Inclui sempre `Authorization` nas rotas privadas.  
- Usa HTTPS em produção.  
- Respeita limites de requisições da Open Food Facts.  
- Evita chamadas excessivas ao mesmo endpoint (usa cache local).  
- Em erros 401, força reautenticação ou refresh automático.

---

🟩 **NutriScore – API REST Reference (MVP)**
