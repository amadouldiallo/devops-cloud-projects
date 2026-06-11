output "artifact_registry_repository_url" {
  description = "URL du dépôt Artifact Registry (pour docker build/push)"
  value       = module.cloudrun_service.artifact_registry_repository_url
}

output "cloud_run_url" {
  description = "URL publique du service Cloud Run"
  value       = module.cloudrun_service.cloud_run_url
}

output "deployer_service_account_email" {
  description = "Valeur du secret GitHub WIF_SERVICE_ACCOUNT"
  value       = module.cloudrun_service.deployer_service_account_email
}

output "workload_identity_provider" {
  description = "Valeur du secret GitHub WIF_PROVIDER"
  value       = data.terraform_remote_state.foundation.outputs.workload_identity_provider_name
}
