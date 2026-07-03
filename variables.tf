# ---------------------------------------------------------------
# Required
# ---------------------------------------------------------------

variable "ssh_public_key" {
  type        = string
  description = "SSH public key contents (e.g. file(\"~/.ssh/id_ed25519.pub\")) installed for ssh_user via instance metadata. Required so cloud-init / bootstrap can reach the host."
  validation {
    condition     = length(trimspace(var.ssh_public_key)) > 0
    error_message = "ssh_public_key must be a non-empty SSH public key."
  }
}

# ---------------------------------------------------------------
# Naming + placement
#
# NOTE: the GCP project and region are taken from the `google`
# provider configuration, not module variables — modules should not
# configure providers. The zone IS a module variable: it's where the
# instance and its zonal Persistent Disks live, and the gce-pd
# storage driver needs to match it.
# ---------------------------------------------------------------

variable "name" {
  type        = string
  description = "Instance name. When empty, defaults to 'rune-<environment>'. Also used as the prefix for the firewall, network tag, service account, and the default bootstrap CLI context name. GCE instance names must be 1–63 chars, lowercase, and DNS-1123."
  default     = ""
}

variable "environment" {
  type        = string
  description = "Environment label used in the instance name and labels (e.g. 'dev', 'prod')."
  default     = "dev"
}

variable "zone" {
  type        = string
  description = "GCE zone for the instance (e.g. 'europe-west2-a'). The instance and any gce-pd Persistent Disks are pinned to this zone."
  default     = "europe-west2-a"
}

variable "machine_type" {
  type        = string
  description = "GCE machine type. Edge nodes terminating ACME-signed traffic should be at least 2 vCPU / 4 GB (e2-medium gives 2 vCPU / 4 GB shared-core; use e2-standard-2 for dedicated)."
  default     = "e2-medium"
}

variable "image" {
  type        = string
  description = "Boot image. Accepts an image family ('ubuntu-os-cloud/ubuntu-2404-lts-amd64') or a full image self-link. Tested on Ubuntu 24.04 LTS."
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "labels" {
  type        = map(string)
  description = "Extra labels applied to the instance. The module always adds 'rune = true' and 'rune-environment = <environment>'."
  default     = {}
}

variable "ssh_user" {
  type        = string
  description = "Login user created via SSH-key metadata, and the SSH user for the bootstrap step."
  default     = "rune"
}

# ---------------------------------------------------------------
# Networking
# ---------------------------------------------------------------

variable "network" {
  type        = string
  description = "VPC network name or self-link to attach to. Defaults to the project's auto 'default' network."
  default     = "default"
}

variable "subnetwork" {
  type        = string
  description = "Subnetwork name or self-link. Empty lets GCE pick the subnet for the region in the chosen network (works for auto-mode networks like 'default')."
  default     = ""
}

variable "assign_public_ip" {
  type        = bool
  description = "Give the instance an external IP. Ignored when allocate_static_ip = true (the static IP is used instead). Set false for private-only nodes reached over a VPN/bastion."
  default     = true
}

variable "allocate_static_ip" {
  type        = bool
  description = "Reserve a static external IP and attach it, so the public address survives stop/start. Recommended for any node you bootstrap against or point DNS at."
  default     = false
}

variable "boot_disk_size" {
  type        = number
  description = "Boot disk size in GB."
  default     = 40
}

variable "boot_disk_type" {
  type        = string
  description = "Boot disk type ('pd-balanced', 'pd-ssd', 'pd-standard')."
  default     = "pd-balanced"
}

# ---------------------------------------------------------------
# Firewall
# ---------------------------------------------------------------

variable "create_firewall" {
  type        = bool
  description = "Create VPC firewall rules (scoped to the instance's network tag). Disable if you manage firewalls externally."
  default     = true
}

variable "ssh_allowed_cidrs" {
  type        = list(string)
  description = "CIDR ranges allowed to reach SSH (port 22). Tighten in production."
  default     = ["0.0.0.0/0"]
}

variable "api_allowed_cidrs" {
  type        = list(string)
  description = "CIDR ranges allowed to reach the rune gRPC + HTTP API ports."
  default     = ["0.0.0.0/0"]
}

variable "ingress_allowed_cidrs" {
  type        = list(string)
  description = "CIDR ranges allowed to reach :80 and :443 when node_role = 'edge'. Public by default since edge nodes terminate user traffic."
  default     = ["0.0.0.0/0"]
}

variable "extra_inbound_tcp_ports" {
  type        = list(number)
  description = "Additional TCP ports to open inbound (gated by api_allowed_cidrs). Useful while you stand up apps before they sit behind the edge ingress."
  default     = []
}

# ---------------------------------------------------------------
# Service account (Persistent Disk + Artifact Registry access)
#
# A service account lets runed mint Persistent Disks (the gce-pd
# storage driver) and pull images from Artifact Registry / GCR with
# no stored credentials.
# ---------------------------------------------------------------

variable "create_service_account" {
  type        = bool
  description = "Create a dedicated service account for the node and attach it. Ignored when service_account_email is set."
  default     = true
}

variable "service_account_email" {
  type        = string
  description = "Email of an existing service account to attach. When set, the module does NOT create one (create_service_account is ignored)."
  default     = ""
}

variable "enable_artifact_registry_access" {
  type        = bool
  description = "Grant the created service account roles/artifactregistry.reader (only when the module creates the service account) AND render a [[docker.registries]] entry with auth type 'gcp' for *.pkg.dev into runefile.toml, so runed authenticates private Artifact Registry pulls via the instance metadata service account. Requires rune >= the version shipping the gcp registry-auth provider (runestack/rune#144)."
  default     = true
}

variable "enable_pd_csi_access" {
  type        = bool
  description = "Grant the created service account roles/compute.storageAdmin so the gce-pd storage driver can create/attach/snapshot Persistent Disks via the instance's credentials. Only applies when the module creates the service account."
  default     = false
}

variable "additional_service_account_roles" {
  type        = list(string)
  description = "Extra project IAM roles to grant the created service account (e.g. 'roles/logging.logWriter'). Only applies when the module creates the service account."
  default     = []
}

variable "service_account_scopes" {
  type        = list(string)
  description = "OAuth scopes for the attached service account. The default 'cloud-platform' lets IAM roles fully govern access (recommended). Narrow only if you understand GCE's scope/role interaction."
  default     = ["cloud-platform"]
}

# ---------------------------------------------------------------
# Rune installation
# ---------------------------------------------------------------

variable "rune_version" {
  type        = string
  description = "Rune release tag passed to install-server.sh on first boot (e.g. 'v0.0.1-dev.46'). The instance ignores user-data changes after creation (see lifecycle block in main.tf), so bumping this variable affects fresh instances only — for in-place upgrades on an existing instance, run scripts/upgrade-server.sh from the rune repo over SSH."
  default     = "v0.0.1-dev.46"
}

# ---------------------------------------------------------------
# Rune runtime config (rendered into /etc/rune/runefile.toml)
# ---------------------------------------------------------------

variable "node_role" {
  type        = string
  description = "Rune node role. 'edge' nodes bind :80/:443 and run the ACME orchestrator; 'worker' nodes only run services."
  default     = "edge"
  validation {
    condition     = contains(["edge", "worker"], var.node_role)
    error_message = "node_role must be 'edge' or 'worker'."
  }
}

variable "grpc_port" {
  type        = number
  description = "Port for the rune gRPC API."
  default     = 7863
}

variable "http_port" {
  type        = number
  description = "Port for the rune HTTP API."
  default     = 7861
}

variable "cluster_cidr" {
  type        = string
  description = "Cluster CIDR used by the rune networking layer for service IPs."
  default     = "10.96.0.0/16"
}

variable "log_level" {
  type        = string
  description = "Log level (debug, info, warn, error)."
  default     = "info"
}

variable "log_format" {
  type        = string
  description = "Log format (text or json)."
  default     = "text"
}

variable "metrics_addr" {
  type        = string
  description = "Address for the Prometheus metrics endpoint. Default binds to loopback only; expose by setting to ':9100' AND opening the port via extra_inbound_tcp_ports."
  default     = "127.0.0.1:9100"
}

variable "acme_email" {
  type        = string
  description = "Contact email for Let's Encrypt account registration. Required when node_role = 'edge' and you intend to use tls.mode = auto/acme on services."
  default     = ""
  validation {
    condition     = var.acme_email == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.acme_email))
    error_message = "acme_email must be a valid email address or empty."
  }
}

# ---------------------------------------------------------------
# Docker registry credentials (rendered into [[docker.registries]])
# Shape mirrors terraform-aws-rune; see that module's variables.tf
# for the long-form documentation of each shape. For Artifact
# Registry / GCR, the cleanest path is the instance service account
# (enable_artifact_registry_access) rather than inline credentials.
# ---------------------------------------------------------------

variable "docker_registries" {
  type = list(object({
    name      = string
    registry  = string
    auth_type = optional(string, "basic")
    username  = optional(string, "")
    password  = optional(string, "")
    token     = optional(string, "")
    region    = optional(string, "")

    from_secret           = optional(string, "")
    from_secret_namespace = optional(string, "")
    bootstrap             = optional(bool, false)
    manage                = optional(string, "")
    immutable             = optional(bool, false)
    data                  = optional(map(string), {})
  }))
  description = "Private Docker registries rendered into [[docker.registries]] in runefile.toml. Three shapes: (1) from_secret reference to an externally-managed Rune Secret; (2) from_secret + bootstrap = true + data = { ... }; (3) inline username/password/token (demo use only). For Artifact Registry, prefer the node service account with enable_artifact_registry_access."
  default     = []
  sensitive   = true
  validation {
    condition = alltrue([
      for r in var.docker_registries : contains(["basic", "token", "ecr", "gcp"], r.auth_type)
    ])
    error_message = "Each docker_registries[*].auth_type must be 'basic', 'token', 'ecr', or 'gcp'."
  }
  validation {
    condition = alltrue([
      for r in var.docker_registries :
      r.auth_type != "basic" || r.from_secret != "" || (r.username != "" && r.password != "")
    ])
    error_message = "docker_registries entries with auth_type = 'basic' require either from_secret or both username and password."
  }
  validation {
    condition = alltrue([
      for r in var.docker_registries :
      r.auth_type != "token" || r.from_secret != "" || r.token != ""
    ])
    error_message = "docker_registries entries with auth_type = 'token' require either from_secret or a non-empty token."
  }
  validation {
    condition = alltrue([
      for r in var.docker_registries :
      r.from_secret == "" || (r.username == "" && r.password == "" && r.token == "")
    ])
    error_message = "docker_registries entries with from_secret set must NOT also set username/password/token — credentials live inside the Rune Secret."
  }
  validation {
    condition = alltrue([
      for r in var.docker_registries :
      !r.bootstrap || (r.from_secret != "" && length(r.data) > 0)
    ])
    error_message = "docker_registries entries with bootstrap = true require both from_secret and a non-empty data map."
  }
  validation {
    condition = alltrue([
      for r in var.docker_registries :
      length(r.data) == 0 || r.bootstrap
    ])
    error_message = "docker_registries[*].data is the bootstrap seed for fromSecret creation. Set bootstrap = true, or drop the data block and create the secret out-of-band with `rune cast secret`."
  }
}

variable "runed_environment" {
  type        = map(string)
  description = "Environment variables exported to the runed process via /etc/rune/runed.env (referenced by the systemd unit's EnvironmentFile). Use for secrets consumed by runefile bootstrap blocks. Pass via TF_VAR_runed_environment or a sensitive tfvars file; values are written to the instance's filesystem with mode 0600."
  default     = {}
  sensitive   = true
}

# ---------------------------------------------------------------
# Optional in-module bootstrap
# ---------------------------------------------------------------

variable "bootstrap" {
  type        = bool
  description = "When true, the module SSHes into the instance after cloud-init finishes, runs `rune admin bootstrap`, copies the token to local disk, and outputs a `rune login` command."
  default     = false
}

variable "bootstrap_ssh_user" {
  type        = string
  description = "SSH user for the bootstrap step. Empty defaults to var.ssh_user."
  default     = ""
}

variable "bootstrap_ssh_private_key" {
  type        = string
  description = "PEM-encoded SSH private key matching ssh_public_key. Sensitive. Required when bootstrap = true."
  default     = ""
  sensitive   = true
}

variable "bootstrap_token_path" {
  type        = string
  description = "Local path where the bootstrap admin token is written. Relative paths resolve against the consuming Terraform working directory."
  default     = "rune-admin.token"
}

variable "bootstrap_namespace" {
  type        = string
  description = "Default namespace baked into the emitted `rune login` command."
  default     = "default"
}

variable "bootstrap_context_name" {
  type        = string
  description = "CLI context name used in the emitted `rune login` command. Defaults to the instance name when unset."
  default     = ""
}

variable "bootstrap_wait_timeout" {
  type        = string
  description = "How long to wait for the runed gRPC port to come up before bootstrapping. Format: '<n>m' or '<n>s'."
  default     = "10m"
}
