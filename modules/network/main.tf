# VPC principal — pas de sous-réseaux auto-créés, on les déclare explicitement
resource "google_compute_network" "main" {
  project                 = var.project_id
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

# Sous-réseau régional, avec logs de flux activés (visibilité réseau)
resource "google_compute_subnetwork" "main" {
  project                  = var.project_id
  name                     = "${var.vpc_name}-subnet-${var.region}"
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true # CKV_GCP_74 : permet aux VM sans IP publique d'atteindre les APIs Google

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Router — prérequis pour Cloud NAT
resource "google_compute_router" "main" {
  project = var.project_id
  name    = "${var.vpc_name}-router-${var.region}"
  region  = var.region
  network = google_compute_network.main.id
}

# Cloud NAT — donne un accès Internet sortant aux instances sans IP publique
resource "google_compute_router_nat" "main" {
  project                            = var.project_id
  name                               = "${var.vpc_name}-nat-${var.region}"
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
