variable "project_id" {
  description = "ID du projet GCP cible"
  type        = string
  default     = "devops-498817"
}

variable "region" {
  description = "Région GCP par défaut"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "Zone GCP par défaut (pour les ressources zonales comme la VM de lab)"
  type        = string
  default     = "europe-west1-b"
}

variable "billing_account_id" {
  description = "ID du compte de facturation GCP (format XXXXXX-XXXXXX-XXXXXX, obtenu via : gcloud billing accounts list)"
  type        = string
}

variable "admin_email" {
  description = "Adresse email du compte Google humain autorisé à se connecter en SSH à la VM de lab (IAP + OS Login)"
  type        = string
}
