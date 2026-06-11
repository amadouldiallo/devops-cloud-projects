output "terraform_sa_email" {
  description = "Email du compte de service Terraform (format : terraform-runner@PROJECT_ID.iam.gserviceaccount.com)"
  value       = google_service_account.terraform.email
}

output "terraform_sa_id" {
  description = "ID complet du compte de service Terraform"
  value       = google_service_account.terraform.id
}
