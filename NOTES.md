# LeadFlow DevOps Notes & Architecture Report

Candidate: **Praemjith P R**  
Repository: [leadflow-devops](https://github.com/praemjithpr/leadflow-devops)  
Assignment: Es Magico DevOps Intern Take-Home

---

## 1. System Architecture & Traffic Flow

The system is containerized and deployed to Kubernetes via Terraform, using Nginx for production ingress routing.

```
       [ Client / Browser ]
                │
                ▼
      [ Nginx Ingress / Reverse Proxy ]
        ├── /api/*   ──────►  [ Backend Service (Port 3001) ]
        │                       └── Replicas: 2 (Express + TS)
        │                       └── Health: /healthz, /readyz
        │                                 │
        │                                 ▼
        │                       [ PostgreSQL 16 (Port 5432) ]
        │
        └── /*       ──────►  [ Frontend Service (Port 3000) ]
                                └── Replicas: 2 (Next.js Standalone)
```

### Key Decisions & Assumptions
1. **Container Strategy**: Multi-stage Docker builds.
   - Frontend utilizes Next.js `output: "standalone"`, reducing container image size to ~80MB and discarding `node_modules` clutter.
   - Backend prunes `devDependencies` and runs as an unprivileged user (`appuser`).
2. **Cluster Runtime**:
   - For local development and CI testing, Kind (Kubernetes in Docker) is used via Terraform's `kubernetes` provider.
   - Matches the PDF guidance: *"A local cluster is fine... stay within its free tier or stop at a plan."*
3. **Database Migration Strategy**:
   - Running migrations in the main API entrypoint is an anti-pattern when scaling horizontally (causes migration race conditions across replicas).
   - Solution: Kubernetes `Job` executes `npm run migrate:prod` before backend replicas receive traffic.

---

## 2. Starter Traps Identified & Solved

| Starter Trap | Why It Was A Problem | How We Solved It |
|---|---|---|
| **Next.js Relative Rewrites in Production** | `next.config.ts` explicitly disables `/api` rewrites in production (`if (process.env.NODE_ENV === "production") return []`). In a real environment, browser requests to `/api` would 404. | Configured Nginx reverse proxy / Kubernetes Ingress rules to route `/api/*` directly to the backend service. |
| **Database Migration Timing & Race Conditions** | Running migrations concurrently across multiple backend pods can corrupt schema migrations. | Isolated DB migration into a Kubernetes `Job` (and a pre-run container in Docker Compose) that runs `npm run migrate:prod` once before the backend deployment scales up. |
| **Probes & Rolling Updates** | Killing old pods before new ones connect to PostgreSQL causes downtime / dropped requests. | Configured `readinessProbe` pointing to `/readyz` (checks DB) and `livenessProbe` pointing to `/healthz`. Kubernetes `maxUnavailable: 0` ensures zero dropped requests during rollouts. |
| **Port Conflicts** | Backend defaulted to port 3000, colliding with Next.js frontend port 3000. | Standardized backend to run on port 3001 via environment variable `PORT=3001`. |

---

## 3. Safe Releases & The One-Command Rollback

### Zero-Downtime Releases
- Deployments use `strategy.type = "RollingUpdate"` with `maxSurge: 1` and `maxUnavailable: 0`.
- Kubernetes only routes traffic to newly spawned pods once the `/readyz` endpoint responds with HTTP 200 (database query `SELECT 1` succeeds).

### The One-Command Rollback
To immediately revert a bad deployment back to the previous stable release, execute:
```bash
kubectl rollout undo deployment/leadflow-backend -n leadflow
```
*(and for frontend: `kubectl rollout undo deployment/leadflow-frontend -n leadflow`)*

**What it undoes:**
- Reverts container image tags and pod environment variable definitions to the previous revision.

**What it does NOT undo:**
- Destructive database migrations (e.g., dropped columns or modified constraints). Schema changes must follow expand/contract patterns for backward compatibility.

---

## 4. Security Hygiene & Secrets

- **Zero Secrets in Git**: No `.env` files committed. `.gitignore` strictly protects `.env`, `.env.local`, and build artifacts.
- **Secrets Lifecycle**:
  - In CI: Stored in **GitHub Actions Secrets**.
  - In Kubernetes: Injected into `kubernetes_secret` as environment variables (`DATABASE_URL`, `POSTGRES_PASSWORD`).
- **Principle of Least Privilege**:
  - Backend runs as non-root user `appuser`.
  - Frontend runs as non-root user `nextjs:1001`.

---

## 5. Cost Estimation for a Small Team

Estimated monthly cost to run LeadFlow in production for a small sales team (assuming ~5–15 concurrent users, 99.9% uptime):

### Option A: Lean Cloud Setup (AWS / DigitalOcean)
| Resource | Service / Specs | Monthly Cost |
|---|---|---|
| **Database** | AWS RDS PostgreSQL (`db.t4g.micro`, 20GB gp3 storage) | ~$15 / month |
| **Compute / Containers** | AWS ECS Fargate or DigitalOcean App Platform (2 containers, 0.5 vCPU, 1GB RAM) | ~$25 / month |
| **Networking & Ingress** | AWS Application Load Balancer (ALB) | ~$18 / month |
| **Registry & CI** | GitHub Actions + GitHub Container Registry (Free Tier quota) | $0 / month |
| **Domain & DNS / TLS** | AWS Route 53 + ACM free SSL | ~$1 / month |
| **Total** | | **~$59 / month** |

*Assumptions*: Traffic is low to moderate. Database backups retained for 7 days. Free tier covers container registry and CI build minutes.

---

## 6. What Was Left Out & Next Steps

1. **Centralized Observability**: Integrate Prometheus metrics and OpenTelemetry tracing for APM.
2. **Automated Schema Rollback**: Implement forward-only or reversible migrations with automated verification.
3. **Secrets Manager Integration**: Transition from Kubernetes Secrets to AWS Secrets Manager or HashiCorp Vault with dynamic rotation.
