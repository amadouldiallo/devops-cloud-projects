output "cluster_name" {
  description = "Nom du cluster GKE créé (pour gcloud container clusters get-credentials)"
  value       = google_container_cluster.primary.name
}

output "cluster_location" {
  description = "Zone du cluster GKE (pour gcloud container clusters get-credentials)"
  value       = google_container_cluster.primary.location
}

output "cluster_endpoint" {
  description = "Endpoint de l'API server du cluster"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "node_service_account_email" {
  description = "Email du compte de service utilisé par les nœuds GKE"
  value       = google_service_account.gke_nodes.email
}
