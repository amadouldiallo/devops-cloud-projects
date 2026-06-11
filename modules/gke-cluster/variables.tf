variable "project_id" {
  description = "ID du projet GCP cible"
  type        = string
}

variable "zone" {
  description = "Zone GCP du cluster (cluster zonal — control plane couvert par le free tier)"
  type        = string
}

variable "cluster_name" {
  description = "Nom du cluster GKE"
  type        = string
  default     = "gitops-lab"
}

variable "network_self_link" {
  description = "Self-link du VPC dans lequel créer le cluster"
  type        = string
}

variable "subnetwork_self_link" {
  description = "Self-link du sous-réseau (doit avoir les ranges secondaires pods/services)"
  type        = string
}

variable "pods_range_name" {
  description = "Nom du range secondaire du sous-réseau utilisé pour les IP des pods"
  type        = string
}

variable "services_range_name" {
  description = "Nom du range secondaire du sous-réseau utilisé pour les IP des services"
  type        = string
}

variable "machine_type" {
  description = "Type de machine des nœuds du node pool"
  type        = string
  default     = "e2-small"
}

variable "disk_size_gb" {
  description = "Taille du disque (Go) de chaque nœud"
  type        = number
  default     = 30
}

variable "initial_node_count" {
  description = "Nombre de nœuds au démarrage du node pool"
  type        = number
  default     = 2
}

variable "min_node_count" {
  description = "Nombre minimum de nœuds (autoscaling)"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Nombre maximum de nœuds (autoscaling)"
  type        = number
  default     = 3
}
