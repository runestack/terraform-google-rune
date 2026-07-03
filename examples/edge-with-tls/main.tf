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

# Edge node terminating ACME-managed TLS for one or more services whose
# `expose.host` resolves to the instance's IP. A static external IP keeps
# the address stable across stop/start.
module "rune" {
  source = "../.."

  environment    = var.environment
  zone           = var.zone
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))

  node_role          = "edge"
  acme_email         = var.acme_email
  allocate_static_ip = true
}

output "public_ip" { value = module.rune.public_ip }
output "grpc_endpoint" { value = module.rune.grpc_endpoint }

output "next_steps" {
  value = <<-EOT
    1. Point your DNS A record at: ${module.rune.public_ip}
    2. Wait for cloud-init: ssh rune@${module.rune.public_ip} 'tail -f /var/log/user-data.log'
    3. Bootstrap:           ssh rune@${module.rune.public_ip} 'sudo rune admin bootstrap --out-file /tmp/rune-admin.token'
    4. Login + cast a service with expose.host + tls.mode = auto.
  EOT
}
