output "instance_name" {
  description = "Nom de la VM de lab"
  value       = google_compute_instance.lab_vm.name
}

output "instance_zone" {
  description = "Zone de la VM de lab"
  value       = google_compute_instance.lab_vm.zone
}

output "instance_internal_ip" {
  description = "IP interne de la VM (pas d'IP publique)"
  value       = google_compute_instance.lab_vm.network_interface[0].network_ip
}

output "service_account_email" {
  description = "Email du SA dédié à la VM de lab"
  value       = google_service_account.lab_vm.email
}
