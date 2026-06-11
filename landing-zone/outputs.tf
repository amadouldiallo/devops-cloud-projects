output "cloudrun_artifact_registry_repository_url" {
  description = "URL du dépôt Artifact Registry (Projet 04)"
  value       = module.cloudrun.artifact_registry_repository_url
}

output "cloudrun_url" {
  description = "URL publique du service Cloud Run (Projet 04)"
  value       = module.cloudrun.cloud_run_url
}

output "cloudrun_workload_identity_provider" {
  description = "Valeur du secret GitHub WIF_PROVIDER (Projet 04)"
  value       = module.cloudrun.workload_identity_provider
}

output "cloudrun_deployer_service_account_email" {
  description = "Valeur du secret GitHub WIF_SERVICE_ACCOUNT (Projet 04)"
  value       = module.cloudrun.deployer_service_account_email
}
