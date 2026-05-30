# ---------------------------------------------------------------
# Optional bootstrap step.
#
# When var.bootstrap = true, this file:
#   1. Waits for the instance's gRPC port to accept TCP connections
#      (proxy for "cloud-init finished + runed up").
#   2. SSHes in and runs `rune admin bootstrap` to mint a one-time
#      root admin token.
#   3. Pulls the token to the operator's machine via `scp`.
#   4. Emits a `rune login` command as an output for one-paste use.
#
# Implementation mirrors terraform-aws-rune; see that module's
# bootstrap.tf for the design rationale.
# ---------------------------------------------------------------

locals {
  bootstrap_context = var.bootstrap_context_name != "" ? var.bootstrap_context_name : local.name

  rune_login_command = format(
    "rune login %s --server %s:%d --token-file %s --default-namespace %s",
    local.bootstrap_context,
    local.public_ip,
    var.grpc_port,
    abspath(var.bootstrap_token_path),
    var.bootstrap_namespace,
  )
}

resource "null_resource" "bootstrap" {
  count = var.bootstrap ? 1 : 0

  triggers = {
    instance_id = google_compute_instance.this.instance_id
    token_path  = var.bootstrap_token_path
  }

  lifecycle {
    precondition {
      condition     = var.bootstrap_ssh_private_key != ""
      error_message = "bootstrap = true requires bootstrap_ssh_private_key to be set."
    }
    precondition {
      condition     = local.public_ip != ""
      error_message = "bootstrap = true requires a reachable public IP. Set assign_public_ip = true (default) or allocate_static_ip = true."
    }
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-eu", "-o", "pipefail", "-c"]
    environment = {
      INSTANCE_IP      = local.public_ip
      SSH_USER         = local.bootstrap_ssh_user
      SSH_KEY_CONTENT  = var.bootstrap_ssh_private_key
      GRPC_PORT        = tostring(var.grpc_port)
      TOKEN_LOCAL_PATH = var.bootstrap_token_path
      WAIT_TIMEOUT     = var.bootstrap_wait_timeout
    }
    command = <<-BOOTSTRAP
      tmpkey=$(mktemp)
      trap 'rm -f "$tmpkey"' EXIT
      printf '%s\n' "$SSH_KEY_CONTENT" > "$tmpkey"
      chmod 600 "$tmpkey"

      ssh_opts=(
        -i "$tmpkey"
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o LogLevel=ERROR
        -o ConnectTimeout=10
      )

      # 1) wait until SSH responds
      deadline=$(( $(date +%s) + $(echo "$WAIT_TIMEOUT" | sed -E 's/m$/*60/;s/s$//' | bc) ))
      while ! ssh "$${ssh_opts[@]}" "$SSH_USER@$INSTANCE_IP" 'true' 2>/dev/null; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
          echo "timed out waiting for SSH on $INSTANCE_IP" >&2
          exit 1
        fi
        sleep 5
      done

      # 2) wait for runed gRPC port via remote /dev/tcp
      while ! ssh "$${ssh_opts[@]}" "$SSH_USER@$INSTANCE_IP" "</dev/tcp/127.0.0.1/$GRPC_PORT" 2>/dev/null; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
          echo "timed out waiting for runed gRPC on :$GRPC_PORT" >&2
          exit 1
        fi
        sleep 5
      done

      # 3) bootstrap (idempotent: fails fast if already bootstrapped,
      #    in which case the operator should run with bootstrap=false)
      ssh "$${ssh_opts[@]}" "$SSH_USER@$INSTANCE_IP" \
        'sudo rune admin bootstrap --out-file /tmp/rune-admin.token && sudo chmod 644 /tmp/rune-admin.token'

      # 4) copy token down + lock it down
      mkdir -p "$(dirname "$TOKEN_LOCAL_PATH")"
      scp "$${ssh_opts[@]}" "$SSH_USER@$INSTANCE_IP:/tmp/rune-admin.token" "$TOKEN_LOCAL_PATH"
      chmod 600 "$TOKEN_LOCAL_PATH"

      # 5) wipe the remote copy
      ssh "$${ssh_opts[@]}" "$SSH_USER@$INSTANCE_IP" 'sudo shred -u /tmp/rune-admin.token || sudo rm -f /tmp/rune-admin.token'

      echo "bootstrap complete: $TOKEN_LOCAL_PATH"
    BOOTSTRAP
  }

  depends_on = [google_compute_instance.this, google_compute_address.this]
}
