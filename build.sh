#!/bin/bash
# Build a patched btusb.ko out-of-tree against the running kernel.
# Reproduces build/ from scratch: kernel source -> patch -> module.
set -euo pipefail
cd "$(dirname "$0")"

KVER=${KVER:-$(uname -r)}
SRCVER=6.8.0
PATCH=0001-Bluetooth-btusb-mediatek-initialise-btmtk_data-USB-fields.patch

echo "==> target kernel: $KVER"

[ -d "/lib/modules/$KVER/build" ] || {
	echo "ERROR: no build tree for $KVER."
	echo "       sudo apt-get install linux-headers-$KVER"
	exit 1
}

# --- kernel source: only drivers/bluetooth is needed -----------------------
if [ ! -d "linux-source-$SRCVER/drivers/bluetooth" ]; then
	TARBALL=/usr/src/linux-source-$SRCVER.tar.bz2
	[ -f "$TARBALL" ] || {
		echo "ERROR: $TARBALL missing."
		echo "       sudo apt-get install linux-source-$SRCVER"
		exit 1
	}
	echo "==> extracting drivers/bluetooth from $TARBALL (slow, ~1 min)"
	tar -xjf "$TARBALL" "linux-source-$SRCVER/drivers/bluetooth"
fi

# --- stage sources ---------------------------------------------------------
echo "==> staging sources into build/"
mkdir -p build
cp "linux-source-$SRCVER/drivers/bluetooth/btusb.c" build/btusb.c
cp "linux-source-$SRCVER/drivers/bluetooth/"*.h     build/
cp build/btusb.c build/btusb.c.orig

cat > build/Makefile <<'MK'
obj-m := btusb.o

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
MK

# --- patch -----------------------------------------------------------------
echo "==> applying $PATCH"
patch -p3 -d build < "$PATCH"

# --- build -----------------------------------------------------------------
echo "==> building"
make -C "/lib/modules/$KVER/build" M="$PWD/build" modules

VM=$(modinfo -F vermagic build/btusb.ko)
[ "${VM%% *}" = "$KVER" ] || { echo "ERROR: vermagic mismatch: '$VM' != '$KVER'"; exit 1; }

echo
echo "built: build/btusb.ko  (vermagic: $VM)"
echo "next:  sudo ./install.sh   then reboot"
