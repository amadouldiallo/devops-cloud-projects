# VPC dédié à ce projet — détruire/recréer ce state n'affecte aucun autre
# projet (et inversement), même logique que le pool WIF du Projet 04.
# Ranges secondaires "pods"/"services" requis pour un cluster GKE VPC-native.
module "network" {
  source = "../../modules/network"

  project_id  = var.project_id
  region      = var.region
  vpc_name    = "gitops-vpc"
  subnet_cidr = "10.20.0.0/20"

  secondary_ip_ranges = [
    { range_name = "pods", ip_cidr_range = "10.21.0.0/16" },
    { range_name = "services", ip_cidr_range = "10.22.0.0/20" },
  ]
}

module "gke_cluster" {
  source = "../../modules/gke-cluster"

  project_id = var.project_id
  zone       = var.zone

  cluster_name         = var.cluster_name
  network_self_link    = module.network.vpc_self_link
  subnetwork_self_link = module.network.subnet_self_link
  pods_range_name      = "pods"
  services_range_name  = "services"
}
