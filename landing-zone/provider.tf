provider "google" {
  project = var.project_id
  region  = var.region

  # Force l'utilisation de devops-498817 comme projet de quota/facturation pour
  # tous les appels API — sans ça, les credentials ADC "utilisateur" retombent
  # sur le projet par défaut du SDK gcloud (764086051850), où des API comme
  # billingbudgets.googleapis.com sont désactivées.
  user_project_override = true
  billing_project       = var.project_id
}
