locals {
  # Aplatit map(list(string)) en liste de paires {role, member} pour le for_each
  iam_bindings_flat = flatten([
    for role, members in var.iam_bindings : [
      for member in members : { role = role, member = member }
    ]
  ])
}

# Compte de service dédié à l'automatisation Terraform — jamais le compte utilisateur personnel
resource "google_service_account" "terraform" {
  project      = var.project_id
  account_id   = "terraform-runner"
  display_name = "Terraform Runner"
  description  = "Compte de service utilisé par le pipeline CI/CD pour les opérations Terraform"
}

# Attribution des rôles au SA Terraform — un resource par rôle pour une gestion granulaire
resource "google_project_iam_member" "terraform_sa_roles" {
  for_each = toset(var.terraform_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

# Liaisons IAM additionnelles configurables via variable (ex. autres SAs, groupes)
resource "google_project_iam_member" "custom_bindings" {
  for_each = { for b in local.iam_bindings_flat : "${b.role}/${b.member}" => b }

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}
