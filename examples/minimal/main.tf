terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 7.0"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
}

module "rune" {
  source = "../.."

  environment    = "dev"
  zone           = var.zone
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))

  # Single worker node — no edge ingress, no ACME.
  node_role = "worker"
}

output "grpc_endpoint" { value = module.rune.grpc_endpoint }
output "public_ip" { value = module.rune.public_ip }
