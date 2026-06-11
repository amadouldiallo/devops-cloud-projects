# APIs nécessaires au service (Cloud Run + CI/CD sans clé statique)
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

# Registre d'images Docker pour le backend
resource "google_artifact_registry_repository" "backend" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_registry_repo_id
  format        = "DOCKER"
  description   = "Images du backend FastAPI (Projet 04 - Cloud Run)"

  depends_on = [google_project_service.cloudrun_apis]
}

# Service Cloud Run — image placeholder au premier apply, remplacée par le
# pipeline CI/CD. Terraform ne suit pas l'image après coup : c'est le
# pipeline qui la fait évoluer.
resource "google_cloud_run_v2_service" "backend" {
  project  = var.project_id
  name     = var.service_name
  location = var.region

  deletion_protection = false

  template {
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
  }

  lifecycle {
    # Le pipeline CI/CD (gcloud run deploy) gère l'image et les annotations
    # client — Terraform ne doit pas les "reprendre".
    ignore_changes = [
      client,
      client_version,
      template[0].containers,
    ]
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

# Autorise CE repo GitHub précis (via le pool WIF partagé) à "devenir" le SA cloudrun-deployer
resource "google_service_account_iam_member" "github_wif_binding" {
  service_account_id = google_service_account.cloudrun_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${var.workload_identity_pool_name}/attribute.repository/${var.github_repo}"
}
