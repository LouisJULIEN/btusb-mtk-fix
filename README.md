# btusb-mtk-fix

Fix for a **Bluetooth regression in Ubuntu's `linux-image-6.8.0-139-generic`**
(Ubuntu 24.04 LTS, noble) that leaves MediaTek MT7925 / MT7921 controllers
completely dead with a kernel NULL pointer dereference at boot.

`6.8.0-138` is fine. `6.8.0-139` is not.

## Is this your problem?

**You ran a routine `apt update && apt upgrade`, rebooted, and now you cannot
turn Bluetooth on.**

Typically:

- Settings shows no Bluetooth adapter at all, or the toggle refuses to stay on
- Previously paired devices — headphones, mouse, keyboard — no longer connect
- `bluetoothctl` reports `No default controller available`
- Nothing you do in the GUI helps, and it worked perfectly before the update

Nothing is wrong with your adapter or your pairings. The kernel that came with
that update crashes while starting the MediaTek Bluetooth chip, so the adapter
never comes up for anything on the system to find.

If your machine has a MediaTek MT7925/MT7921 (very common on recent AMD boards
with MediaTek Wi-Fi) and you are on `6.8.0-139-generic`, this repo fixes it.
Check with:

```sh
uname -r                       # 6.8.0-139-generic?
lsusb | grep -i mediatek       # a MediaTek "Wireless_Device"?
```

**In a hurry?** Reboot and pick the previous kernel (`6.8.0-138-generic`) from
GRUB's *Advanced options* — Bluetooth works again immediately. The build below
is the fix that survives across reboots.

## Symptom (technical)

No Bluetooth adapter at all. `bluetoothctl list` is empty, `hciconfig -a`
shows `BD Address: 00:00:00:00:00:00` and `DOWN INIT`, and the kernel log
carries an oops during firmware setup:

```
BUG: kernel NULL pointer dereference, address: 0000000000000219
RIP: 0010:__pm_runtime_resume+0x1b/0x80
Call Trace:
 usb_autopm_get_interface+0x1d/0x60
 btmtk_usb_hci_wmt_sync+0xa9/0x2e0     [btmtk]
 btmtk_setup_firmware_79xx+0x1c7/0x360 [btmtk]
 btusb_mtk_setup+0x453/0x610           [btusb]
 hci_dev_setup_sync+0x6c/0x430         [bluetooth]
 hci_dev_open_sync+0xb1/0x350          [bluetooth]
 hci_power_on+0x50/0x210               [bluetooth]
```

The `hci0` kworker exits with irqs disabled, so setup never finishes.

Full logs for the broken, good and patched boots are in [`logs/`](logs/).

## Cause

The 6.8.0-139 backport of the upstream series *"Bluetooth: btmtk: move
`btusb_mtk_hci_wmt_sync` to btmtk.c"* moved the MediaTek WMT handshake out of
`btusb.c` and into `btmtk.c`. The moved code reads the USB interface, device
and control anchor out of the btmtk private area of `hci_dev`:

```c
usb_autopm_get_interface(data->intf);
```

but the hunk that *populates* those fields in `btusb_mtk_setup()` was not
carried across with it. `btusb_mtk_setup()` sets only `->dev_id` and
`->reset_sync`, so `->intf`, `->udev` and `->ctrl_anchor` stay NULL and the
first `usb_autopm_get_interface()` dereferences NULL.

Upstream is **not** affected — it has these assignments. This is a dropped
hunk in the Ubuntu backport only.

## The patch

[`0001-Bluetooth-btusb-mediatek-initialise-btmtk_data-USB-fields.patch`](0001-Bluetooth-btusb-mediatek-initialise-btmtk_data-USB-fields.patch)
restores the three missing lines, matching upstream `btusb_mtk_setup()`:

```c
 	mediatek = hci_get_priv(hdev);
 	mediatek->dev_id = dev_id;
 	mediatek->reset_sync = btusb_mtk_reset;
+	mediatek->intf = data->intf;
+	mediatek->udev = data->udev;
+	mediatek->ctrl_anchor = &data->ctrl_anchor;
```

## Usage

Build the single patched module out-of-tree and drop it in `updates/`, where
`depmod` prefers it over the distro module. The stock module is left untouched,
so `uninstall.sh` fully reverts you.

```sh
sudo apt-get install linux-headers-$(uname -r) linux-source-6.8.0 zstd
./build.sh
sudo ./install.sh
sudo reboot
```

After rebooting:

```sh
hciconfig -a | head -4     # real BD Address, UP RUNNING
bluetoothctl list          # a Controller line
```

To go back to the stock module once Ubuntu ships a fixed kernel:

```sh
sudo ./uninstall.sh
```

### One warning worth reading

Do **not** `modprobe -r btusb` on a boot where the oops has already fired.
`hci0` is left half-registered, `hci_unregister_dev` then hangs forever in
uninterruptible sleep, and `btusb` is wedged at refcount -1 until you reboot.
Install, then reboot — a clean boot loads the patched module directly.

## Status

**Not yet filed with Ubuntu.** [`LAUNCHPAD-BUG.md`](LAUNCHPAD-BUG.md) holds the
report ready to submit against the `linux` source package (noble); this section
will carry the bug link once it is filed.

Once `6.8.0-140` or later carries the fix, run `uninstall.sh` and drop this
workaround.

## Hardware this was reproduced on

| | |
|---|---|
| Adapter | MediaTek MT7925 — USB `0e8d:0616`, paired with `mt7921e` Wi-Fi |
| Board | MSI MAG X670E TOMAHAWK WIFI (MS-7E12), BIOS 1.80 |
| OS | Ubuntu 24.04.4 LTS |
| Broken | `6.8.0-139-generic` (`6.8.0-139.139`) |
| Last good | `6.8.0-138-generic` (`6.8.0-138.138`) |

Any MT7921/MT7922/MT7925 USB controller going through `btusb_mtk_setup()`
should hit this identically.
