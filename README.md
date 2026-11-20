# LeadFlow — DevOps Production Setup

LeadFlow is a lead-tracking system composed of a Next.js 16 Web UI, an Express + TypeScript API, and a PostgreSQL 16 database. 

This repository packages LeadFlow into production-grade containerized infrastructure with Terraform IaC, zero-downtime CI/CD deployment pipelines, and one-command rollback capabilities.

---

## 🚀 Quick Start (Local Run with Docker Compose)

The fastest way to spin up the entire LeadFlow stack (Postgres + auto-migrations + Backend API + Frontend UI + Nginx Reverse Proxy) on any machine:

### Prerequisites
* [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running.

### 1. Launch the Stack
```bash
cd leadflow
docker compose up --build
```

### 2. Access the Application
* **Web UI**: Open [http://localhost:3000](http://localhost:3000)
* **Backend API / Health Probe**: [http://localhost:3000/readyz](http://localhost:3000/readyz)
* **API Documentation Endpoint**: [http://localhost:3000/api/leads](http://localhost:3000/api/leads)

*Note: Database migrations run automatically via the `migrate` service container before the backend receives any connections.*

---

## 🏛️ Architecture & Production Design

```
             Internet / User Requests
                        │
                        ▼
            [ Ingress / Nginx Proxy ]
               ├── /api/*   ───► [ Backend API ] :3001
               │                   ├── Liveness:  /healthz
               │                   ├── Readiness: /readyz
               │                   └── Replicas: 2
               │                         │
               │                         ▼
               │                   [ PostgreSQL 16 ] :5432
               │
               └── /*       ───► [ Frontend UI ] :3000
                                   └── Next.js 16 (Standalone)
                                   └── Replicas: 2
```

### Key Highlights
* **Ingress Reverse Proxy**: Next.js disables relative rewrites in production (`next.config.ts`). Nginx routes `/api/*` and operational endpoints directly to the backend.
* **Security & Least Privilege**: All Docker containers use multi-stage builds and run under non-privileged users (`appuser` for backend, `nextjs:1001` for frontend).
* **Zero Secrets in Git**: Sensitive parameters like database credentials are decoupled into environment variables and Kubernetes secrets.

---

## ☸️ Infrastructure as Code (Terraform + Kubernetes)

Deploy to a local Kubernetes cluster (such as `kind`, `k3d`, or `minikube`):

### 1. Create Cluster
```bash
kind create cluster --name leadflow
```

### 2. Apply Terraform
```bash
cd leadflow/terraform
terraform init
terraform apply -auto-approve
```

This provisions:
- `leadflow` Kubernetes Namespace.
- Secret store (`leadflow-secrets`).
- PostgreSQL Stateful Deployment + ClusterIP Service.
- Schema Migration Kubernetes `Job` (executes `npm run migrate:prod`).
- Backend Deployment with 2 replicas & HTTP readiness/liveness probes.
- Frontend Deployment with 2 replicas (Next.js standalone).
- Ingress routing rules.

---

## 🔄 Safe Releases & One-Command Rollback

### Zero-Downtime Rollout Strategy
Deployments enforce `RollingUpdate` with `maxSurge: 1` and `maxUnavailable: 0`. Traffic is routed exclusively to pods that pass the `/readyz` health check (verifying DB connectivity).

### One-Command Rollback
If a faulty build is ever released, revert immediately to the previous revision:
```bash
kubectl rollout undo deployment/leadflow-backend -n leadflow
kubectl rollout undo deployment/leadflow-frontend -n leadflow
```

---

## 🧪 CI/CD Pipeline (GitHub Actions)

Located at [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml):
1. **Test Gate**: Executes `npm run lint`, database migrations, and integration tests (`npm test`) on an isolated Postgres service container.
2. **Build Stage**: Builds multi-stage Docker images via Buildx and pushes to GitHub Container Registry (`ghcr.io`).
3. **Deployment**: Deploys via Terraform to a test cluster and performs automated curl smoke tests on `/readyz`.
4. **Rollback Trigger**: Supports manual or automated one-click rollback dispatch.

---

## 📑 Detailed Report & Decisions

For comprehensive technical reasoning, starter traps noticed, and cloud cost estimations, please read **[`NOTES.md`](NOTES.md)**.
