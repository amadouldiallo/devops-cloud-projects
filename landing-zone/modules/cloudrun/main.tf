# APIs nécessaires au Projet 04 (Cloud Run + CI/CD sans clé statique)
resource "google_project_service" "cloudrun_apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "iamcredentials.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Registre d'images Docker pour le backend (Projet 04)
resource "google_artifact_registry_repository" "backend" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_registry_repo_id
  format        = "DOCKER"
  description   = "Images du backend FastAPI (Projet 04 - Cloud Run)"

  depends_on = [google_project_service.cloudrun_apis]
}

# Service Cloud Run — image placeholder au premier apply, remplacée par le
# pipeline CI/CD (étape 6 du guide projet-04-cloudrun-ia.md). Terraform ne
# suit pas l'image après coup : c'est le pipeline qui la fait évoluer.
resource "google_cloud_run_v2_service" "backend" {
  project  = var.project_id
  name     = var.service_name
  location = var.region

  template {
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
  }

  lifecycle {
    ignore_changes = [template[0].containers]
  }

  depends_on = [google_project_service.cloudrun_apis]
}

# Accès public (--allow-unauthenticated)
resource "google_cloud_run_v2_service_iam_member" "public" {
  project  = google_cloud_run_v2_service.backend.project
  location = google_cloud_run_v2_service.backend.location
  name     = google_cloud_run_v2_service.backend.name

  role   = "roles/run.invoker"
  member = "allUsers"
}

# --- Workload Identity Federation : GitHub Actions sans clé JSON ------------

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.cloudrun_apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }
  # Restreint l'échange de jeton à CE repo précis — sans ça, n'importe quel
  # repo GitHub pourrait usurper l'identité du SA cloudrun-deployer.
  attribute_condition = "assertion.repository == '${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# SA dédié au déploiement depuis GitHub Actions — pas terraform-runner, pas lab-vm
resource "google_service_account" "cloudrun_deployer" {
  project      = var.project_id
  account_id   = "cloudrun-deployer"
  display_name = "Cloud Run Deployer (GitHub Actions)"
  description  = "Build + push image, deploy Cloud Run — via Workload Identity Federation"
}

resource "google_project_iam_member" "deployer_roles" {
  for_each = toset(var.deployer_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudrun_deployer.email}"
}

# Autorise CE repo GitHub précis à "devenir" le SA cloudrun-deployer
resource "google_service_account_iam_member" "github_wif_binding" {
  service_account_id = google_service_account.cloudrun_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}
