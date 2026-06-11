output "budget_id" {
  description = "ID du budget GCP créé"
  value       = google_billing_budget.main.id
}

output "budget_name" {
  description = "Nom affiché du budget"
  value       = google_billing_budget.main.display_name
}
