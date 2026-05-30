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
<!-- END_TF_DOCS -->
