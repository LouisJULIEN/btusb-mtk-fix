#!/bin/bash
# Revert to the stock (broken) btusb.ko — use once Ubuntu ships a fixed kernel.
set -euo pipefail
KVER=${KVER:-$(uname -r)}
DEST=/lib/modules/$KVER/updates/btusb.ko.zst

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root (sudo ./uninstall.sh)"; exit 1; }

rm -fv "$DEST"
depmod -a "$KVER"
echo "btusb now resolves to: $(modinfo -n btusb)"
modprobe -r btusb 2>/dev/null || true
modprobe btusb
echo "reverted to stock module."
