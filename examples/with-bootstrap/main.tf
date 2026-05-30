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

# Edge node + auto-bootstrap. After `terraform apply`, the admin token is
# on disk and `terraform output rune_login_command` prints a ready-to-paste
# login.
#
# enable_pd_csi_access grants the node's service account
# roles/compute.storageAdmin, so the gce-pd storage driver can
# provision/attach/snapshot Persistent Disks through the instance's own
# credentials — no service-account key in Terraform state or on disk.
module "rune" {
  source = "../.."

  environment    = "demo"
  zone           = var.zone
  ssh_public_key = file(var.ssh_public_key_path)

  node_role          = "edge"
  acme_email         = var.acme_email
  allocate_static_ip = true

  bootstrap                 = true
  bootstrap_ssh_private_key = file(var.ssh_private_key_path)
  bootstrap_token_path      = "${path.cwd}/rune-admin.token"
  bootstrap_namespace       = "default"

  # Let the gce-pd driver manage Persistent Disks via the instance SA.
  enable_pd_csi_access = true
}

output "public_ip" { value = module.rune.public_ip }
output "rune_login_command" { value = module.rune.rune_login_command }
output "bootstrap_token_path" { value = module.rune.bootstrap_token_path }
output "service_account_email" { value = module.rune.service_account_email }
