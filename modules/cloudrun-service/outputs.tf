output "artifact_registry_repository_url" {
  description = "URL du dépôt Artifact Registry (pour docker build/push)"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.backend.repository_id}"
}

output "cloud_run_url" {
  description = "URL publique du service Cloud Run"
  value       = google_cloud_run_v2_service.backend.uri
}

output "deployer_service_account_email" {
  description = "Email du SA de déploiement — à coller dans le secret GitHub WIF_SERVICE_ACCOUNT"
  value       = google_service_account.cloudrun_deployer.email
}
