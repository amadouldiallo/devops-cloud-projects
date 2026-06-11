variable "project_id" {
  description = "ID du projet GCP cible"
  type        = string
}

variable "region" {
  description = "Région GCP pour le sous-réseau, le routeur et le NAT"
  type        = string
}

variable "vpc_name" {
  description = "Nom du VPC"
  type        = string
  default     = "main-vpc"
}

variable "subnet_cidr" {
  description = "Plage CIDR du sous-réseau principal"
  type        = string
  default     = "10.10.0.0/20"
}

variable "secondary_ip_ranges" {
  description = "Ranges IP secondaires du sous-réseau (ex. pods/services pour un cluster GKE VPC-native) — optionnel"
  type = list(object({
    range_name    = string
    ip_cidr_range = string
  }))
  default = []
}
