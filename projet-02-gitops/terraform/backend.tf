terraform {
  required_version = ">= 1.9"

  backend "gcs" {
    bucket = "devops-498817-tfstate"
    prefix = "projet-02-gitops/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
