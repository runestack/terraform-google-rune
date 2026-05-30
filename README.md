# terraform-google-rune

Provision a [Rune](https://github.com/runestack/rune) node on Google
Cloud: a Compute Engine instance, firewall rules, an optional static
external IP, a service account for Persistent Disk + Artifact Registry
access, cloud-init installation, and an optional one-shot admin
bootstrap.

> Open-source Terraform module. Tracks Rune releases under
> `var.rune_version`. Sibling of `terraform-aws-rune`,
> `terraform-digitalocean-rune`, and `terraform-hetzner-rune`.

## Features

- **Single-instance** provisioning with sensible defaults
  (Ubuntu 24.04, `e2-medium`, the `default` network).
- **cloud-init** (via the `user-data` metadata key) runs the upstream
  `install-server.sh`, pins to a specific `runed` version, and writes a
  templated `runefile.toml`.
- **Edge or worker** role via `var.node_role`. Edge nodes bind :80/:443,
  open them in the firewall, and run the ACME orchestrator for
  `tls.mode = auto` services.
- **Persistent Disks without a key.** The module creates a service
  account; `enable_pd_csi_access` grants it `roles/compute.storageAdmin`
  so the [`gce-pd` storage driver](https://docs.runestack.io/guides/persistent-storage/)
  provisions/attaches/snapshots disks via the instance's own credentials.
- **Optional static IP** for an address that survives stop/start.
- **Optional bootstrap** (`var.bootstrap = true`) that waits for the gRPC
  port, runs `rune admin bootstrap`, copies the token locally, and emits
  a ready-to-paste `rune login` command.

## Quick start

```hcl
provider "google" {
  project = "my-gcp-project"
  region  = "europe-west2"
}

module "rune" {
  source  = "runestack/rune/google"
  version = "0.0.1"

  zone           = "europe-west2-a"
  ssh_public_key = file("~/.ssh/id_ed25519.pub")

  node_role  = "edge"
  acme_email = "ops@example.com"

  allocate_static_ip = true
}

output "ip" {
  value = module.rune.public_ip
}
```

```bash
terraform init
terraform apply
```

The GCP **project and region** come from the `google` provider; the
**zone** is a module variable (the instance and its `gce-pd` disks are
zonal). Then point DNS at `module.rune.public_ip` and SSH in to
bootstrap, or set `bootstrap = true` to do it automatically.

## Examples

| Path | What it shows |
|---|---|
| [`examples/minimal`](./examples/minimal) | Single worker node, no TLS. |
| [`examples/edge-with-tls`](./examples/edge-with-tls) | Edge node with ACME-managed TLS + static IP. |
| [`examples/with-bootstrap`](./examples/with-bootstrap) | Edge + automated bootstrap + gce-pd via the service account. |

## After `terraform apply`

If you set `bootstrap = true`, you're done — paste the
`rune_login_command` output. Otherwise (the module creates `var.ssh_user`,
default `rune`, and runs privileged commands via `sudo`):

```bash
ssh rune@$(terraform output -raw public_ip) \
  'sudo rune admin bootstrap --out-file /tmp/rune-admin.token; sudo chmod 644 /tmp/rune-admin.token'

scp rune@$(terraform output -raw public_ip):/tmp/rune-admin.token ./rune-admin.token

rune login dev \
  --server $(terraform output -raw grpc_endpoint) \
  --token-file ./rune-admin.token
```

## Networking

By default the module places the instance in the project's **`default`**
network and creates network-tag-scoped firewall rules opening SSH, the
gRPC/HTTP API ports, and (for edge nodes) :80/:443. Override with
`var.network` / `var.subnetwork`, and tighten access with the
`*_allowed_cidrs` variables.

The ephemeral external IP changes on stop/start. Set
`allocate_static_ip = true` for any node you point DNS at or bootstrap
against.

## Persistent Disks / service account

`create_service_account = true` (default) creates a service account and
attaches it with the `cloud-platform` scope. Grant it disk permissions
with `enable_pd_csi_access = true` (`roles/compute.storageAdmin`) so the
`gce-pd` driver can manage Persistent Disks credential-free:

```hcl
enable_pd_csi_access            = true   # gce-pd storage driver
enable_artifact_registry_access = true   # private image pulls (default)
```

Add extra roles with `var.additional_service_account_roles`, or skip
module-managed IAM entirely by passing `var.service_account_email`.

## Cloud-init is at-most-once

cloud-init runs **only on first boot**. Changing `var.rune_version` or
any value rendered into `runefile.toml` after the instance exists will
NOT take effect on the running instance. To prevent accidental data loss,
the instance has
`lifecycle { ignore_changes = [metadata["user-data"], boot image] }` in
[`main.tf`](main.tf) — bumping `var.rune_version` (or a new upstream
image) advances the desired state in code without triggering a
destroy/recreate.

### Upgrade paths

| Scenario | Path |
| --- | --- |
| Routine version bump on an existing instance | Run [`scripts/upgrade-server.sh`](https://github.com/runestack/rune/blob/main/scripts/upgrade-server.sh) over SSH on the instance, then bump `var.rune_version` in code so new instances match. |
| Force a fresh instance on a new version | `terraform apply -replace=module.rune.google_compute_instance.this` — **wipes** `/var/lib/rune` (KEK, BadgerDB store) and any host-local volumes. |
| Re-render `runefile.toml` only | Out-of-band: edit `/etc/rune/runefile.toml` on the host and `systemctl reload runed`. |

See the [upgrade guide on docs.runestack.io](https://docs.runestack.io/operations/upgrades/).

## Bootstrap: re-rotate

```bash
terraform apply -replace=module.rune.null_resource.bootstrap[0]
```

Re-runs the SSH bootstrap and overwrites the local token file.

## Compatibility

- Terraform `>= 1.5.0`
- `hashicorp/google` provider `>= 5.0, < 7.0`
- Ubuntu 24.04 LTS (older releases may work; not supported)

## Related modules

| Cloud | Module |
|---|---|
| Google Cloud | This repo |
| AWS | `runestack/rune/aws` |
| DigitalOcean | `runestack/rune/digitalocean` |
| Hetzner Cloud | `runestack/rune/hcloud` |
| Azure | `runestack/rune/azurerm` *(planned)* |

## Contributing

Issues and PRs welcome. Please run `terraform fmt -recursive` and
`terraform validate` (in the root and each `examples/*` directory)
before opening a PR; CI will block otherwise.

## License

MIT — see [LICENSE](./LICENSE).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 5.0, < 7.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | >= 2.4 |
| <a name="requirement_null"></a> [null](#requirement\_null) | >= 3.2 |
## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | >= 5.0, < 7.0 |
| <a name="provider_null"></a> [null](#provider\_null) | >= 3.2 |
## Resources

| Name | Type |
|------|------|
| [google_compute_address.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_address) | resource |
| [google_compute_firewall.api](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.ingress](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.ssh](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_instance.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance) | resource |
| [google_project_iam_member.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_service_account.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [null_resource.bootstrap](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_acme_email"></a> [acme\_email](#input\_acme\_email) | Contact email for Let's Encrypt account registration. Required when node\_role = 'edge' and you intend to use tls.mode = auto/acme on services. | `string` | `""` | no |
| <a name="input_additional_service_account_roles"></a> [additional\_service\_account\_roles](#input\_additional\_service\_account\_roles) | Extra project IAM roles to grant the created service account (e.g. 'roles/logging.logWriter'). Only applies when the module creates the service account. | `list(string)` | `[]` | no |
| <a name="input_allocate_static_ip"></a> [allocate\_static\_ip](#input\_allocate\_static\_ip) | Reserve a static external IP and attach it, so the public address survives stop/start. Recommended for any node you bootstrap against or point DNS at. | `bool` | `false` | no |
| <a name="input_api_allowed_cidrs"></a> [api\_allowed\_cidrs](#input\_api\_allowed\_cidrs) | CIDR ranges allowed to reach the rune gRPC + HTTP API ports. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_assign_public_ip"></a> [assign\_public\_ip](#input\_assign\_public\_ip) | Give the instance an external IP. Ignored when allocate\_static\_ip = true (the static IP is used instead). Set false for private-only nodes reached over a VPN/bastion. | `bool` | `true` | no |
| <a name="input_boot_disk_size"></a> [boot\_disk\_size](#input\_boot\_disk\_size) | Boot disk size in GB. | `number` | `40` | no |
| <a name="input_boot_disk_type"></a> [boot\_disk\_type](#input\_boot\_disk\_type) | Boot disk type ('pd-balanced', 'pd-ssd', 'pd-standard'). | `string` | `"pd-balanced"` | no |
| <a name="input_bootstrap"></a> [bootstrap](#input\_bootstrap) | When true, the module SSHes into the instance after cloud-init finishes, runs `rune admin bootstrap`, copies the token to local disk, and outputs a `rune login` command. | `bool` | `false` | no |
| <a name="input_bootstrap_context_name"></a> [bootstrap\_context\_name](#input\_bootstrap\_context\_name) | CLI context name used in the emitted `rune login` command. Defaults to the instance name when unset. | `string` | `""` | no |
| <a name="input_bootstrap_namespace"></a> [bootstrap\_namespace](#input\_bootstrap\_namespace) | Default namespace baked into the emitted `rune login` command. | `string` | `"default"` | no |
| <a name="input_bootstrap_ssh_private_key"></a> [bootstrap\_ssh\_private\_key](#input\_bootstrap\_ssh\_private\_key) | PEM-encoded SSH private key matching ssh\_public\_key. Sensitive. Required when bootstrap = true. | `string` | `""` | no |
| <a name="input_bootstrap_ssh_user"></a> [bootstrap\_ssh\_user](#input\_bootstrap\_ssh\_user) | SSH user for the bootstrap step. Empty defaults to var.ssh\_user. | `string` | `""` | no |
| <a name="input_bootstrap_token_path"></a> [bootstrap\_token\_path](#input\_bootstrap\_token\_path) | Local path where the bootstrap admin token is written. Relative paths resolve against the consuming Terraform working directory. | `string` | `"rune-admin.token"` | no |
| <a name="input_bootstrap_wait_timeout"></a> [bootstrap\_wait\_timeout](#input\_bootstrap\_wait\_timeout) | How long to wait for the runed gRPC port to come up before bootstrapping. Format: '<n>m' or '<n>s'. | `string` | `"10m"` | no |
| <a name="input_cluster_cidr"></a> [cluster\_cidr](#input\_cluster\_cidr) | Cluster CIDR used by the rune networking layer for service IPs. | `string` | `"10.96.0.0/16"` | no |
| <a name="input_create_firewall"></a> [create\_firewall](#input\_create\_firewall) | Create VPC firewall rules (scoped to the instance's network tag). Disable if you manage firewalls externally. | `bool` | `true` | no |
| <a name="input_create_service_account"></a> [create\_service\_account](#input\_create\_service\_account) | Create a dedicated service account for the node and attach it. Ignored when service\_account\_email is set. | `bool` | `true` | no |
| <a name="input_docker_registries"></a> [docker\_registries](#input\_docker\_registries) | Private Docker registries rendered into [[docker.registries]] in runefile.toml. Three shapes: (1) from\_secret reference to an externally-managed Rune Secret; (2) from\_secret + bootstrap = true + data = { ... }; (3) inline username/password/token (demo use only). For Artifact Registry, prefer the node service account with enable\_artifact\_registry\_access. | <pre>list(object({<br/>    name      = string<br/>    registry  = string<br/>    auth_type = optional(string, "basic")<br/>    username  = optional(string, "")<br/>    password  = optional(string, "")<br/>    token     = optional(string, "")<br/>    region    = optional(string, "")<br/><br/>    from_secret           = optional(string, "")<br/>    from_secret_namespace = optional(string, "")<br/>    bootstrap             = optional(bool, false)<br/>    manage                = optional(string, "")<br/>    immutable             = optional(bool, false)<br/>    data                  = optional(map(string), {})<br/>  }))</pre> | `[]` | no |
| <a name="input_enable_artifact_registry_access"></a> [enable\_artifact\_registry\_access](#input\_enable\_artifact\_registry\_access) | Grant the created service account roles/artifactregistry.reader so runed can pull private images from Artifact Registry / GCR. Only applies when the module creates the service account. | `bool` | `true` | no |
| <a name="input_enable_pd_csi_access"></a> [enable\_pd\_csi\_access](#input\_enable\_pd\_csi\_access) | Grant the created service account roles/compute.storageAdmin so the gce-pd storage driver can create/attach/snapshot Persistent Disks via the instance's credentials. Only applies when the module creates the service account. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment label used in the instance name and labels (e.g. 'dev', 'prod'). | `string` | `"dev"` | no |
| <a name="input_extra_inbound_tcp_ports"></a> [extra\_inbound\_tcp\_ports](#input\_extra\_inbound\_tcp\_ports) | Additional TCP ports to open inbound (gated by api\_allowed\_cidrs). Useful while you stand up apps before they sit behind the edge ingress. | `list(number)` | `[]` | no |
| <a name="input_grpc_port"></a> [grpc\_port](#input\_grpc\_port) | Port for the rune gRPC API. | `number` | `7863` | no |
| <a name="input_http_port"></a> [http\_port](#input\_http\_port) | Port for the rune HTTP API. | `number` | `7861` | no |
| <a name="input_image"></a> [image](#input\_image) | Boot image. Accepts an image family ('ubuntu-os-cloud/ubuntu-2404-lts-amd64') or a full image self-link. Tested on Ubuntu 24.04 LTS. | `string` | `"ubuntu-os-cloud/ubuntu-2404-lts-amd64"` | no |
| <a name="input_ingress_allowed_cidrs"></a> [ingress\_allowed\_cidrs](#input\_ingress\_allowed\_cidrs) | CIDR ranges allowed to reach :80 and :443 when node\_role = 'edge'. Public by default since edge nodes terminate user traffic. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Extra labels applied to the instance. The module always adds 'rune = true' and 'rune-environment = <environment>'. | `map(string)` | `{}` | no |
| <a name="input_log_format"></a> [log\_format](#input\_log\_format) | Log format (text or json). | `string` | `"text"` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level (debug, info, warn, error). | `string` | `"info"` | no |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | GCE machine type. Edge nodes terminating ACME-signed traffic should be at least 2 vCPU / 4 GB (e2-medium gives 2 vCPU / 4 GB shared-core; use e2-standard-2 for dedicated). | `string` | `"e2-medium"` | no |
| <a name="input_metrics_addr"></a> [metrics\_addr](#input\_metrics\_addr) | Address for the Prometheus metrics endpoint. Default binds to loopback only; expose by setting to ':9100' AND opening the port via extra\_inbound\_tcp\_ports. | `string` | `"127.0.0.1:9100"` | no |
| <a name="input_name"></a> [name](#input\_name) | Instance name. When empty, defaults to 'rune-<environment>'. Also used as the prefix for the firewall, network tag, service account, and the default bootstrap CLI context name. GCE instance names must be 1–63 chars, lowercase, and DNS-1123. | `string` | `""` | no |
| <a name="input_network"></a> [network](#input\_network) | VPC network name or self-link to attach to. Defaults to the project's auto 'default' network. | `string` | `"default"` | no |
| <a name="input_node_role"></a> [node\_role](#input\_node\_role) | Rune node role. 'edge' nodes bind :80/:443 and run the ACME orchestrator; 'worker' nodes only run services. | `string` | `"edge"` | no |
| <a name="input_rune_version"></a> [rune\_version](#input\_rune\_version) | Rune release tag passed to install-server.sh on first boot (e.g. 'v0.0.1-dev.46'). The instance ignores user-data changes after creation (see lifecycle block in main.tf), so bumping this variable affects fresh instances only — for in-place upgrades on an existing instance, run scripts/upgrade-server.sh from the rune repo over SSH. | `string` | `"v0.0.1-dev.46"` | no |
| <a name="input_runed_environment"></a> [runed\_environment](#input\_runed\_environment) | Environment variables exported to the runed process via /etc/rune/runed.env (referenced by the systemd unit's EnvironmentFile). Use for secrets consumed by runefile bootstrap blocks. Pass via TF\_VAR\_runed\_environment or a sensitive tfvars file; values are written to the instance's filesystem with mode 0600. | `map(string)` | `{}` | no |
| <a name="input_service_account_email"></a> [service\_account\_email](#input\_service\_account\_email) | Email of an existing service account to attach. When set, the module does NOT create one (create\_service\_account is ignored). | `string` | `""` | no |
| <a name="input_service_account_scopes"></a> [service\_account\_scopes](#input\_service\_account\_scopes) | OAuth scopes for the attached service account. The default 'cloud-platform' lets IAM roles fully govern access (recommended). Narrow only if you understand GCE's scope/role interaction. | `list(string)` | <pre>[<br/>  "cloud-platform"<br/>]</pre> | no |
| <a name="input_ssh_allowed_cidrs"></a> [ssh\_allowed\_cidrs](#input\_ssh\_allowed\_cidrs) | CIDR ranges allowed to reach SSH (port 22). Tighten in production. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | SSH public key contents (e.g. file("~/.ssh/id\_ed25519.pub")) installed for ssh\_user via instance metadata. Required so cloud-init / bootstrap can reach the host. | `string` | n/a | yes |
| <a name="input_ssh_user"></a> [ssh\_user](#input\_ssh\_user) | Login user created via SSH-key metadata, and the SSH user for the bootstrap step. | `string` | `"rune"` | no |
| <a name="input_subnetwork"></a> [subnetwork](#input\_subnetwork) | Subnetwork name or self-link. Empty lets GCE pick the subnet for the region in the chosen network (works for auto-mode networks like 'default'). | `string` | `""` | no |
| <a name="input_zone"></a> [zone](#input\_zone) | GCE zone for the instance (e.g. 'europe-west2-a'). The instance and any gce-pd Persistent Disks are pinned to this zone. | `string` | `"europe-west2-a"` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bootstrap_token_path"></a> [bootstrap\_token\_path](#output\_bootstrap\_token\_path) | Local path where the admin bootstrap token was written. Empty when bootstrap = false. |
| <a name="output_grpc_endpoint"></a> [grpc\_endpoint](#output\_grpc\_endpoint) | Address to point the rune CLI `--server` flag at. |
| <a name="output_http_endpoint"></a> [http\_endpoint](#output\_http\_endpoint) | rune HTTP API base URL. |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | GCE instance ID. |
| <a name="output_instance_name"></a> [instance\_name](#output\_instance\_name) | Instance name (var.name when set, otherwise 'rune-<environment>'). |
| <a name="output_network_tag"></a> [network\_tag](#output\_network\_tag) | Network tag applied to the instance and targeted by the firewall rules. |
| <a name="output_private_ip"></a> [private\_ip](#output\_private\_ip) | Internal IPv4 address of the instance. |
| <a name="output_public_ip"></a> [public\_ip](#output\_public\_ip) | External IPv4 address (the static IP when allocate\_static\_ip = true, otherwise the ephemeral external IP; empty for private-only instances). |
| <a name="output_rune_login_command"></a> [rune\_login\_command](#output\_rune\_login\_command) | Ready-to-paste `rune login` command. Empty when bootstrap = false. |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | Instance self-link. |
| <a name="output_service_account_email"></a> [service\_account\_email](#output\_service\_account\_email) | Service account attached to the instance (created or pre-existing; empty when none). |
| <a name="output_static_ip"></a> [static\_ip](#output\_static\_ip) | Reserved static external IP (empty when allocate\_static\_ip = false). |
| <a name="output_zone"></a> [zone](#output\_zone) | Zone the instance (and its gce-pd disks) live in. |
<!-- END_TF_DOCS -->
