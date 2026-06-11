variable "project_id" {
  description = "ID du projet GCP cible"
  type        = string
}

variable "terraform_sa_roles" {
  description = "Rôles IAM attribués au compte de service Terraform (pas de primitifs owner/editor/viewer)"
  type        = list(string)
  default = [
    "roles/compute.networkAdmin",
    "roles/compute.instanceAdmin.v1",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/storage.admin",
    "roles/resourcemanager.projectIamAdmin",
  ]
}

variable "iam_bindings" {
  description = "Liaisons IAM additionnelles : map rôle → liste de membres (ex. serviceAccount:sa@project.iam.gserviceaccount.com)"
  type        = map(list(string))
  default     = {}
}
