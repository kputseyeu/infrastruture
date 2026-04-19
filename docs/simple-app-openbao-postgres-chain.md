# Simple App → OpenBao → PostgreSQL: полная цепочка

## Архитектура

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Kubernetes Cluster                                  │
│                                                                              │
│  ┌──────────────────────────┐              ┌──────────────────────────┐     │
│  │      simple-app          │              │      PostgreSQL          │     │
│  │      (Deployment)        │              │      (StatefulSet)       │     │
│  │                          │              │                          │     │
│  │  ┌────────────────────┐  │              │  ┌────────────────────┐  │     │
│  │  │  Container         │  │              │  │  postgres:16.4     │  │     │
│  │  │                    │  │              │  │  port: 5432        │  │     │
│  │  │  env:              │  │              │  │  DB: appdb         │  │     │
│  │  │    DB_HOST ────────┼──┼─────────────▶│  │  User: appuser     │  │     │
│  │  │    DB_PORT=5432    │  │  TCP         │  │  Pass: ****        │  │     │
│  │  │    DB_NAME=appdb   │  │              │  │                    │  │     │
│  │  │    DB_USER=appuser │  │              │  └────────────────────┘  │     │
│  │  │    DB_PASSWORD=*** │  │              │                          │     │
│  │  │                    │  │              │  PVC: local-path         │     │
│  │  │  Port: 3000        │  │              │  Node: worker-01         │     │
│  │  └────────────────────┘  │              └──────────────────────────┘     │
│  │                          │                                                │
│  │  Вolumes:                │              ┌──────────────────────────┐     │
│  │  - kube-api-access       │              │   External Secrets       │     │
│  │                          │              │   Operator (ESO)         │     │
│  │  ServiceAccount:         │              │                          │     │
│  │    login-app-sa ─────────┼──────────────┼──▶ JWT Token             │     │
│  └──────────────────────────┘              │                          │     │
│         │                                  │  Pod: external-secrets   │     │
│         │                                  └────────────┬─────────────┘     │
│         │                                               │                   │
│         │  1. ESO сканирует                             │                   │
│         │     ExternalSecret                            │  2. ESO берёт JWT │
│         │     каждые 5 минут                            │     у SA          │
│         ▼                                               ▼                   │
└─────────┼───────────────────────────────────────────────┼───────────────────┘
          │                                               │
          │  6. ESO создаёт/обновляет                     │  3. PUT /v1/auth/
          │     Secret "simple-app-secrets"               │     kubernetes/login
          │     в namespace default                       │     {role, jwt}
          │                                               │     (TLS :8200)
          ▼                                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          OpenBao (10.10.0.30:8200)                           │
│                                                                              │
│  4. OpenBao получает JWT → идёт в K8s API (10.10.0.10:6443)                │
│     POST /apis/authentication.k8s.io/v1/tokenreviews                         │
│     (token_reviewer_jwt от SA default:default)                               │
│                                                                              │
│  5. K8s подтверждает: SA login-app-sa в namespace default валиден            │
│                                                                              │
│  6. Проверяет роль "login-app-role":                                         │
│     - bound_service_account_names: [login-app-sa] ✓                          │
│     - bound_service_account_namespaces: [default] ✓                          │
│     - policies: [login-app-policy]                                           │
│                                                                              │
│  7. Проверяет политику "login-app-policy":                                   │
│     path "secrets/data/simple-app/*" { capabilities = ["read"] } ✓           │
│                                                                              │
│  8. Отдаёт секрет:                                                           │
│     secrets/data/simple-app/db → {host, port, database, user, password}      │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Пошаговое описание

| Шаг | Кто | Куда | Протокол | Что происходит |
|-----|-----|------|----------|----------------|
| 1 | ESO pod | K8s API | HTTPS :6443 | Получает JWT токен для `login-app-sa` через TokenRequest API |
| 2 | ESO pod | OpenBao | HTTPS :8200 (TLS) | Авторизуется через K8s auth method: `PUT /v1/auth/kubernetes/login` |
| 3 | OpenBao | K8s API | HTTPS :6443 | Валидирует JWT через TokenReview API |
| 4 | K8s API | OpenBao | — | Подтверждает: SA `login-app-sa` в `default` валиден |
| 5 | OpenBao | — | — | Проверяет роль `login-app-role` (SA name + namespace) |
| 6 | OpenBao | — | — | Проверяет политику `login-app-policy` (read доступ к пути) |
| 7 | OpenBao | ESO pod | HTTPS :8200 | Отдаёт секрет: `{host, port, database, user, password}` |
| 8 | ESO pod | K8s API | HTTPS :6443 | Создаёт Secret `simple-app-secrets` в namespace `default` |
| 9 | Kubelet | simple-app pod | — | Монтирует Secret как env vars в контейнер |
| 10 | simple-app | PostgreSQL | TCP :5432 | Подключается к БД используя переменные окружения |

## Компоненты

### OpenBao

| Параметр | Значение |
|----------|----------|
| Адрес | `https://10.10.0.30:8200` |
| TLS | Self-signed cert с SAN: `IP:10.10.0.30`, `DNS:openbao-01` |
| Auth method | Kubernetes (`/auth/kubernetes`) |
| KV engine | v2 (`secrets/`) |

### Роль в OpenBao

```
Role: login-app-role
  bound_service_account_names:      [login-app-sa]
  bound_service_account_namespaces: [default]
  policies:                         [login-app-policy]
  ttl:                              1h
```

### Политика в OpenBao

```hcl
# login-app-policy
path "secrets/data/login-app/*" {
  capabilities = ["read"]
}
path "secrets/data/simple-app/*" {
  capabilities = ["read"]
}
```

### Kubernetes RBAC

| Resource | Namespace | Назначение |
|----------|-----------|------------|
| SA `login-app-sa` | default | Идентификатор для ESO → OpenBao |
| SA `default` | default | TokenReviewer (ClusterRole `system:auth-delegator`) |

### External Secrets Operator

| Параметр | Значение |
|----------|----------|
| Chart | `external-secrets/external-secrets` (Helm) |
| API version | `external-secrets.io/v1` |
| Refresh interval | 5m |

### PostgreSQL

| Параметр | Значение |
|----------|----------|
| Chart | `helm/postgresql` |
| Image | `postgres:16.4-alpine` |
| Node affinity | `worker-01` |
| Storage | `local-path`, 10Gi |
| Database | `appdb` |
| User | `appuser` |

## Конфигурация

### SecretStore (namespace: default)

```yaml
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: openbao-backend
  namespace: default
spec:
  provider:
    vault:
      server: "https://10.10.0.30:8200"
      path: "secrets"
      version: "v2"
      caBundle: "<base64-encoded cert>"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "login-app-role"
          serviceAccountRef:
            name: "login-app-sa"
```

### ExternalSecret (namespace: default)

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: simple-app-db-creds
  namespace: default
spec:
  refreshInterval: "5m"
  secretStoreRef:
    name: openbao-backend
    kind: SecretStore
  target:
    name: simple-app-secrets
    creationPolicy: Owner
  data:
    - secretKey: DB_HOST
      remoteRef:
        key: "simple-app/db"
        property: host
    - secretKey: DB_PORT
      remoteRef:
        key: "simple-app/db"
        property: port
    - secretKey: DB_NAME
      remoteRef:
        key: "simple-app/db"
        property: database
    - secretKey: DB_USER
      remoteRef:
        key: "simple-app/db"
        property: user
    - secretKey: DB_PASSWORD
      remoteRef:
        key: "simple-app/db"
        property: password
```

### Deployment (envFrom)

```yaml
containers:
  - name: simple-app
    image: ghcr.io/kputseyeu/simple-app:latest
    envFrom:
      - configMapRef:
          name: simple-app-config
      - secretRef:
          name: simple-app-secrets
```

### Секрет в OpenBao

```bash
bao kv put secrets/simple-app/db \
  host='postgresql.default.svc.cluster.local' \
  port='5432' \
  database='appdb' \
  user='appuser' \
  password='postgres-secure-pass-2026'
```

## Переменные окружения в поде

После синхронизации контейнер `simple-app` получает:

```
DB_HOST=postgresql.default.svc.cluster.local
DB_PORT=5432
DB_NAME=appdb
DB_USER=appuser
DB_PASSWORD=postgres-secure-pass-2026
```

Приложение использует их для подключения:

```javascript
const db = new Client({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});
```

## Безопасность

- **TLS** — все соединения ESO → OpenBao зашифрованы
- **JWT** — одноразовые токены с TTL 1h, генерируются K8s API
- **Least privilege** — политика разрешает только `read` к `secrets/data/simple-app/*`
- **Namespace isolation** — роль привязана к namespace `default`
- **etcd encryption** — секреты шифруются на диске (secretbox в Kubespray)
- **Нет plaintext секретов** — пароль никогда не хранится в git или manifests

## Ротация паролей

1. Обновить пароль в OpenBao:
   ```bash
   bao kv put secrets/simple-app/db password='new-password'
   ```
2. ESO подтянет автоматически в течение 5 минут (refreshInterval)
3. K8s Secret `simple-app-secrets` обновится автоматически
4. Pod `simple-app` нужно перезапустить для применения нового пароля:
   ```bash
   kubectl rollout restart deployment simple-app
   ```

## Troubleshooting

```bash
# Статус ExternalSecret
kubectl get externalsecret simple-app-db-creds

# Статус SecretStore
kubectl get secretstore openbao-backend

# Содержимое секрета (проверка)
kubectl get secret simple-app-secrets -o jsonpath='{.data.DB_HOST}' | base64 -d

# Логи ESO
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50

# Логи приложения
kubectl logs -l app.kubernetes.io/instance=simple-app --tail=50

# Тестовый логин в OpenBao
SA_TOKEN=$(kubectl create token login-app-sa -n default --duration=1h)
bao write auth/kubernetes/login role=login-app-role jwt=$SA_TOKEN

# Проверка подключения к PostgreSQL из пода
kubectl exec -it deploy/simple-app -- sh -c 'echo "SELECT 1" | nc postgresql.default.svc.cluster.local 5432'
```
