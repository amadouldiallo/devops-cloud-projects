variable "project_id" {
  description = "ID du projet GCP cible"
  type        = string
}

variable "billing_account_id" {
  description = "ID du compte de facturation GCP (format XXXXXX-XXXXXX-XXXXXX, obtenu via : gcloud billing accounts list)"
  type        = string
}

variable "budget_display_name" {
  description = "Nom affiché pour ce budget dans la console Billing"
  type        = string
  default     = "budget-landing-zone"
}

variable "budget_amount_eur" {
  description = "Montant du budget mensuel en euros (partie entière)"
  type        = number
  default     = 20
}

variable "alert_thresholds" {
  description = "Seuils d'alerte en fraction du budget (0.5 = 50 %, 1.0 = 100 %)"
  type        = list(number)
  default     = [0.5, 0.9, 1.0]
}
