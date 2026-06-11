variable "project_id" {
  description = "ID du projet GCP cible"
  type        = string
  default     = "devops-498817"
}

variable "region" {
  description = "Région Cloud Run / Artifact Registry"
  type        = string
  default     = "europe-west9"
}

variable "github_repo" {
  description = "Repo GitHub (format owner/repo) autorisé à s'authentifier via Workload Identity Federation pour le déploiement Cloud Run"
  type        = string
}
