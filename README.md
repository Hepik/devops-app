# DevOps Task

## Крок 1 — застосунок локально (Docker Compose)

React-фронтенд + Node.js/Express-бекенд + PostgreSQL.

```bash
cp .env.example .env
docker compose up --build
```
- Фронтенд: http://localhost:3000
- Бекенд: http://localhost:5000/health, http://localhost:5000/api/items

backend/server.js: retry-підключення до БД на старті, `GET/POST /api/items`,
`GET /health` + `/api/health` (перевіряє реальне з'єднання з БД, не просто
"процес живий"). Dockerfile-и обох сервісів — multi-stage (build stage з
toolchain окремо від легкого runtime).

## Крок 2 — CI/CD → EC2 (замінено Кроком 4, файли видалені)

Був окремий пайплайн через SSH на EC2 (ghcr.io, `docker compose`). Після
переходу на ECS (Крок 3/4) `backend.yml`/`frontend.yml` видалені — ECS
лишається єдиним активним варіантом деплою, щоб не тригерити два пайплайни
на кожен пуш. Підхід (path filters, git-sha теги, needs: між джобами,
smoke-test) переноситься на ECS-пайплайн нижче без змін по суті.

## Крок 3 — Terraform → ECR + ECS Fargate + RDS

Рішення:
- **Fargate**, не EC2 launch type — не дублюємо ручне керування EC2 з Кроку 2
- **Тільки публічні сабнети, без NAT Gateway** — найдорожчий елемент
  інфраструктури, ізоляція йде через Security Groups, не мережеву топологію
- **Файли по темах, без Terraform-модулів** — простіше орієнтуватись на
  етапі навчання
- **Remote state в S3 + DynamoDB lock** — bootstrap (`infra/bootstrap/`)
  створює бакет і таблицю окремо, з локальним стейтом (курка/яйце: бакет
  має існувати до того, як основний проєкт зможе туди писати стан)
- **IAM: окремий non-root користувач** (`terraform-deployer`), не root-акаунт

Файли (`infra/`): `versions.tf`, `providers.tf`, `variables.tf`,
`backend.tf` (S3), `vpc.tf` (VPC + 2 публічні сабнети в різних AZ, IGW,
route table), `security-groups.tf` (ALB ← інтернет, ECS ← тільки ALB,
RDS ← тільки ECS), `ecr.tf` (2 репозиторії, IMMUTABLE теги), `secrets.tf`
(`random_password` → Secrets Manager, 2 секрети: сам пароль і повний
`DATABASE_URL`), `rds.tf` (Postgres, `publicly_accessible = false`,
`skip_final_snapshot = true` для навчального стенду), `iam.tf`
(execution role — pull/logs/secrets; task role — порожня, для майбутнього
розширення), `alb.tf` (Target Groups з `target_type = "ip"` для Fargate,
path-based routing: `/api/*` → backend, решта → frontend), `ecs.tf`
(кластер, CloudWatch log groups, task definitions, сервіси;
`lifecycle { ignore_changes = [task_definition] }` — щоб Terraform не
відкочував деплої, зроблені CI).

## Крок 4 — CI/CD → ECS

`.github/workflows/backend-ecs.yml` / `frontend-ecs.yml`:
build → push в ECR (тег git-sha) → `describe-task-definition` поточної
ревізії → патч тільки `image` через `jq` → `register-task-definition`
(нова ревізія) → `update-service --force-new-deployment` →
`ecs wait services-stable` (це і smoke-test, і механізм "не задеплоїти
зламану версію" — якщо нові задачі не стануть healthy в ALB, wait
падає з таймаутом, workflow червоний).

Потрібні GitHub Secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
(зараз — ключі `terraform-deployer`; це тимчасовий компроміс — керований
CI-користувач з вужчими правами або OIDC без довгоживучих ключів
заплановані в Кроці 6).

## Rollback (ECS)

ECS зберігає **всі** попередні ревізії task definition — жодна не
видаляється автоматично при новому деплої. Відкат:

```bash
# 1. Знайти попередню робочу ревізію
aws ecs list-task-definitions --family-prefix devops-task-backend --sort DESC

# 2. Переключити сервіс на неї
aws ecs update-service \
  --cluster devops-task-cluster \
  --service devops-task-backend \
  --task-definition devops-task-backend:<номер-попередньої-ревізії> \
  --force-new-deployment

# 3. Дочекатись стабілізації (як і в CI)
aws ecs wait services-stable --cluster devops-task-cluster --services devops-task-backend
```

Аналогічно для `devops-task-frontend`. Номер ревізії також видно в
GitHub Actions логах кожного попереднього деплою (крок "Register new
task definition revision").

## Знесення інфраструктури

**Порядок важливий** — спершу основна інфраструктура, бо вона залежить
від bootstrap (S3/DynamoDB), не навпаки:

```bash
cd infra
terraform destroy
```

Підтверди `yes`. Знесе VPC, ECS, RDS (без фінального снепшоту —
`skip_final_snapshot = true`), ALB, ECR (разом з образами всередині),
Secrets Manager секрети, IAM-ролі — усе, чим керує `infra/`.

Потім, **окремо**, bootstrap (тільки якщо проєкт закривається зовсім —
без цього бакета `infra/` більше нікуди не зможе писати стан):

```bash
cd infra/bootstrap
terraform destroy
```

⚠️ Перед цим переконайся, що `infra/destroy` вище **успішно завершився**
— якщо знести bootstrap першим, `infra/` втратить доступ до свого
стану і подальше `destroy` там стане значно складнішим.

Локальні ресурси (Docker-контейнери, образи, volumes) з Кроку 1:
```bash
docker compose down -v
```

## Моніторинг (CloudWatch Container Insights + Grafana)

Рішення: не self-hosted Prometheus/cAdvisor — у Fargate немає доступного
хоста для встановлення таких агентів (це і є суть Fargate). Замість
цього: **Container Insights** (вбудований у ECS механізм збору
CPU/RAM/мережі по кожному сервісу в CloudWatch) + **Grafana локально**
з CloudWatch datasource. Дешевше і простіше за розгортання Prometheus
+ cloudwatch_exporter як окремих Fargate-сервісів, які коштували б
цілодобово.

Grafana працює **локально**, не в AWS — немає сенсу платити за
цілодобово запущений сервіс лише для перегляду дашборда.

```bash
docker run -d -p 3001:3000 --name grafana grafana/grafana
```

Відкрий http://localhost:3001 (логін/пароль за замовчуванням `admin`/`admin`).

**Дані для datasource** (одноразово, з Terraform):
```bash
cd infra
terraform output grafana_cloudwatch_access_key_id
terraform output -raw grafana_cloudwatch_secret_access_key
```

У Grafana: Connections → Data sources → Add → **CloudWatch** →
Authentication Provider: `Access & secret key` → встав значення вище,
Default Region: `eu-central-1` → Save & Test.

**Дашборд:** Dashboards → New → Import → ID `551` ("AWS ECS",
Grafana Labs) → обери щойно доданий CloudWatch datasource → Import.

## Наступні кроки за планом завдання

1. ~~Локально через docker compose~~ ✅
2. ~~CI/CD → EC2~~ ✅ (замінено ECS)
3. ~~Terraform: VPC/SG/ECR/RDS/IAM/ALB/ECS~~ ✅
4. ~~CI/CD → ECS~~ ✅
5. ~~Моніторинг (CloudWatch Container Insights + Grafana локально)~~ ✅
6. Домен, HTTPS, GitHub OIDC (замінити довгоживучі AWS ключі в CI)
