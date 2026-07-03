# Minimal example

Provisions a single worker GCE instance in the default network with
default ports open to the public internet.

```bash
gcloud auth application-default login   # or set GOOGLE_APPLICATION_CREDENTIALS
export TF_VAR_project="my-gcp-project"
export TF_VAR_zone="europe-west2-a"
export TF_VAR_ssh_public_key_path="$HOME/.ssh/id_ed25519.pub"

terraform init
terraform apply
```

After apply, bootstrap manually (the module creates the `rune` login user):

```bash
ssh rune@$(terraform output -raw public_ip) 'sudo rune admin bootstrap --out-file /tmp/rune-admin.token; sudo chmod 644 /tmp/rune-admin.token'
scp rune@$(terraform output -raw public_ip):/tmp/rune-admin.token ./rune-admin.token
rune login dev --server $(terraform output -raw grpc_endpoint) --token-file ./rune-admin.token
```

For a fully automated bootstrap, see `../with-bootstrap/`.
