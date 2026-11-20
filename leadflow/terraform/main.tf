terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

# 1. Namespace
resource "kubernetes_namespace" "leadflow" {
  metadata {
    name = var.namespace
    labels = {
      app = "leadflow"
    }
  }
}

# 2. Database Secret (Zero secrets in Git - values parameterized)
resource "kubernetes_secret" "leadflow_secrets" {
  metadata {
    name      = "leadflow-secrets"
    namespace = kubernetes_namespace.leadflow.metadata[0].name
  }

  data = {
    DATABASE_URL      = "postgres://${var.db_user}:${var.db_password}@leadflow-db:5432/${var.db_name}"
    POSTGRES_PASSWORD = var.db_password
  }

  type = "Opaque"
}

# 3. PostgreSQL Database Deployment & Service
resource "kubernetes_deployment" "postgres" {
  metadata {
    name      = "leadflow-db"
    namespace = kubernetes_namespace.leadflow.metadata[0].name
    labels = {
      app = "leadflow-db"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "leadflow-db"
      }
    }

    template {
      metadata {
        labels = {
          app = "leadflow-db"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:16-alpine"

          port {
            container_port = 5432
          }

          env {
            name  = "POSTGRES_DB"
            value = var.db_name
          }
          env {
            name  = "POSTGRES_USER"
            value = var.db_user
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.leadflow_secrets.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "leadflow-db"
    namespace = kubernetes_namespace.leadflow.metadata[0].name
  }

  spec {
    selector = {
      app = "leadflow-db"
    }

    port {
      port        = 5432
      target_port = 5432
    }
  }
}

# 4. Database Migration Job (Ensures schema is migrated before traffic)
resource "kubernetes_job" "db_migrate" {
  metadata {
    name      = "leadflow-migrate-${var.app_version}"
    namespace = kubernetes_namespace.leadflow.metadata[0].name
  }

  spec {
    template {
      metadata {
        name = "leadflow-migrate"
      }
      spec {
        container {
          name    = "migrate"
          image   = "${var.container_registry}/backend:${var.app_version}"
          command = ["npm", "run", "migrate:prod"]

          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.leadflow_secrets.metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }
        }
        restart_policy = "OnFailure"
      }
    }
  }

  depends_on = [kubernetes_deployment.postgres]
}

# 5. Backend Deployment (2 Replicas, Zero-Downtime Rolling Update)
resource "kubernetes_deployment" "backend" {
  metadata {
    name      = "leadflow-backend"
    namespace = kubernetes_namespace.leadflow.metadata[0].name
    labels = {
      app = "leadflow-backend"
    }
  }

  spec {
    replicas = 2

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "1"
        max_unavailable = "0" # Guarantees zero downtime during rolling update
      }
    }

    selector {
      match_labels = {
        app = "leadflow-backend"
      }
    }

    template {
      metadata {
        labels = {
          app = "leadflow-backend"
        }
      }

      spec {
        container {
          name  = "backend"
          image = "${var.container_registry}/backend:${var.app_version}"

          port {
            container_port = 3001
          }

          env {
            name  = "PORT"
            value = "3001"
          }
          env {
            name  = "APP_VERSION"
            value = var.app_version
          }
          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.leadflow_secrets.metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }

          # Probes addressing the release safety requirement
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 3001
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 3001
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_job.db_migrate]
}

resource "kubernetes_service" "backend" {
  metadata {
    name      = "leadflow-backend"
    namespace = kubernetes_namespace.leadflow.metadata[0].name
  }

  spec {
    selector = {
      app = "leadflow-backend"
    }

    port {
      port        = 3001
      target_port = 3001
    }
  }
}

# 6. Frontend Deployment (2 Replicas, Zero-Downtime)
resource "kubernetes_deployment" "frontend" {
  metadata {
    name      = "leadflow-frontend"
    namespace = kubernetes_namespace.leadflow.metadata[0].name
    labels = {
      app = "leadflow-frontend"
    }
  }

  spec {
    replicas = 2

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "1"
        max_unavailable = "0"
      }
    }

    selector {
      match_labels = {
        app = "leadflow-frontend"
      }
    }

    template {
      metadata {
        labels = {
          app = "leadflow-frontend"
        }
      }

      spec {
        container {
          name  = "frontend"
          image = "${var.container_registry}/frontend:${var.app_version}"

          port {
            container_port = 3000
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 3000
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend" {
  metadata {
    name      = "leadflow-frontend"
    namespace = kubernetes_namespace.leadflow.metadata[0].name
  }

  spec {
    selector = {
      app = "leadflow-frontend"
    }

    port {
      port        = 3000
      target_port = 3000
    }
  }
}

# 7. Ingress (Solves the /api routing to backend and / to frontend)
resource "kubernetes_ingress_v1" "leadflow_ingress" {
  metadata {
    name      = "leadflow-ingress"
    namespace = kubernetes_namespace.leadflow.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                = "nginx"
      "nginx.ingress.kubernetes.io/ssl-redirect"   = "false"
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.backend.metadata[0].name
              port {
                number = 3001
              }
            }
          }
        }

        path {
          path      = "/readyz"
          path_type = "Exact"
          backend {
            service {
              name = kubernetes_service.backend.metadata[0].name
              port {
                number = 3001
              }
            }
          }
        }

        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.frontend.metadata[0].name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }
  }
}
