data "google_project" "current" {
  project_id = var.project_id
}

# Budget mensuel avec alertes email — réflexe FinOps, doit exister avant tout terraform apply
resource "google_billing_budget" "main" {
  billing_account = var.billing_account_id
  display_name    = var.budget_display_name

  budget_filter {
    # budget_filter.projects attend le numéro de projet (pas l'ID textuel)
    projects = ["projects/${data.google_project.current.number}"]
  }

  amount {
    specified_amount {
      currency_code = "EUR"
      units         = tostring(floor(var.budget_amount_eur))
    }
  }

  # Génère une threshold_rules par seuil déclaré dans la variable
  dynamic "threshold_rules" {
    for_each = var.alert_thresholds
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  # Pas de all_updates_rule : GCP envoie par défaut les alertes par email
  # aux admins/utilisateurs de facturation du compte (comportement natif).
}
