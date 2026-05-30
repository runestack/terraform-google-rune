# ---------------------------------------------------------------
# terraform-google-rune
#
# Provisions a single Google Compute Engine instance running the Rune
# server (`runed`). cloud-init (via the `user-data` metadata key)
# installs Rune via the upstream installer script and writes a
# runefile.toml shaped by this module's inputs.
#
# Project + region come from the `google` provider; the zone is a
# module variable (the instance and its gce-pd disks are zonal).
#
# Optional bootstrap (var.bootstrap = true) SSHes in once the
# instance is reachable, runs `rune admin bootstrap`, copies the
# token locally, and emits the `rune login` command as an output.
# ---------------------------------------------------------------

locals {
  name = var.name != "" ? var.name : "rune-${var.environment}"

  base_labels = {
    rune             = "true"
    rune-environment = var.environment
  }
  labels = merge(local.base_labels, var.labels)

  # Network tag used to target the firewall rules at this instance.
  network_tag = "${local.name}-fw"

  # Sorted KEY=VALUE lines for /etc/rune/runed.env. Sorting keeps the
  # rendered user-data stable across applies.
  runed_env_file = join("\n", [
    for k in sort(keys(var.runed_environment)) :
    "${k}=${var.runed_environment[k]}"
  ])

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    rune_version      = var.rune_version
    runefile          = local.runefile
    runed_environment = local.runed_env_file
  })

  runefile = templatefile("${path.module}/templates/runefile.toml.tftpl", {
    grpc_address      = ":${var.grpc_port}"
    http_address      = ":${var.http_port}"
    cluster_cidr      = var.cluster_cidr
    node_role         = var.node_role
    log_level         = var.log_level
    log_format        = var.log_format
    metrics_addr      = var.metrics_addr
    acme_email        = var.acme_email
    docker_registries = var.docker_registries
  })

  # Service account resolution.
  create_sa = var.service_account_email == "" && var.create_service_account
  sa_email  = var.service_account_email != "" ? var.service_account_email : (local.create_sa ? google_service_account.this[0].email : "")
  sa_roles = local.create_sa ? toset(concat(
    var.enable_artifact_registry_access ? ["roles/artifactregistry.reader"] : [],
    var.enable_pd_csi_access ? ["roles/compute.storageAdmin"] : [],
    var.additional_service_account_roles,
  )) : toset([])

  # Stable public address used by bootstrap + outputs.
  public_ip = var.allocate_static_ip ? try(google_compute_address.this[0].address, "") : (
    var.assign_public_ip ? try(google_compute_instance.this.network_interface[0].access_config[0].nat_ip, "") : ""
  )

  bootstrap_ssh_user = var.bootstrap_ssh_user != "" ? var.bootstrap_ssh_user : var.ssh_user

  # Inbound TCP port lists for the firewall rules.
  api_ports = concat(
    [tostring(var.grpc_port), tostring(var.http_port)],
    [for p in var.extra_inbound_tcp_ports : tostring(p)],
  )
}

# ---------------------------------------------------------------
# Project (for IAM bindings) — read from the provider.
# ---------------------------------------------------------------

data "google_project" "current" {}

# ---------------------------------------------------------------
# Service account (optional)
# ---------------------------------------------------------------

resource "google_service_account" "this" {
  count        = local.create_sa ? 1 : 0
  account_id   = substr("${local.name}-sa", 0, 30)
  display_name = "Rune node ${local.name}"
}

resource "google_project_iam_member" "this" {
  for_each = local.sa_roles
  project  = data.google_project.current.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.this[0].email}"
}

# ---------------------------------------------------------------
# Static external IP (optional)
# ---------------------------------------------------------------

resource "google_compute_address" "this" {
  count = var.allocate_static_ip ? 1 : 0
  name  = "${local.name}-ip"
}

# ---------------------------------------------------------------
# Instance
# ---------------------------------------------------------------

resource "google_compute_instance" "this" {
  name         = local.name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = [local.network_tag]
  labels       = local.labels

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.boot_disk_size
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork != "" ? var.subnetwork : null

    # Static IP wins; otherwise an ephemeral external IP when requested;
    # otherwise no external IP (private-only).
    dynamic "access_config" {
      for_each = var.allocate_static_ip ? [1] : (var.assign_public_ip ? [1] : [])
      content {
        nat_ip = var.allocate_static_ip ? google_compute_address.this[0].address : null
      }
    }
  }

  metadata = {
    # cloud-init on GCE Ubuntu images reads the `user-data` key and runs
    # it at-most-once per instance.
    user-data = local.user_data
    ssh-keys  = "${var.ssh_user}:${trimspace(var.ssh_public_key)}"
  }

  dynamic "service_account" {
    for_each = local.sa_email != "" ? [1] : []
    content {
      email  = local.sa_email
      scopes = var.service_account_scopes
    }
  }

  lifecycle {
    # cloud-init runs at-most-once per instance, so changed user-data
    # never re-executes on an existing host; ignore it so a bumped
    # rune_version advances in code without a perpetual diff. The boot
    # image is ignored too: an image-family reference resolves to the
    # latest image, which would otherwise force a destroy/recreate that
    # wipes /var/lib/rune (KEK, BadgerDB store).
    #
    # To deliberately rebuild on a new version/image, use
    # `terraform apply -replace=...` or taint the instance.
    ignore_changes = [
      metadata["user-data"],
      boot_disk[0].initialize_params[0].image,
    ]
  }
}

# ---------------------------------------------------------------
# Firewall (network-tag scoped)
# ---------------------------------------------------------------

resource "google_compute_firewall" "ssh" {
  count         = var.create_firewall ? 1 : 0
  name          = "${local.name}-ssh"
  network       = var.network
  direction     = "INGRESS"
  target_tags   = [local.network_tag]
  source_ranges = var.ssh_allowed_cidrs

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "api" {
  count         = var.create_firewall ? 1 : 0
  name          = "${local.name}-api"
  network       = var.network
  direction     = "INGRESS"
  target_tags   = [local.network_tag]
  source_ranges = var.api_allowed_cidrs

  allow {
    protocol = "tcp"
    ports    = local.api_ports
  }
}

resource "google_compute_firewall" "ingress" {
  count         = var.create_firewall && var.node_role == "edge" ? 1 : 0
  name          = "${local.name}-ingress"
  network       = var.network
  direction     = "INGRESS"
  target_tags   = [local.network_tag]
  source_ranges = var.ingress_allowed_cidrs

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}
