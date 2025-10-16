# ⚙️ SETUP – NutriScore

Guia rápido e oficial para preparar o **ambiente de desenvolvimento** e correr o projeto localmente (Backend + Frontend).  
Documentação em **português técnico**, focada no fluxo real do projeto (sem recriar ficheiros que já existem).

---

## 🧩 1) Pré-requisitos

Certifica-te de teres estas ferramentas instaladas:

| Ferramenta | Versão recomendada | Uso |
|-------------|--------------------|-----|
| **Git** | 2.40+ | Clonar e versionar |
| **Node.js** | 18 LTS+ | NestJS + Prisma |
| **Docker / Docker Compose** | 24+ | Base de dados e API |
| **Flutter SDK** | 3.22+ | Aplicação móvel/web |
| **Java 17** |  | Build Android |
| **Make** *(opcional)* |  | Atalhos |
| **OpenSSL** *(opcional)* |  | Gerar chaves JWT |

Verifica rapidamente:
```bash
node -v && npm -v
docker --version && docker compose version
flutter --version
```

---

## 🧱 2) Clonar o projeto

```bash
git clone https://github.com/Fegue3/NutriScore nutriscore
cd nutriscore
```

Estrutura relevante:
```
Backend/api/      → API NestJS + Prisma
Frontend/         → App Flutter
docs/             → Documentação (STRUCTURE.md, etc.)
```

---

## ⚙️ 3) Configurar variáveis de ambiente

### 🔹 Backend

Na pasta `Backend/api`:

```bash
cp .env.example .env
```

O ficheiro `.env.example` já contém todas as variáveis necessárias (`DATABASE_URL`, `JWT_SECRET`, `OFF_BASE_URL`, etc.).  
Revê apenas as credenciais, se mudares portas ou nome da base de dados.

---

## 🐘 4) Base de dados e API

O projeto já inclui um **docker-compose.yml** funcional.

Para levantar o ambiente completo (PostgreSQL + API):

```bash
cd Backend/api
docker compose up -d --build
```

Depois:
```bash
npm install      # se ainda não tiveres node_modules
npx prisma generate
npx prisma migrate deploy   # aplica migrações já existentes
```

Verifica o estado:
```bash
npx prisma studio
```

A API estará disponível em [http://localhost:3000](http://localhost:3000)  
Teste rápido:
```bash
curl http://localhost:3000/health
```

---

## 💻 5) Executar o Backend (modo desenvolvimento)

Se quiseres correr o NestJS fora do Docker (mais rápido para dev):

```bash
cd Backend/api
npm run start:dev
```

A API fica acessível em `http://localhost:3000`.  
O container do Postgres (`db`) continua a correr via Docker.

---

## 📱 6) Executar o Frontend (Flutter)

```bash
cd Frontend
flutter pub get
```

### Emulador Android
```bash
flutter emulators --launch <nome>
flutter run
```
*(usa `10.0.2.2:3000` automaticamente como baseUrl)*

### Dispositivo físico (mesma rede)
```bash
flutter devices
flutter run --dart-define=BACKEND_URL=http://<IP-da-tua-maquina>:3000
```

### Web
```bash
flutter run -d chrome --web-port 5173   --dart-define=BACKEND_URL=http://localhost:3000
```

> ⚠️ **Importante:**  
> - Se mudares de rede, atualiza o `BACKEND_URL`.  
> - O IP da tua máquina pode ser obtido com `ipconfig` (Windows) ou `ifconfig` (macOS/Linux).  
> - Em produção, o `BACKEND_URL` será substituído pelo domínio público (ex.: AWS).

---

## 🌐 7) Open Food Facts (OFF)

Já está configurado no `.env.example`.  
Boas práticas:
- Mantém `OFF_USER_AGENT` personalizado (identificação ética).  
- Respeita o `OFF_RATELIMIT_PER_MINUTE`.  
- O módulo `products` já implementa cache-first + refresh silencioso.

---

## 🧰 8) Troubleshooting (erros comuns)

### 🐞 Flutter: “Invalid file / AndroidManifest.xml not found”  
**Sintomas:**  
```
Error opening archive ... app-debug.apk: Invalid file
Failed to extract manifest from APK
No application found for TargetPlatform.android_x64.
```
**Como resolver:**
```bash
cd Frontend
flutter clean
rm -rf android/.gradle android/build build
flutter pub get
flutter create .  # <- repõe android/ e iOS/ se estiverem corrompidos
flutter run
```
Confirma que existe `android/app/src/main/AndroidManifest.xml`.  
Garante SDK Build‑Tools estável (evita RCs) no Android SDK Manager.

---

### 🌍 API não responde / CORS
- Confirma que o container `api` está ativo (`docker ps`).  
- Verifica `BACKEND_URL` no Flutter.  
- Tokens JWT expirados → volta a autenticar.  
- Se necessário, ativa CORS no `main.ts`:
  ```ts
  app.enableCors({ origin: true, credentials: true });
  ```

---

### 🧩 Prisma: falha de migração
```bash
npx prisma generate
npx prisma migrate deploy
```

---

### 📶 Dispositivo físico não liga à API
- Mesma rede Wi-Fi do PC.  
- Desativa firewall temporariamente.  
- Testa: `http://<IP-PC>:3000/health` no browser do telemóvel.  
- Se necessário, usa túnel (ngrok, Cloudflare) e aponta `BACKEND_URL` para HTTPS público.

---

## 🧩 9) Scripts úteis

**Backend (`Backend/api/package.json`):**
```json
{
  "scripts": {
    "dev": "nest start --watch",
    "build": "nest build",
    "start:prod": "node dist/main.js",
    "migrate": "prisma migrate deploy",
    "studio": "prisma studio"
  }
}
```

**Frontend (Makefile opcional):**
```makefile
run-device:
	flutter run --dart-define=BACKEND_URL=http://$(IP):3000
```

---

## ✅ 10) Checklist de funcionamento

- [ ] `docker compose up -d` subiu o Postgres e API.  
- [ ] `GET /health` retorna **200 OK**.  
- [ ] App Flutter abre o dashboard sem erros.  
- [ ] Login e registo de refeições funcionam.  
- [ ] Scanner (OFF) retorna produtos.  
- [ ] Cache e histórico ativos.  

---

## 🚀 11) Próximos passos

- Configurar **CI/CD** (GitHub Actions ou Railway).  
- Deploy da API (AWS/Fly.io) e build mobile/web.  
- Monitorização (logs, erros, métricas).

---

🟩 **NutriScore** – estrutura pronta, setup rápido, dev simplificado.
