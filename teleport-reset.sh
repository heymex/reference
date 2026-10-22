#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG=/etc/teleport.yaml
DATA_DIR=/var/lib/teleport
BACKUP="$HOME/teleport.yaml"

if [[ ! -f "$CONFIG" ]]; then
  printf 'Error: %s does not exist; nothing was changed.\n' "$CONFIG" >&2
  exit 1
fi

printf 'Host: %s\n' "$(hostname --fqdn 2>/dev/null || hostname)"
printf 'This will back up %s to %s, then remove Teleport and %s.\n' \
  "$CONFIG" "$BACKUP" "$DATA_DIR"
read -r -p 'Type RESET to continue: ' confirmation

if [[ "$confirmation" != RESET ]]; then
  echo 'Aborted; nothing was changed.'
  exit 1
fi

# Back up the configuration before making destructive changes.
sudo cp -- "$CONFIG" "$BACKUP"
sudo chown "$(id -u):$(id -g)" "$BACKUP"

if [[ ! -s "$BACKUP" ]]; then
  printf 'Error: backup %s is missing or empty; refusing to continue.\n' "$BACKUP" >&2
  exit 1
fi

echo 'Stopping the Teleport service...'
sudo systemctl stop teleport

# Match only processes whose executable name is exactly "teleport". Using
# `pkill -f teleport` could kill this script because its filename contains it.
echo 'Stopping any remaining Teleport daemon processes...'
sudo pkill -x teleport 2>/dev/null || true

echo 'Removing Teleport state and active configuration...'
sudo rm -rf -- "$DATA_DIR"
sudo rm -f -- "$CONFIG"

echo 'Removing the Teleport package...'
sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y teleport

printf '\nComplete. Configuration backup: %s\n' "$BACKUP"
