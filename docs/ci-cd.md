# CI/CD Pipelines

## Overview

Single unified pipeline that runs all checks in parallel on every push/PR.

```
┌─────────────────────────────────────────────────────────────┐
│                      CI Pipeline                             │
│                                                              │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────┐│
│  │ Terraform  │  │    Helm    │  │ K8s        │  │Security││
│  │            │  │            │  │ Manifests  │  │        ││
│  │ fmt        │  │ lint       │  │ kubeconform│  │checkov ││
│  │ init       │  │ template   │  │ strict     │  │trivy   ││
│  │ validate   │  │ (dev/prod) │  │            │  │        ││
│  │ plan*      │  │            │  │            │  │        ││
│  └────────────┘  └────────────┘  └────────────┘  └────────┘│
│                                                              │
│  *plan only runs on pull requests, posts results as comment  │
└─────────────────────────────────────────────────────────────┘
```

## Pipeline Structure (`.github/workflows/ci.yml`)

### Jobs

| Job | Trigger | Duration | Fail on |
|-----|---------|----------|---------|
| `terraform` | Changes in `tf/` | ~30s | fmt, validate, plan errors |
| `helm` | Changes in `helm/` | ~15s | lint, template errors |
| `k8s-manifests` | Changes in `k8s/` | ~10s | invalid YAML |
| `security` | Any push/PR | ~30s | HIGH/CRITICAL findings |

### Terraform Job

```yaml
Steps:
1. terraform fmt -check      # Format validation
2. terraform init            # Initialize providers
3. terraform validate        # Config validation
4. terraform plan            # Preview changes (PR only)
5. Post plan as PR comment   # Review changes before merge
```

**PR Comment Example:**
```
#### Terraform Format: ✅ success
#### Terraform Init: ✅ success
#### Terraform Validate: ✅ success
#### Terraform Plan: ✅ success

<details><summary>Show Plan</summary>
...
</details>
```

### Helm Job

```yaml
Steps:
1. helm lint helm/simple-app                    # Chart validation
2. helm template test helm/simple-app           # Default values render
3. helm template test helm/simple-app -f ...    # Dev values render
4. helm template test helm/simple-app -f ...    # Prod values render
```

### K8s Manifests Job

```yaml
Steps:
1. kubeconform -strict -summary k8s/**/*.yaml   # Schema validation
```

Validates all Kubernetes manifests against the API schema. Catches:
- Typos in field names
- Missing required fields
- Invalid enum values
- Deprecated API versions

### Security Job

```yaml
Steps:
1. checkov -d tf/              # Terraform security scan
2. trivy config helm/          # Helm config scan
```

**Checkov checks:**
- Public S3 buckets
- Unencrypted disks
- Overly permissive IAM
- Missing logging
- SSH open to 0.0.0.0/0

**Trivy checks:**
- Misconfigured Helm values
- Hardcoded secrets
- Privileged containers
- Missing resource limits

## Adding New Checks

### Terraform-specific check

Add to the `terraform` job:

```yaml
- name: Terraform Security
  uses: aquasecurity/tfsec-action@v1.0.0
  with:
    working_directory: tf/
```

### Helm tests

Add to `helm` job:

```yaml
- name: Helm Test
  run: helm test test-release
```

### Custom kubeconform schemas

```yaml
- name: Validate with custom schema
  run: |
    kubeconform -strict \
      -schema-location default \
      -schema-location 'k8s/schemas/{{.ResourceKind}}.json' \
      k8s/
```

## Branch Protection

Recommended GitHub branch protection rules:

```
main branch:
  ✅ Require pull request reviews
  ✅ Require status checks to pass
     ✅ Terraform
     ✅ Helm
     ✅ K8s Manifests
     ✅ Security
  ✅ Require linear history
  ✅ Do not allow bypassing
```

## Local Testing

Run checks locally before pushing:

```bash
# Terraform
cd tf && terraform fmt -check && terraform init && terraform validate

# Helm
helm lint helm/simple-app
helm template test helm/simple-app

# K8s manifests
kubeconform -strict -summary k8s/

# Security
checkov -d tf/
trivy config helm/
```
