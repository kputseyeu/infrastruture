# GitOps Workflow

## Как работает ArgoCD

**Важно понимать:** ArgoCD **не следит за образами** в контейнерных реестрах. Он следит только за **Git**.

```
ArgoCD:  Git (Helm values) → Рендерит чарт → Деплоит в кластер
```

Если в `values-dev.yaml` написано `image.tag: v1.0.0` — ArgoCD будет всегда деплоить `v1.0.0`, пока ты не поменяешь это в Git.

### Кто тогда обновляет образы?

**ArgoCD Image Updater** — это отдельный компонент, который:

1. Мониторит GHCR/Docker Hub на наличие новых тегов
2. Когда находит новый тег (например, `v1.1.0`) — обновляет `values-dev.yaml` в Git (делает commit)
3. ArgoCD видит изменение в Git → синхронизирует приложение

```
Image Updater:  GHCR (новый тег) → Обновляет Git → ArgoCD подхватывает
```

### Итог

| Компонент | За чем следит | Что делает |
|-----------|---------------|------------|
| **ArgoCD** | Git | Деплоит то, что написано в репозитории |
| **Image Updater** | GHCR/Docker Hub | Обновляет Git когда появляется новый образ |

**Без Image Updater** ArgoCD будет вечно деплоить тот образ, который указан в `values.yaml`. Он сам не узнает что появился новый тег.

### Про тег `latest`

Image Updater **не работает с тегом `latest`**. В нашем конфиге:

```yaml
argocd-image-updater.argoproj.io/simple-app.allow-tags: regexp:^v\d+\.\d+\.\d+$
```

Он ищет только семантические теги: `v1.0.0`, `v1.1.0`, `v1.2.0`. Тег `latest` игнорируется.

## App of Apps Pattern

```
┌─────────────────────────────────────────────────────────────┐
│                    ArgoCD (argocd namespace)                 │
│                                                              │
│  ┌──────────────────┐                                       │
│  │  app-of-apps     │  ← Root Application                   │
│  │  (bootstrap)     │     k8s/bootstrap/app-of-apps.yaml    │
│  └────────┬─────────┘                                       │
│           │                                                 │
│           ▼                                                 │
│  ┌────────────────────────────────────────────────┐        │
│  │           Child Applications                   │        │
│  │                                                │        │
│  │  ┌────────────┐  ┌─────────────┐  ┌─────────┐ │        │
│  │  │ argocd     │  │eso-openbao  │  │simple-  │ │        │
│  │  │            │  │             │  │app      │ │        │
│  │  └─────┬──────┘  └──────┬──────┘  └────┬────┘ │        │
│  │        │                │               │      │        │
│  │        ▼                ▼               ▼      │        │
│  │  ┌────────────┐  ┌─────────────┐  ┌─────────┐ │        │
│  │  │ SA,        │  │ SA,         │  │ Helm    │ │        │
│  │  │ SecretStore│  │ SecretStore │  │ Chart   │ │        │
│  │  │ ExtSecret  │  │ ExtSecret   │  │ Deploy  │ │        │
│  │  └────────────┘  └─────────────┘  └─────────┘ │        │
│  └────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
k8s/
├── bootstrap/                  # Apply once manually
│   └── app-of-apps.yaml        # Points to k8s/app-of-apps/
│
├── app-of-apps/                # ArgoCD Applications
│   ├── argocd-app.yaml         # ArgoCD namespace resources
│   ├── eso-openbao-app.yaml    # ESO + OpenBao (default ns)
│   ├── simple-app.yaml         # Helm chart deployment
│   └── image-updater-app.yaml  # Image Updater
│
└── apps/                       # Actual manifests
    ├── argocd/
    │   └── es-secretstore.yaml # SA, SecretStore, ExternalSecret
    ├── eso-openbao/
    │   └── es-secretstore.yaml # SA, SecretStore, ExternalSecret
    └── simple-app/
        └── ingress.yaml        # Ingress rule
```

## Bootstrap Process

### 1. Initial Setup

```bash
# Connect to cluster via bastion
ssh -i ~/.ssh/k8s.key -L 6443:10.10.0.10:6443 jollywonka@<bastion-ip> -N &

# Verify connection
kubectl get nodes
```

### 2. Apply Root Application

```bash
kubectl apply -f k8s/bootstrap/app-of-apps.yaml
```

This creates the `app-of-apps` Application in ArgoCD, which then automatically:
1. Reads `k8s/app-of-apps/` directory
2. Creates all child Applications
3. Each child Application syncs its respective manifests

### 3. Verify

```bash
# Check all Applications
kubectl get applications -n argocd

# Check sync status
argocd app list

# Check individual app
kubectl get application argocd -n argocd -o yaml
```

## Adding a New Application

### Step 1: Create manifests

```bash
mkdir -p k8s/apps/my-new-app
```

Create your manifests in `k8s/apps/my-new-app/`.

### Step 2: Create ArgoCD Application

```yaml
# k8s/app-of-apps/my-new-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-new-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/kirylputseyeu/develop-platform.git
    targetRevision: main
    path: k8s/apps/my-new-app
  destination:
    server: https://kubernetes.default.svc
    namespace: my-new-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Step 3: Commit and push

```bash
git add k8s/apps/my-new-app/ k8s/app-of-apps/my-new-app.yaml
git commit -m "add my-new-app"
git push
```

ArgoCD will automatically detect the new Application and sync it.

## Image Updater Workflow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Developer  │     │    CI/CD    │     │   Docker    │     │   ArgoCD    │
│              │     │  Pipeline   │     │   Hub       │     │   Image     │
│  git push    │────▶│  Build      │────▶│  Push       │────▶│   Updater   │
│              │     │  Test       │     │  v1.2.3     │     │   Monitor   │
└─────────────┘     └─────────────┘     └─────────────┘     └──────┬──────┘
                                                                    │
                                                                    ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Cluster     │     │   ArgoCD    │     │    Git      │     │   ArgoCD    │
│  Running     │◀────│   Sync      │◀────│   Commit    │◀────│   Update    │
│  v1.2.3      │     │  Deploy     │     │  values     │     │  values     │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
```

### How It Works

1. Developer pushes code → CI builds and pushes image `v1.2.3` to Docker Hub
2. Image Updater polls Docker Hub every 2 minutes
3. Finds new tag matching `regexp:^v\d+\.\d+\.\d+$`
4. Updates `values-dev.yaml` in git (commit + push)
5. ArgoCD detects git change → syncs application
6. New deployment rolls out with `v1.2.3`

### Application Annotations

```yaml
metadata:
  annotations:
    # Which image to monitor
    argocd-image-updater.argoproj.io/image-list: simple-app=docker.io/kirylputseyeu/simple-app

    # Which Helm values to update
    argocd-image-updater.argoproj.io/simple-app.helm.image-name: image.repository
    argocd-image-updater.argoproj.io/simple-app.helm.image-tag: image.tag

    # Tag filter (only semver tags)
    argocd-image-updater.argoproj.io/simple-app.allow-tags: regexp:^v\d+\.\d+\.\d+$

    # Update strategy
    argocd-image-updater.argoproj.io/simple-app.update-strategy: semver

    # Write changes back to git
    argocd-image-updater.argoproj.io/write-back-method: git
```

### Update Strategies

| Strategy | Behavior | Example |
|----------|----------|---------|
| `semver` | Latest stable version | `v1.2.3` → `v1.3.0` |
| `latest` | Latest tag (any) | `v1.2.3` → `v2.0.0-beta` |
| `name` | Alphabetical order | `prod` → `stage` |
| `digest` | Latest digest | SHA256 hash |

## Sync Policies

### Automated Sync

```yaml
syncPolicy:
  automated:
    prune: true      # Delete resources removed from git
    selfHeal: true   # Revert manual changes
  syncOptions:
    - CreateNamespace=true
```

### Manual Sync

Remove `automated` block and sync via UI or CLI:

```bash
argocd app sync my-new-app
```

## Troubleshooting

### Application Out of Sync

```bash
# Check diff
argocd app diff my-new-app

# Force sync
argocd app sync my-new-app --force
```

### Image Updater Not Working

```bash
# Check logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater

# Check Application annotations
kubectl get application simple-app -n argocd -o jsonpath='{.metadata.annotations}'

# Force refresh
kubectl annotate application simple-app -n argocd \
  argocd-image-updater.argoproj.io/force-update=true
```

### Sync Failed

```bash
# Check Application events
kubectl describe application my-new-app -n argocd

# Check ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```
