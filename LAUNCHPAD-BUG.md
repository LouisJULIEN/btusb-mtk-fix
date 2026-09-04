# How to file this on Launchpad

Ubuntu kernel bugs want apport's hardware data attached, so **file it with
`ubuntu-bug`, then replace the description** with the text below.

```sh
ubuntu-bug linux
```

That opens a browser with a pre-filled bug carrying `lspci`, `lsusb`,
`dmesg`, kernel version and BIOS data. Set the title and paste the
description, then attach:

- `0001-Bluetooth-btusb-mediatek-initialise-btmtk_data-USB-fields.patch`
- `logs/oops-6.8.0-139-generic.txt`

Afterwards, tag the bug `regression-update` and `noble`, and put the bug
number into the patch's `BugLink:` line (currently `XXXXXXX`).

---

## Title

```
btusb: NULL pointer dereference in btmtk_usb_hci_wmt_sync kills MT7925 Bluetooth in 6.8.0-139 (regression from 6.8.0-138)
```

## Description

```
[Impact]

MediaTek MT7925/MT7921 USB Bluetooth controllers are completely non-functional
on linux-image-6.8.0-139-generic. The controller oopses during firmware setup,
the hci0 kworker exits with irqs disabled, and the adapter is left DOWN INIT
with BD_ADDR 00:00:00:00:00:00. bluetoothctl reports no controller at all, so
the machine has no usable Bluetooth.

This is a regression: 6.8.0-138.138 is unaffected on the identical hardware.

[Cause]

The 6.8.0-139 backport of the upstream series

  Bluetooth: btmtk: move btusb_mtk_hci_wmt_sync to btmtk.c

moved the MediaTek WMT handshake out of btusb.c and into btmtk.c. The moved
code reads the USB interface, device and control anchor out of the btmtk
private area of hci_dev (hci_get_priv), but the hunk that populates those
fields in btusb_mtk_setup() was not carried across with it.

btusb_mtk_setup() sets only ->dev_id and ->reset_sync, leaving ->intf, ->udev
and ->ctrl_anchor NULL. btmtk_usb_hci_wmt_sync() then calls
usb_autopm_get_interface(data->intf) on a NULL pointer.

Upstream is not affected -- it has these three assignments. This is a dropped
hunk in the Ubuntu backport only.

[Fix]

Restore the missing assignments in btusb_mtk_setup(), matching upstream:

	mediatek = hci_get_priv(hdev);
	mediatek->dev_id = dev_id;
	mediatek->reset_sync = btusb_mtk_reset;
+	mediatek->intf = data->intf;
+	mediatek->udev = data->udev;
+	mediatek->ctrl_anchor = &data->ctrl_anchor;

Patch attached (drivers/bluetooth/btusb.c, 3 insertions).

[Test Case]

On an MT7925 USB adapter (0e8d:0616) under 6.8.0-139-generic, no Bluetooth
adapter is usable: hci0 never leaves DOWN INIT, it carries no BD address, and
bluetoothctl lists no controller. The kernel log shows why, at boot:

  BUG: kernel NULL pointer dereference, address: 0000000000000219
  #PF: supervisor read access in kernel mode
  Oops: 0000 [#1] PREEMPT SMP NOPTI
  CPU: 6 PID: 225 Comm: kworker/u51:0 Tainted: P OE 6.8.0-139-generic #139-Ubuntu
  Workqueue: hci0 hci_power_on [bluetooth]
  RIP: 0010:__pm_runtime_resume+0x1b/0x80
  Call Trace:
   usb_autopm_get_interface+0x1d/0x60
   btmtk_usb_hci_wmt_sync+0xa9/0x2e0     [btmtk]
   btmtk_setup_firmware_79xx+0x1c7/0x360 [btmtk]
   btusb_mtk_setup+0x453/0x610           [btusb]
   hci_dev_setup_sync+0x6c/0x430         [bluetooth]
   hci_dev_init_sync+0x3e/0x1c0          [bluetooth]
   hci_dev_open_sync+0xb1/0x350          [bluetooth]
   hci_dev_do_open+0x28/0x70             [bluetooth]
   hci_power_on+0x50/0x210               [bluetooth]
   process_one_work+0x181/0x3a0
   worker_thread+0x18b/0x330
   kthread+0xef/0x120
  note: kworker/u51:0[225] exited with irqs disabled

With the patched btusb.ko loaded, the same machine boots to:

  Bluetooth: hci0: HW/SW Version: 0x008a008a, Build Time: 20250523103438
  Bluetooth: hci0: Device setup in 159295 usecs
  Bluetooth: hci0: AOSP extensions version v1.00

  $ hciconfig -a | head -3
  hci0:   Type: Primary  Bus: USB
          BD Address: A8:3B:76:XX:XX:XX  ACL MTU: 1021:6  SCO MTU: 240:8
          UP RUNNING PSCAN

and audio devices pair and stream normally.

[Regression Potential]

Very low. Three assignments of already-available values, in the MediaTek USB
setup path only, restoring parity with upstream btusb_mtk_setup(). Non-MediaTek
controllers do not execute this code. Without them the affected fields are NULL
and every consumer of them oopses, so there is no behaviour to preserve.

[Affected versions]

Broken:    linux-image-6.8.0-139-generic  6.8.0-139.139
Last good: linux-image-6.8.0-138-generic  6.8.0-138.138
Release:   Ubuntu 24.04.4 LTS (noble)

[Hardware]

Adapter: MediaTek MT7925, USB 0e8d:0616 (companion to mt7921e Wi-Fi)
Board:   Micro-Star MSI MAG X670E TOMAHAWK WIFI (MS-7E12), BIOS 1.80 02/06/2024

Any MT7921/MT7922/MT7925 USB controller going through btusb_mtk_setup() should
reproduce this identically.
```
