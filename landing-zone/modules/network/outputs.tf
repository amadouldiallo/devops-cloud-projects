output "vpc_id" {
  description = "ID du VPC créé"
  value       = google_compute_network.main.id
}

output "vpc_name" {
  description = "Nom du VPC créé"
  value       = google_compute_network.main.name
}

output "subnet_id" {
  description = "ID du sous-réseau créé"
  value       = google_compute_subnetwork.main.id
}

output "subnet_self_link" {
  description = "Self-link du sous-réseau (utile pour rattacher des ressources)"
  value       = google_compute_subnetwork.main.self_link
}
