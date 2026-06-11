variable "project_id" {
  description = "ID du projet GCP cible"
  type        = string
}

variable "zone" {
  description = "Zone GCP de la VM de lab"
  type        = string
  default     = "europe-west1-b"
}

variable "instance_name" {
  description = "Nom de la VM de lab"
  type        = string
  default     = "lab-vm"
}

variable "machine_type" {
  description = "Type de machine (e2-standard-4 = 4 vCPU / 16 Go RAM)"
  type        = string
  default     = "e2-standard-4"
}

variable "boot_image" {
  description = "Image de boot (famille Ubuntu LTS)"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2204-lts"
}

variable "boot_disk_size_gb" {
  description = "Taille du disque de boot en Go"
  type        = number
  default     = 50
}

variable "subnet_self_link" {
  description = "Self-link du sous-réseau auquel attacher la VM (sortie de module.network)"
  type        = string
}

variable "vpc_id" {
  description = "ID du VPC sur lequel créer la règle de firewall IAP (sortie de module.network)"
  type        = string
}

variable "lab_vm_sa_roles" {
  description = "Rôles IAM attribués au SA de la VM de lab (moindre privilège)"
  type        = list(string)
  default = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]
}
