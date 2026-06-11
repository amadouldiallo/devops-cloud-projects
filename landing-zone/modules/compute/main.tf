# SA dédié à la VM de lab — droits minimaux (pas le SA par défaut, pas terraform-runner)
resource "google_service_account" "lab_vm" {
  project      = var.project_id
  account_id   = "lab-vm"
  display_name = "Lab VM"
  description  = "Compte de service de la VM de développement à la demande"
}

resource "google_project_iam_member" "lab_vm_roles" {
  for_each = toset(var.lab_vm_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.lab_vm.email}"
}

# Autorise le SSH via IAP uniquement (plage réservée Google), pas d'exposition publique du port 22
resource "google_compute_firewall" "allow_iap_ssh" {
  project   = var.project_id
  name      = "lab-vm-allow-iap-ssh"
  network   = var.vpc_id
  direction = "INGRESS"

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["iap-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# VM de lab à la demande — pas d'IP publique (sortie via Cloud NAT, entrée via IAP)
resource "google_compute_instance" "lab_vm" {
  project      = var.project_id
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["iap-ssh"]

  boot_disk {
    initialize_params {
      image = var.boot_image
      size  = var.boot_disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = var.subnet_self_link
    # Pas de bloc access_config => pas d'IP publique
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    email  = google_service_account.lab_vm.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "true"
  }

  metadata_startup_script = file("${path.module}/files/setup.sh")

  allow_stopping_for_update = true

  # Créée à l'arrêt : démarrée à la demande via `gcloud compute instances start`
  desired_status = "TERMINATED"

  lifecycle {
    ignore_changes = [desired_status] # ne pas reverter un start/stop manuel via gcloud
  }
}
