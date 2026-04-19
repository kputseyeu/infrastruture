# ESO + OpenBao: полная цепочка

## Архитектура

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                            │
│                                                                      │
│  ┌──────────────────────┐     ┌──────────────────────────────┐      │
│  │  external-secrets    │     │         argocd               │      │
│  │  (ESO operator pod)  │     │                              │      │
│  │                      │     │  ┌──────────────────────┐    │      │
│  │  1. Каждые 5 минут   │     │  │ argocd-eso-sa (SA)   │    │      │
│  │     сканирует        │     │  │                      │    │      │
│  │     ExternalSecret   │     │  │  JWT Token           │    │      │
│  │     "argocd-admin-   │─────┼─▶│  (автосгенерённый    │      │
│  │     password"        │     │  │   K8s API)           │    │      │
│  │                      │     │  └──────────────────────┘    │      │
│  │  2. Берёт JWT токен  │     │                              │      │
│  │     SA argocd-eso-sa │     │  ┌──────────────────────┐    │      │
│  │                      │     │  │ argocd-admin-        │    │      │
│  │  8. Обновляет K8s    │     │  │ password-secret      │    │      │
│  │     Secret           │◀────┼──│  (создан ESO)        │      │
│  └──────────────────────┘     │  └──────────────────────┘    │      │
│         │                     │                              │      │
│         │                     │  ┌──────────────────────┐    │      │
│         │                     │  │ argocd-server (pod)  │    │      │
│         │                     │  │                      │    │      │
│         │                     │  │  Читаёт secret       │    │      │
│         │                     │  │  при необходимости   │    │      │
│         │                     │  └──────────────────────┘    │      │
└─────────┼────────────────────────────────────────────────────┘      │
          │ 3. PUT /v1/auth/kubernetes/login                          │
          │    {role: "argocd-role", jwt: "<token>"}                  │
          │    (TLS, порт 8200)                                       │
          │                                                          │
          ▼                                                          │
┌──────────────────────────────────────────────────────────────────┐  │
│  OpenBao (10.10.0.30:8200)                                       │  │
│                                                                   │  │
│  4. Получает JWT → идёт в K8s API (10.10.0.10:6443)             │  │
│     POST /apis/authentication.k8s.io/v1/tokenreviews              │  │
│     (token_reviewer_jwt от SA default:default)                    │  │
│                                                                   │  │
│  5. K8s подтверждает: SA argocd-eso-sa в namespace argocd ───────┘  │
│     валиден                                                        │
│                                                                   │
│  6. Проверяет роль "argocd-role":                                  │
│     - bound_service_account_names: argocd-eso-sa ✓                │
│     - bound_service_account_namespaces: argocd ✓                  │
│     - policies: argocd-policy                                     │
│                                                                   │
│  7. Проверяет политику "argocd-policy":                           │
│     path "secrets/data/argocd/*" { capabilities = ["read"] }      │
│                                                                   │
│  8. Отдаёт секрет:                                               │
│     secrets/data/argocd/admin-password → password: "rwbe4aq..."   │
└──────────────────────────────────────────────────────────────────┘
```

## Пошаговое описание

| Шаг | Кто | Куда | Протокол | Зачем |
|-----|-----|------|----------|-------|
| 1 | ESO pod | K8s API | HTTPS :6443 | Получить JWT для `argocd-eso-sa` через TokenRequest API |
| 2 | ESO pod | OpenBao | HTTPS :8200 (TLS) | Авторизоваться через K8s auth method |
| 3 | OpenBao | K8s API | HTTPS :6443 | Валидировать JWT через TokenReview API |
| 4 | OpenBao | — | — | Проверить роль `argocd-role` (SA name + namespace) |
| 5 | OpenBao | — | — | Проверить политику `argocd-policy` (read доступ к пути) |
| 6 | OpenBao | ESO pod | HTTPS :8200 | Отдать секрет `secrets/data/argocd/admin-password` |
| 7 | ESO pod | K8s API | HTTPS :6443 | Создать/обновить K8s Secret `argocd-admin-password-secret` |

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
Role: argocd-role
  bound_service_account_names:      [argocd-eso-sa]
  bound_service_account_namespaces: [argocd]
  policies:                         [argocd-policy]
  ttl:                              1h
```

### Политика в OpenBao

```hcl
# argocd-policy
path "secrets/data/argocd/*" {
  capabilities = ["read"]
}
```

### Kubernetes RBAC

| Resource | Namespace | Назначение |
|----------|-----------|------------|
| SA `argocd-eso-sa` | argocd | Идентификатор для ESO → OpenBao |
| SA `default` | argocd | TokenReviewer (ClusterRole `system:auth-delegator`) |

### External Secrets Operator

| Параметр | Значение |
|----------|----------|
| Chart | `external-secrets/external-secrets` (Helm) |
| API version | `external-secrets.io/v1` |
| Refresh interval | 5m |

## Конфигурация

### SecretStore (namespace: argocd)

```yaml
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: openbao-backend
  namespace: argocd
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
          role: "argocd-role"
          serviceAccountRef:
            name: "argocd-eso-sa"
```

### ExternalSecret (namespace: argocd)

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: argocd-admin-password
  namespace: argocd
spec:
  refreshInterval: "5m"
  secretStoreRef:
    name: openbao-backend
    kind: SecretStore
  target:
    name: argocd-admin-password-secret
    creationPolicy: Owner
  data:
  - secretKey: password
    remoteRef:
      key: "argocd/admin-password"
      property: password
```

## Безопасность

- **TLS** — все соединения ESO → OpenBao зашифрованы
- **JWT** — одноразовые токены с TTL 1h, генерируются K8s API
- **Least privilege** — политика разрешает только `read` к `secrets/data/argocd/*`
- **Namespace isolation** — роль привязана к namespace `argocd`
- **etcd encryption** — секреты шифруются на диске (secretbox в Kubespray)

## Ротация паролей

1. Обновить пароль в OpenBao:
   ```bash
   bao kv put secrets/argocd/admin-password password='new-password'
   ```
2. ESO подтянет автоматически в течение 5 минут (refreshInterval)
3. K8s Secret `argocd-admin-password-secret` обновится автоматически

## Troubleshooting

```bash
# Статус ExternalSecret
kubectl get externalsecret argocd-admin-password -n argocd

# Статус SecretStore
kubectl get secretstore openbao-backend -n argocd

# Логи ESO
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50

# Проверить содержимое секрета
kubectl get secret argocd-admin-password-secret -n argocd -o jsonpath='{.data.password}' | base64 -d

# Тестовый логин в OpenBao
SA_TOKEN=$(kubectl create token argocd-eso-sa -n argocd --duration=1h)
bao write auth/kubernetes/login role=argocd-role jwt=$SA_TOKEN
```
