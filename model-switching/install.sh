#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_MODEL="${1:-35b}"

# 1. Make scripts executable
chmod +x "$ROOT/switch-model"

# 2. Point active.conf at the default model
ln -sfn "$ROOT/configs/$DEFAULT_MODEL.conf" "$ROOT/active.conf"

# 3. Install the user systemd unit
mkdir -p "$HOME/.config/systemd/user"
cp "$ROOT/llama-server.service" "$HOME/.config/systemd/user/llama-server.service"

# 4. Enable lingering so the service runs at boot without login (needs sudo, one-time)
if ! loginctl show-user "$USER" 2>/dev/null | grep -q 'Linger=yes'; then
    echo "Enabling lingering for $USER (one-time sudo)..."
    sudo loginctl enable-linger "$USER"
fi

# 5. Reload + enable + start
systemctl --user daemon-reload
systemctl --user enable llama-server
systemctl --user restart llama-server

echo
echo "Installed. Active model: $DEFAULT_MODEL"
echo "Tip: alias switch-model=$ROOT/switch-model"
