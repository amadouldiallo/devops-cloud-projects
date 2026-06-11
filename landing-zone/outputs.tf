output "workload_identity_pool_name" {
  description = "Nom complet du pool WIF partagé — consommé par le state de chaque projet"
  value       = module.wif.pool_name
}

output "workload_identity_provider_name" {
  description = "Nom complet du provider WIF partagé — valeur du secret GitHub WIF_PROVIDER pour chaque projet"
  value       = module.wif.provider_name
}
