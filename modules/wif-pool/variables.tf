variable "project_id" {
  description = "ID du projet GCP cible"
  type        = string
}

variable "github_repo" {
  description = "Repo GitHub autorisé à s'authentifier via Workload Identity Federation, format owner/repo"
  type        = string
}

variable "pool_id" {
  description = "ID du pool Workload Identity — unique par projet (un pool par état Terraform, pour une isolation totale)"
  type        = string
}
