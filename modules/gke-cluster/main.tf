# API GKE — requise pour créer un cluster
resource "google_project_service" "gke" {
  project            = var.project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

# SA dédié aux nœuds — jamais le compte de service Compute Engine par défaut
# (souvent rôle Editor sur le projet). Rôles minimaux recommandés par Google
# pour la télémétrie (logs/metrics) ; oauth_scopes = cloud-platform avec accès
# réel borné par ces rôles IAM (principe du moindre privilège, cf. CKS J3-J4).
resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE nodes (${var.cluster_name})"
}

resource "google_project_iam_member" "gke_node_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Cluster zonal, VPC-native (alias IP via les ranges secondaires pods/services
# du sous-réseau). Le node pool par défaut est supprimé : on gère notre propre
# node pool ci-dessous (taille, autoscaling, SA dédié).
resource "google_container_cluster" "primary" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.zone

  network    = var.network_self_link
  subnetwork = var.subnetwork_self_link

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  remove_default_node_pool = true
  initial_node_count       = 1

  # Lab : permet `terraform destroy` sans étape manuelle de déprotection
  deletion_protection = false

  depends_on = [google_project_service.gke]
}

resource "google_container_node_pool" "primary" {
  project  = var.project_id
  name     = "${var.cluster_name}-pool"
  cluster  = google_container_cluster.primary.name
  location = google_container_cluster.primary.location

  node_count = var.initial_node_count

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.machine_type
    disk_size_gb    = var.disk_size_gb
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}
