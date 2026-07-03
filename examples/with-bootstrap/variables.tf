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
  type        = string
  description = "Path to an SSH public key file (e.g. ~/.ssh/id_ed25519.pub)."
  # No default on purpose: a default path makes tflint/terraform
  # evaluate file() at lint time, which fails wherever the key does
  # not exist (CI). Pass -var or set TF_VAR_ssh_public_key_path.
}

variable "ssh_private_key_path" {
  type        = string
  description = "Path to the PEM private key matching ssh_public_key_path, used for the in-module bootstrap SSH."
  # No default on purpose — see ssh_public_key_path.
}
