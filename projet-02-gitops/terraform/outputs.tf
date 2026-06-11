output "cluster_name" {
  description = "Nom du cluster GKE — pour gcloud container clusters get-credentials"
  value       = module.gke_cluster.cluster_name
}

output "cluster_zone" {
  description = "Zone du cluster GKE — pour gcloud container clusters get-credentials"
  value       = module.gke_cluster.cluster_location
}

output "vpc_name" {
  description = "Nom du VPC dédié à ce projet"
  value       = module.network.vpc_name
}
