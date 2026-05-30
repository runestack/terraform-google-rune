# Changelog

All notable changes to this module are documented here. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/).

This module is pre-1.0 and tracks Rune's own pre-1.0 development.
Breaking changes can land on any minor bump (`0.x.0`) until
`v1.0.0`. Patch bumps (`0.x.y`) stay backwards-compatible.

## [Unreleased]

## [0.0.1] - 2026-05-29

### Added
- Initial public release. Port of `terraform-aws-rune` to Google
  Compute Engine.
- Single-instance provisioning: `google_compute_instance`, network-tag
  scoped firewall rules, optional static external IP, optional service
  account.
- cloud-init (via the `user-data` metadata key) installs `runed` via the
  upstream installer pinned to `var.rune_version` (default
  `v0.0.1-dev.46`) and renders a templated `/etc/rune/runefile.toml`.
- `node_role` toggle between `edge` (binds :80/:443, runs ACME) and
  `worker`.
- Optional service account created by default; toggles to grant
  `roles/artifactregistry.reader` (image pulls) and
  `roles/compute.storageAdmin` (so the `gce-pd` storage driver can manage
  Persistent Disks via the instance's credentials, no key required).
- `lifecycle { ignore_changes = [metadata["user-data"], boot image] }` so
  a `rune_version` bump (or a new upstream image) does not trigger a
  destroy/recreate that would wipe `/var/lib/rune`. In-place upgrades
  happen out-of-band via `scripts/upgrade-server.sh`.
- Optional `bootstrap = true` flow: SSHes in (as `var.ssh_user`), runs
  `sudo rune admin bootstrap`, copies the token to disk, outputs the
  ready-to-paste `rune login` command.
- `docker_registries` and `runed_environment` inputs matching the AWS /
  DigitalOcean modules' shapes and validations.
- Examples: `minimal`, `edge-with-tls`, `with-bootstrap`.

[Unreleased]: https://github.com/runestack/terraform-google-rune/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/runestack/terraform-google-rune/releases/tag/v0.0.1
