#!/usr/bin/env bash
# Replace generic placeholders (<user>, <server-ip>, <vm-ip>, <VM-IP>) throughout the repo
# with your actual values. Run once after cloning.
#
# Usage:
#   ./personalize.sh                              # interactive prompt
#   ./personalize.sh <user> <server-ip>           # non-interactive
#   USER_NAME=alice SERVER_IP=10.0.0.5 ./personalize.sh   # via env vars
#
# Idempotent-ish: re-running with the same values is a no-op. Re-running with
# different values won't undo prior replacements (since the placeholders are
# already gone), so commit before running if you want to revert easily.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

USER_NAME="${1:-${USER_NAME:-}}"
SERVER_IP="${2:-${SERVER_IP:-}}"

if [[ -z "$USER_NAME" ]]; then
    read -rp "Username on the server (e.g. alice): " USER_NAME
fi
if [[ -z "$SERVER_IP" ]]; then
    read -rp "Server IP or hostname (e.g. 192.168.1.50): " SERVER_IP
fi

[[ -n "$USER_NAME" && -n "$SERVER_IP" ]] || { echo "Both username and server IP are required." >&2; exit 1; }

# Files to scan — explicit list, so we never touch .git/.claude/binaries.
FILES=(
    "$ROOT/README.md"
    "$ROOT/common-commands.md"
    "$ROOT/docs/history.md"
    "$ROOT/model-switching/README.md"
    "$ROOT/scripts/claude-vm"
    "$ROOT/scripts/setup"
)

# Use perl for portable in-place edit (works on macOS and Linux).
for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || continue
    perl -i -pe "
        s/<user>/$USER_NAME/g;
        s/<server-ip>/$SERVER_IP/g;
        s/<vm-ip>/$SERVER_IP/g;
        s/<VM-IP>/$SERVER_IP/g;
    " "$f"
    echo "Personalized: ${f#$ROOT/}"
done

echo
echo "Done. user=$USER_NAME server=$SERVER_IP"
