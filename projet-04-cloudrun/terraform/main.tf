# State de la fondation (landing-zone) — fournit le pool WIF partagé
data "terraform_remote_state" "foundation" {
  backend = "gcs"
  config = {
    bucket = "devops-498817-tfstate"
    prefix = "landing-zone/state"
  }
}

module "cloudrun_service" {
  source = "../../modules/cloudrun-service"

  project_id                  = var.project_id
  region                      = var.region
  github_repo                 = var.github_repo
  workload_identity_pool_name = data.terraform_remote_state.foundation.outputs.workload_identity_pool_name
}
