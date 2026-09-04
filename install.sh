#!/bin/bash
# Install patched btusb.ko for the MT7925 NULL-deref regression in 6.8.0-139.
# Installs into /lib/modules/<kver>/updates/ which depmod prefers over kernel/,
# leaving the distro module untouched. Reverse with uninstall.sh.
set -euo pipefail
cd "$(dirname "$0")"

KVER=${KVER:-$(uname -r)}
SRC=build/btusb.ko
DEST_DIR=/lib/modules/$KVER/updates
DEST=$DEST_DIR/btusb.ko.zst

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root (sudo ./install.sh)"; exit 1; }
[ -f "$SRC" ] || { echo "ERROR: $SRC not found — run ./build.sh first"; exit 1; }

VM=$(modinfo -F vermagic "$SRC")
[ "${VM%% *}" = "$KVER" ] || { echo "ERROR: vermagic mismatch: '$VM' != '$KVER'"; exit 1; }
echo "vermagic OK: $VM"

mkdir -p "$DEST_DIR"
zstd -q -f -19 "$SRC" -o "$DEST"
chmod 0644 "$DEST"
echo "installed: $DEST"

depmod -a "$KVER"
echo "depmod resolves btusb -> $(modinfo -n btusb)"

cat <<'MSG'

================================================================
Module installed. A REBOOT is required.

Do NOT 'modprobe -r btusb' on a boot where the MT7925 oops has
already fired: hci0 is left half-initialised and hci_unregister_dev
hangs forever in D state (unkillable), wedging btusb at refcount -1.
A clean boot loads the patched module directly.
================================================================

Reboot, then verify with:
  hciconfig -a | head -4      # expect a real BD Address, UP RUNNING
  bluetoothctl list           # expect a Controller line
  journalctl -k -b 0 | grep -i 'bluetooth: hci0'
MSG
