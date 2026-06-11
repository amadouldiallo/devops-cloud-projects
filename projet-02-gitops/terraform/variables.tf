variable "project_id" {
  description = "ID du projet GCP cible"
  type        = string
  default     = "devops-498817"
}

variable "region" {
  description = "Région GCP (VPC, sous-réseau)"
  type        = string
  default     = "europe-west9"
}

variable "zone" {
  description = "Zone GCP du cluster GKE (cluster zonal — free tier)"
  type        = string
  default     = "europe-west9-a"
}

variable "cluster_name" {
  description = "Nom du cluster GKE"
  type        = string
  default     = "gitops-lab"
}
