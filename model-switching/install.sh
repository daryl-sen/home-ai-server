#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Make scripts executable
chmod +x "$ROOT/switch-model"

# 2. Install the user systemd unit (router mode — 27b auto-loads via preset)
mkdir -p "$HOME/.config/systemd/user"
cp "$ROOT/llama-server.service" "$HOME/.config/systemd/user/llama-server.service"

# 3. Enable lingering so the service runs at boot without login (needs sudo, one-time)
if ! loginctl show-user "$USER" 2>/dev/null | grep -q 'Linger=yes'; then
    echo "Enabling lingering for $USER (one-time sudo)..."
    sudo loginctl enable-linger "$USER"
fi

# 4. Reload + enable + start
systemctl --user daemon-reload
systemctl --user enable llama-server
systemctl --user restart llama-server

echo
echo "Installed. llama-server running in router mode (27b auto-loads at startup)."
echo "Switch: $ROOT/switch-model {27b|35b|status}"
echo "Tip: alias switch-model=$ROOT/switch-model"
