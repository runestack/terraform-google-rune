output "instance_id" {
  description = "GCE instance ID."
  value       = google_compute_instance.this.instance_id
}

output "instance_name" {
  description = "Instance name (var.name when set, otherwise 'rune-<environment>')."
  value       = google_compute_instance.this.name
}

output "self_link" {
  description = "Instance self-link."
  value       = google_compute_instance.this.self_link
}

output "zone" {
  description = "Zone the instance (and its gce-pd disks) live in."
  value       = google_compute_instance.this.zone
}

output "public_ip" {
  description = "External IPv4 address (the static IP when allocate_static_ip = true, otherwise the ephemeral external IP; empty for private-only instances)."
  value       = local.public_ip
}

output "private_ip" {
  description = "Internal IPv4 address of the instance."
  value       = google_compute_instance.this.network_interface[0].network_ip
}

output "grpc_endpoint" {
  description = "Address to point the rune CLI `--server` flag at."
  value       = "${local.public_ip}:${var.grpc_port}"
}

output "http_endpoint" {
  description = "rune HTTP API base URL."
  value       = "http://${local.public_ip}:${var.http_port}"
}

output "network_tag" {
  description = "Network tag applied to the instance and targeted by the firewall rules."
  value       = local.network_tag
}

output "service_account_email" {
  description = "Service account attached to the instance (created or pre-existing; empty when none)."
  value       = local.sa_email
}

output "static_ip" {
  description = "Reserved static external IP (empty when allocate_static_ip = false)."
  value       = var.allocate_static_ip ? google_compute_address.this[0].address : ""
}

# --- Bootstrap outputs (empty when bootstrap = false) ---

output "bootstrap_token_path" {
  description = "Local path where the admin bootstrap token was written. Empty when bootstrap = false."
  value       = var.bootstrap ? abspath(var.bootstrap_token_path) : ""
}

output "rune_login_command" {
  description = "Ready-to-paste `rune login` command. Empty when bootstrap = false."
  value       = var.bootstrap ? local.rune_login_command : ""
}
