#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG=/etc/teleport.yaml
DATA_DIR=/var/lib/teleport
BACKUP="$HOME/teleport.yaml"

if (( EUID == 0 )); then
  SUDO=()
else
  SUDO=(sudo)
fi

if [[ ! -f "$CONFIG" ]]; then
  printf 'Error: %s does not exist; nothing was changed.\n' "$CONFIG" >&2
  exit 1
fi

printf 'Host: %s\n' "$(hostname --fqdn 2>/dev/null || hostname)"
printf 'This will back up %s to %s, then remove Teleport and %s.\n' \
  "$CONFIG" "$BACKUP" "$DATA_DIR"

# Back up the configuration before making destructive changes.
"${SUDO[@]}" cp -- "$CONFIG" "$BACKUP"
if (( EUID != 0 )); then
  "${SUDO[@]}" chown "$(id -u):$(id -g)" "$BACKUP"
fi

if [[ ! -s "$BACKUP" ]]; then
  printf 'Error: backup %s is missing or empty; refusing to continue.\n' "$BACKUP" >&2
  exit 1
fi

echo 'Stopping the Teleport service...'
"${SUDO[@]}" systemctl stop teleport

# Match only processes whose executable name is exactly "teleport". Using
# `pkill -f teleport` could kill this script because its filename contains it.
echo 'Stopping any remaining Teleport daemon processes...'
"${SUDO[@]}" pkill -x teleport 2>/dev/null || true

echo 'Removing Teleport state and active configuration...'
"${SUDO[@]}" rm -rf -- "$DATA_DIR"
"${SUDO[@]}" rm -f -- "$CONFIG"

echo 'Removing the Teleport package...'
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get remove -y teleport

printf '\nComplete. Configuration backup: %s\n' "$BACKUP"
