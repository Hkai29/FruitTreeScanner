# FruitTreeScanner Deployment

This directory contains all deployment and infrastructure configurations for the FruitTreeScanner application.

## Structure

```
deploy/
├── docker-compose.yml           # Local development environment
├── docker-compose.monitoring.yml # Monitoring stack (Prometheus, Grafana, Loki)
├── kubernetes/                   # Kubernetes manifests
│   ├── backend-deployment.yaml
│   ├── worker-deployment.yaml
│   └── secrets.yaml
├── helm/                         # Helm charts
│   ├── Chart.yaml
│   └── values.yaml
├── terraform/                    # Infrastructure as Code (AWS)
│   ├── main.tf
│   ├── variables.tf
│   └── terraform.tfvars.example
├── monitoring/                   # Monitoring configs
│   ├── prometheus.yml
│   ├── promtail.yml
│   └── grafana/
├── postgres/                     # PostgreSQL initialization
│   └── init.sql
└── security/                     # Security configurations
    └── security-headers.conf
```

## Quick Start

### Local Development

```bash
cd deploy
docker compose up -d
```

### With Monitoring

```bash
cd deploy
docker compose --profile monitoring up -d
```

Services:
- Backend API: http://localhost:8000
- MinIO Console: http://localhost:9001
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000 (admin/admin)
- Loki: http://localhost:3100

## Production Deployment

### Prerequisites

1. Install tools:
   - Docker
   - kubectl
   - helm
   - terraform
   - AWS CLI (for AWS deployments)

2. Configure secrets in `kubernetes/secrets.yaml` or use External Secrets Operator

### Kubernetes Deployment

```bash
# Apply Kubernetes manifests
kubectl apply -f kubernetes/

# Or use Helm
helm install fruittreescanner ./helm
```

### Terraform (AWS)

```bash
cd terraform
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

## CI/CD

The GitHub Actions workflows are defined in `.github/workflows/`:

- `backend-ci.yml` - Backend FastAPI pipeline (lint, test, build, deploy)
- `build-ipa.yml` - iOS IPA build pipeline

## Security

- All secrets should be stored in Kubernetes Secrets or AWS Secrets Manager
- Use TLS for all connections in production
- Review `security/security-headers.conf` for recommended security headers
- Run security scans with: `docker run -v $(pwd):/src aquasec/trivy /src`
