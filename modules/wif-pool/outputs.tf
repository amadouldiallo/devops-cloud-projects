output "pool_name" {
  description = "Nom complet du pool Workload Identity (utilisé par les SA de déploiement des projets)"
  value       = google_iam_workload_identity_pool.github.name
}

output "provider_name" {
  description = "Nom complet du provider WIF — valeur du secret GitHub WIF_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github.name
}
