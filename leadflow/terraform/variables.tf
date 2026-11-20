variable "kubeconfig_path" {
  description = "Path to the kubeconfig file (e.g., ~/.kube/config)"
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "Kubernetes namespace for LeadFlow"
  type        = string
  default     = "leadflow"
}

variable "container_registry" {
  description = "Container registry prefix"
  type        = string
  default     = "ghcr.io/praemjithpr/leadflow"
}

variable "app_version" {
  description = "Version tag for Docker images"
  type        = string
  default     = "latest"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "leadflow"
}

variable "db_user" {
  description = "PostgreSQL username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "PostgreSQL password (injected via CI or environment)"
  type        = string
  sensitive   = true
  default     = "postgres"
}
