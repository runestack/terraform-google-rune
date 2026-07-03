# Edge node with automated bootstrap

```bash
gcloud auth application-default login
export TF_VAR_project="my-gcp-project"
export TF_VAR_acme_email="ops@example.com"
export TF_VAR_ssh_public_key_path="$HOME/.ssh/id_ed25519.pub"
export TF_VAR_ssh_private_key_path="$HOME/.ssh/id_ed25519"

terraform init
terraform apply
```

When apply finishes:

```bash
$(terraform output -raw rune_login_command)
rune whoami
```

The admin token sits at the path printed by
`terraform output -raw bootstrap_token_path` (mode 0600). Treat it like a
root password.

## Persistent Disks with no service-account key

`enable_pd_csi_access = true` grants the node's service account
`roles/compute.storageAdmin`, so the [`gce-pd` storage driver](https://docs.runestack.io/guides/persistent-storage/#using-gce-pd-for-google-persistent-disks)
provisions, attaches and snapshots Persistent Disks through the
instance's own credentials — nothing is stored in Terraform state or on
disk. After login, create a StorageClass (no `credentialsJSON` needed):

```yaml
storageClass:
  name: pd-balanced-euw2a
  driver: gce-pd
  parameters:
    zone: europe-west2-a
    diskType: pd-balanced
    fsType: ext4
```

The driver reads the project from the metadata server and authenticates
via Application Default Credentials.

## Re-bootstrap

If you need to rotate the admin token, taint and re-apply:

```bash
terraform apply -replace=module.rune.null_resource.bootstrap[0]
```
