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

variable "environment" {
  type    = string
  default = "edge"
}

variable "acme_email" {
  type        = string
  description = "Required: Let's Encrypt account email."
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to an SSH public key file (e.g. ~/.ssh/id_ed25519.pub)."
  # No default on purpose: a default path makes tflint/terraform
  # evaluate file() at lint time, which fails wherever the key does
  # not exist (CI). Pass -var or set TF_VAR_ssh_public_key_path.
}
