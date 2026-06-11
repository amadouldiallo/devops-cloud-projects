# Pool WIF dédié à ce projet — détruire/recréer ce state n'affecte aucun
# autre projet (et inversement).
module "wif" {
  source      = "../../modules/wif-pool"
  project_id  = var.project_id
  github_repo = var.github_repo
  pool_id     = "github-pool-p04"
}

module "cloudrun_service" {
  source = "../../modules/cloudrun-service"

  project_id                  = var.project_id
  region                      = var.region
  github_repo                 = var.github_repo
  workload_identity_pool_name = module.wif.pool_name
}
