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
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}
