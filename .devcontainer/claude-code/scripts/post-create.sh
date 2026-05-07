#!/bin/bash
# Post-create setup script for Claude Code devcontainer
set -euo pipefail

echo "=== Post-Create Setup Starting ==="

# Pin moby-containerd to the last known-good version.
# containerd 2.3.0's transfer.v1.local plugin pulls in the erofs differ, which
# requires `mkfs.erofs --tar`. Debian bookworm ships erofs-utils 1.5 (no --tar),
# so containerd fails to initialize and dockerd exits. Regression introduced by
# https://github.com/containerd/containerd/pull/13328. Remove this pin once
# https://github.com/containerd/containerd/issues/13346 is released.
CONTAINERD_PIN="2.2.3-debian12u1"
if dpkg-query -W -f='${Status}' moby-containerd 2>/dev/null | grep -q '^install ok installed'; then
    CURRENT_VERSION="$(dpkg-query -W -f='${Version}' moby-containerd)"
    if [ "$CURRENT_VERSION" != "$CONTAINERD_PIN" ]; then
        echo "Downgrading moby-containerd from $CURRENT_VERSION to $CONTAINERD_PIN"
        sudo apt-get update
        sudo apt-get install -y --allow-downgrades "moby-containerd=$CONTAINERD_PIN" \
            2> >(grep -vE 'System has not been booted with systemd|Failed to connect to bus|Host is down' >&2)
        sudo systemctl restart docker || true
    fi
    sudo apt-mark hold moby-containerd
fi

# Fix permissions for Docker volumes (Docker volumes are root-owned)
sudo chown -R node:node /commandhistory
touch /commandhistory/.zsh_history
touch /commandhistory/.bash_history

sudo chown -R node:node /home/node/.claude
chmod 700 /home/node/.claude

# Configure Claude statusline in user settings
CLAUDE_SETTINGS="/home/node/.claude/settings.json"
STATUSLINE_CONFIG='{"model":"opus[1m]","statusLine":{"type":"command","command":"/usr/local/bin/claude-statusline.sh","padding":0}}'
if [ -f "$CLAUDE_SETTINGS" ] && [ -s "$CLAUDE_SETTINGS" ]; then
    # Merge statusLine into existing settings
    tmp=$(jq --argjson sl "$STATUSLINE_CONFIG" '. * $sl' "$CLAUDE_SETTINGS")
    echo "$tmp" > "$CLAUDE_SETTINGS"
else
    echo "$STATUSLINE_CONFIG" | jq . > "$CLAUDE_SETTINGS"
fi
chmod 600 "$CLAUDE_SETTINGS"
echo "Claude statusline configured"

# Configure Terraform credentials for HCP Terraform
if [ -n "${TFE_TOKEN:-}" ]; then
    mkdir -p ~/.terraform.d
    cat > ~/.terraform.d/credentials.tfrc.json << EOF
{
  "credentials": {
    "app.terraform.io": {
      "token": "${TFE_TOKEN}"
    }
  }
}
EOF
    echo "Terraform credentials configured"
else
    echo "Skipping Terraform credentials (TFE_TOKEN not set)"
fi

# Setup internal CA certificates (skips cleanly if not on network)
CERT_NAME="${INTERNAL_CA_CERT_NAME:-internal-ca-chain}"
CERT_PATH="/usr/local/share/ca-certificates/${CERT_NAME}.crt"

SCRIPT_DIR="$(dirname "$0")"
"${SCRIPT_DIR}/../../scripts/setup-internal-certs.sh"

# If certs were installed, configure Node.js and OTEL to trust them
if [ -f "$CERT_PATH" ]; then
    {
        echo ""
        echo "# Internal CA certs (added by post-create.sh)"
        echo "export NODE_EXTRA_CA_CERTS=\"$CERT_PATH\""
        echo "export OTEL_EXPORTER_OTLP_CERTIFICATE=\"$CERT_PATH\""
    } >> /home/node/.zshrc
    echo "NODE_EXTRA_CA_CERTS and OTEL_EXPORTER_OTLP_CERTIFICATE set in shell profile"
fi

echo "=== Post-Create Setup Complete ==="
