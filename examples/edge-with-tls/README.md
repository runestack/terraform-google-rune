# Edge node with ACME-managed TLS

Single edge GCE instance that terminates :80/:443 and issues Let's
Encrypt certs for any service deployed with `expose.tls.mode = auto`.
A static external IP keeps the public address stable across stop/start.

## Apply

```bash
gcloud auth application-default login
export TF_VAR_project="my-gcp-project"
export TF_VAR_acme_email="ops@example.com"

terraform init
terraform apply
```

## DNS

Point your domain's A record at the output `public_ip` **before**
casting any service with `tls.mode = auto` — the HTTP-01 challenge needs
DNS to resolve back to this instance.

## Cast a service

```yaml
service:
  name: landing
  image: nginx:alpine
  ports: [{ name: http, port: 80 }]
  expose:
    host: example.com
    port: http
    tls:
      mode: auto
```

The first request to `https://example.com` triggers issuance (~5–15s);
renewals happen automatically 30 days before expiry.
