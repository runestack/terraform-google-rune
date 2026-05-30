variable "project" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region for the provider (the zone's region)."
  default     = "europe-west2"
}

variable "zone" {
  type        = string
  description = "GCE zone for the instance."
  default     = "europe-west2-a"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to an SSH public key file (e.g. ~/.ssh/id_ed25519.pub)."
  default     = "~/.ssh/id_ed25519.pub"
}
