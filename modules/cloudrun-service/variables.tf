variable "project_id" {
  description = "ID du projet GCP cible"
  type        = string
}

variable "region" {
  description = "Région Cloud Run / Artifact Registry (Projet 04 — indépendante du VPC europe-west1 du Projet 01)"
  type        = string
  default     = "europe-west9"
}

variable "github_repo" {
  description = "Repo GitHub autorisé à s'authentifier via Workload Identity Federation, format owner/repo"
  type        = string
}

variable "workload_identity_pool_name" {
  description = "Nom complet du pool WIF partagé (output workload_identity_pool_name de la fondation landing-zone)"
  type        = string
}

variable "service_name" {
  description = "Nom du service Cloud Run"
  type        = string
  default     = "backend"
}

variable "artifact_registry_repo_id" {
  description = "ID du dépôt Artifact Registry"
  type        = string
  default     = "backend-repo"
}

variable "deployer_sa_roles" {
  description = "Rôles IAM attribués au SA de déploiement CI/CD (moindre privilège)"
  type        = list(string)
  default = [
    "roles/run.admin",
    "roles/artifactregistry.writer",
    "roles/iam.serviceAccountUser",
  ]
}
