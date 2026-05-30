variable "project" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type    = string
  default = "europe-west2"
}

variable "zone" {
  type    = string
  default = "europe-west2-a"
}

variable "acme_email" {
  type = string
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  type        = string
  description = "Path to the PEM private key matching ssh_public_key_path, used for the in-module bootstrap SSH."
  default     = "~/.ssh/id_ed25519"
}
