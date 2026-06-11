variable "project_id" {
  description = "ID du projet GCP cible"
  type        = string
}

variable "github_repo" {
  description = "Repo GitHub autorisé à s'authentifier via Workload Identity Federation, format owner/repo"
  type        = string
}
