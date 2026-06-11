module "network" {
  source     = "../modules/network"
  project_id = var.project_id
  region     = var.region
}

module "iam" {
  source     = "../modules/iam"
  project_id = var.project_id

  iam_bindings = {
    "roles/iap.tunnelResourceAccessor" = ["user:${var.admin_email}"]
    "roles/compute.osAdminLogin"       = ["user:${var.admin_email}"]
  }
}

module "budget" {
  source             = "../modules/budget"
  project_id         = var.project_id
  billing_account_id = var.billing_account_id
}

module "compute" {
  source           = "../modules/compute"
  project_id       = var.project_id
  zone             = var.zone
  subnet_self_link = module.network.subnet_self_link
  vpc_id           = module.network.vpc_id
}

module "wif" {
  source      = "../modules/wif-pool"
  project_id  = var.project_id
  github_repo = var.github_repo
}
