# develop-platform

Production-grade Kubernetes infrastructure on GCP with GitOps workflow.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Google Cloud Platform                         │
│                                                                      │
│  ┌──────────────┐    ┌──────────────────────────────────────────┐   │
│  │   VPC        │    │           Compute Instances              │   │
│  │  10.10.0.0/20│    │                                          │   │
│  │              │    │  ┌──────────┐  ┌──────────┐              │   │
│  │  ┌────────┐  │    │  │Bastion   │  │Control   │              │   │
│  │  │Bastion │  │◄───┼──┤10.10.0.2 │  │Plane     │              │   │
│  │  │35.x.x.x│  │    │  │          │  │10.10.0.10│              │   │
│  │  └────────┘  │    │  └──────────┘  └──────────┘              │   │
│  │              │    │        │              │                    │   │
│  │  ┌────────┐  │    │  ┌─────┴─────┐  ┌────┴────┐              │   │
│  │  │Bastion │  │    │  │Worker 1   │  │Worker 2 │              │   │
│  │  │35.x.x.x│  │    │  │10.10.0.20 │  │10.10.0.21│              │   │
│  │  └────────┘  │    │  └───────────┘  └─────────┘              │   │
│  │              │    │                                          │   │
│  │  ┌────────┐  │    │  ┌──────────┐                            │   │
│  │  │OpenBao │  │    │  │OpenBao   │  Secrets management        │   │
│  │  │        │  │◄───┼──┤10.10.0.30│                            │   │
│  │  └────────┘  │    │  └──────────┘                            │   │
│  └──────────────┘    └──────────────────────────────────────────┘   │
│                                                                      │
│  KMS ─── Disk encryption                                             │
│  Cloud NAT ─── Outbound internet for private nodes                   │
└──────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.9.0
- [gcloud CLI](https://cloud.google.com/sdk/docs/install)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) >= 3.15.0
- SSH key pair (`~/.ssh/k8s.key`)

### 1. Provision Infrastructure

```bash
cd tf
terraform init
terraform plan
terraform apply
```

This creates:
- VPC with private subnet
- Bastion nodes (public IP)
- Control-plane + Workers (private)
- OpenBao node (private)
- KMS encryption keys
- Service accounts with least-privilege IAM

### 2. Deploy Kubernetes Cluster

```bash
# Update inventory with actual IPs
vim kubespray/inventory/mycluster/inventory.ini

# Deploy via Kubespray
docker run --rm -it \
  --mount type=bind,source="$(pwd)"/inventory/mycluster,dst=/inventory \
  quay.io/kubespray/kubespray:v2.30.0 bash

# Inside container:
ansible-playbook -i /inventory/inventory.ini cluster.yml
```

### 3. Bootstrap GitOps

```bash
# Connect via bastion
ssh -i ~/.ssh/k8s.key -L 6443:10.10.0.10:6443 jollywonka@<bastion-ip> -N &

# Bootstrap ArgoCD App of Apps
kubectl apply -f k8s/bootstrap/app-of-apps.yaml
```

### 4. Unseal OpenBao

```bash
ssh openbao-01
bao operator unseal <key1>
bao operator unseal <key2>
bao operator unseal <key3>
```

## Project Structure

```
develop-platform/
├── tf/                          # Terraform (GCP infrastructure)
│   ├── providers.tf             # GCP provider, versions
│   ├── variables.tf             # All configurable inputs
│   ├── network.tf               # VPC, subnet, firewall
│   ├── instances.tf             # Compute instances
│   ├── kms.tf                   # Disk encryption keys
│   ├── service_accounts.tf      # IAM service accounts
│   └── outputs.tf               # Output values
│
├── kubespray/                   # Kubernetes cluster deployment
│   └── inventory/mycluster/     # Custom inventory
│       └── inventory.ini        # Node definitions
│
├── k8s/                         # Kubernetes manifests (ArgoCD managed)
│   ├── bootstrap/               # One-time bootstrap
│   │   └── app-of-apps.yaml     # Root ArgoCD Application
│   ├── app-of-apps/             # ArgoCD Applications
│   │   ├── argocd-app.yaml      # ArgoCD + ESO secrets
│   │   ├── eso-openbao-app.yaml # ESO + OpenBao integration
│   │   ├── simple-app.yaml      # Helm chart deployment
│   │   └── image-updater-app.yaml # Image Updater
│   └── apps/                    # Application manifests
│       ├── argocd/              # ArgoCD namespace resources
│       ├── eso-openbao/         # ESO SecretStore + ExternalSecrets
│       └── simple-app/          # Simple app resources
│
├── helm/                        # Helm charts
│   └── simple-app/              # Application chart
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values-dev.yaml
│       ├── values-prod.yaml
│       └── templates/
│
├── bao/                         # OpenBao keys (KEEP SAFE!)
│   └── cluster_keys.txt
│
├── docs/                        # Documentation
│   └── eso-openbao-chain.md     # ESO + OpenBao architecture
│
├── .github/workflows/           # CI pipelines
│   └── ci.yml                   # Terraform, Helm, Security checks
│
├── CLAUDE.md                    # AI assistant context
└── README.md                    # This file
```

## Components

### Infrastructure (Terraform)

| Resource | Description |
|----------|-------------|
| VPC | `10.10.0.0/20` with flow logs |
| Subnet | Private, regional |
| Bastion (x2) | Public IP, SSH entry point |
| Control-plane | Kubernetes API server |
| Workers (x2) | Application workloads |
| OpenBao | Secrets management (HashiCorp Vault fork) |
| KMS | Disk encryption, 90-day rotation |
| Cloud NAT | Outbound internet for private nodes |

### Kubernetes

| Component | Version | Notes |
|-----------|---------|-------|
| Kubernetes | v1.35.4 | Secrets encrypted at rest (secretbox) |
| CNI | Calico | Network policies, BGP |
| CRI | CRI-O | Lightweight container runtime |
| Ingress | NGINX | Load balancing, TLS termination |
| Storage | Local Path | Persistent volumes |

### GitOps (ArgoCD)

| Component | Purpose |
|-----------|---------|
| ArgoCD | Declarative GitOps engine |
| App of Apps | Hierarchical application management |
| External Secrets Operator | Sync secrets from OpenBao |
| Image Updater | Auto-update container images |

## Node Layout

| Role | IP | External | Tags |
|------|-----|----------|------|
| Bastion 1 | 10.10.0.2 | Yes | bastion, ssh, internal |
| Bastion 2 | 10.10.0.3 | Yes | bastion, ssh, internal |
| Control-plane | 10.10.0.10 | No | control-plane, ssh, internal |
| Worker 1 | 10.10.0.20 | No | worker, ssh, internal |
| Worker 2 | 10.10.0.21 | No | worker, ssh, internal |
| OpenBao | 10.10.0.30 | No | openbao, ssh, internal |

## Security

### Infrastructure Level
- Shielded VMs (secure boot, vTPM, integrity monitoring)
- KMS disk encryption with 90-day key rotation
- OS Login enforced
- Firewall rules use network tags (not IP-based)
- Private nodes with Cloud NAT

### Kubernetes Level
- Secrets encrypted at rest (secretbox)
- RBAC with least-privilege
- Network policies (Calico)

### Secrets Management
- OpenBao for centralized secret storage
- ESO for automatic sync to Kubernetes
- JWT-based Kubernetes authentication
- TLS for all OpenBao communication
- Namespace-isolated SecretStores

## CI/CD Pipeline

### Infrastructure CI (`.github/workflows/ci.yml`)

| Job | Checks |
|-----|--------|
| Terraform | `fmt`, `init`, `validate`, `plan` + PR comment |
| Helm | `lint`, `template` (default/dev/prod) |
| K8s Manifests | `kubeconform` strict validation |
| Security | Checkov (Terraform), Trivy (Helm configs) |

### Application CI (in your app repo)

```
Build → Test → Push image → ArgoCD Image Updater detects → Updates git → ArgoCD syncs
```

## Operations

### SSH to Nodes

```bash
# Via bastion to any internal node
ssh -A -J jollywonka@<bastion-ip> jollywonka@10.10.0.<node-ip>

# SSH config shortcut
ssh openbao-01
ssh control-plane-01
ssh worker-01
```

### OpenBao Operations

```bash
# Check status
ssh openbao-01 "BAO_ADDR=https://10.10.0.30:8200 BAO_SKIP_VERIFY=1 BAO_TOKEN='<root-token>' sudo -E bao status"

# Unseal (need 3 of 5 keys)
ssh openbao-01 "BAO_ADDR=https://10.10.0.30:8200 BAO_SKIP_VERIFY=1 BAO_TOKEN='<root-token>' sudo -E bao operator unseal <key>"

# Read a secret
ssh openbao-01 "BAO_ADDR=https://10.10.0.30:8200 BAO_SKIP_VERIFY=1 BAO_TOKEN='<root-token>' sudo -E bao kv get secrets/login-app/db"

# Write a secret
ssh openbao-01 "BAO_ADDR=https://10.10.0.30:8200 BAO_SKIP_VERIFY=1 BAO_TOKEN='<root-token>' sudo -E bao kv put secrets/myapp/config key=value"
```

### ArgoCD Access

```bash
# Port-forward UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# CLI login
argocd login localhost:8080 --username admin --password <password> --insecure
```

### Image Updater

```bash
# Check logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater

# Force refresh
kubectl annotate application simple-app -n argocd \
  argocd-image-updater.argoproj.io/force-update=true
```

### Scaling

```bash
# Add a worker: edit tf/variables.tf
worker_nodes = ["worker-01", "worker-02", "worker-03"]

# Apply
cd tf && terraform apply

# Update Kubespray inventory and re-run
ansible-playbook -i inventory/mycluster/inventory.ini scale.yml
```

## Troubleshooting

### Common Issues

| Problem | Solution |
|---------|----------|
| OpenBao sealed | Unseal with 3 of 5 keys |
| ESO can't connect | Check TLS cert, CA bundle, Kubernetes auth |
| ArgoCD sync failed | Check Application status: `kubectl get app -n argocd` |
| Image Updater not working | Check annotations, registry credentials, git write-back |
| Terraform state locked | `terraform force-unlock <lock-id>` |

### Debug Commands

```bash
# External Secrets
kubectl get externalsecret <name> -n <namespace> -o yaml
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# ArgoCD
kubectl get application -n argocd
kubectl describe application <name> -n argocd

# OpenBao connectivity
curl -sk https://10.10.0.30:8200/v1/sys/health

# Kubernetes API from OpenBao
ssh openbao-01 "curl -sk https://10.10.0.10:6443/version"
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TF_VAR_project` | — | GCP project ID |
| `TF_VAR_region` | `europe-west3` | GCP region |
| `TF_VAR_zone` | `europe-west3-b` | GCP zone |
| `TF_VAR_machine_type` | `e2-medium` | VM instance type |
| `TF_VAR_disk_size_gb` | `30` | Boot disk size |
| `TF_VAR_environment` | `dev` | Environment label |

## License

MIT
