# Submitting this fix to Ubuntu

Ubuntu's kernel does not take GitHub pull requests. A fix reaches a released
kernel through the **SRU** (Stable Release Update) process, in two steps that
must happen in this order:

1. **File a Launchpad bug.** Every Ubuntu kernel patch must carry a
   `BugLink:`, so the bug number has to exist before the patch is sent.
2. **Mail the patch to `kernel-team@lists.ubuntu.com`.** That list is Ubuntu's
   equivalent of a pull request: a kernel-team member ACKs it and applies it to
   the `noble` branch.

Everything you need for both steps is below.

---

## Step 1 — File the bug ✔

> **Filed:** [LP #2166509](https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2166509)
> — `linux (Ubuntu)`, New, with apport's hardware data attached.

Use `ubuntu-bug` rather than the Launchpad web form. It attaches `lspci`,
`lsusb`, `dmesg`, kernel version, BIOS data and package versions automatically,
and the kernel team will ask for exactly that data if it is missing.

```sh
ubuntu-bug linux
```

It opens a browser on a pre-filled bug. Set the title to:

```
btusb: NULL pointer dereference in btmtk_usb_hci_wmt_sync kills MT7925 Bluetooth in 6.8.0-139 (regression from 6.8.0-138)
```

Then replace the description with the block in [Step 2](#step-2--bug-description).

> **Run it from the working machine, on the affected kernel if you can.**
> Apport collects data from the running system. Filing from the patched kernel
> is fine — just say so — but filing from a machine that never had the bug is
> not.

### Attach

- `0001-Bluetooth-btusb-mediatek-initialise-btmtk_data-USB-fields.patch`
- `logs/oops-6.8.0-139-generic.txt`
- `logs/good-6.8.0-138-generic.txt`

### Then set

- **Tags:** `regression-update`, `noble`, `kernel-bug`
- **Affects:** `linux (Ubuntu)` — apport does this for you
- **Series:** nominate for **Noble**

Write down the bug number. Everything below needs it.

---

## Step 2 — Bug description ✔

Paste this verbatim, replacing nothing except where marked.

```
[Impact]

MediaTek MT7925/MT7921 USB Bluetooth controllers are completely non-functional
on linux-image-6.8.0-139-generic. The controller oopses during firmware setup,
the hci0 kworker exits with irqs disabled, and the adapter is left DOWN INIT
with BD_ADDR 00:00:00:00:00:00. bluetoothctl reports no controller at all, so
the machine has no usable Bluetooth: no pairing, and every previously paired
device stops working.

This is a regression introduced by 6.8.0-139.139. 6.8.0-138.138 is unaffected
on identical hardware.

MediaTek MT7925/MT7921 is the Bluetooth companion of the mt7921e Wi-Fi chip and
is very common on recent AMD desktop boards and laptops, so the affected
population is not small.

[Fix]

Two consecutive upstream commits from the same July 2024 MediaTek series, both
first released in v6.11:

  d019930b0049 ("Bluetooth: btmtk: move btusb_mtk_hci_wmt_sync to btmtk.c")
      Moves the WMT handshake into btmtk.c. struct btusb_data is out of scope
      there, so the moved code reads the USB interface, device and control
      anchor out of the btmtk private area of hci_dev instead:

          struct btmtk_data *data = hci_get_priv(hdev);
          ...
          err = usb_autopm_get_interface(data->intf);

  5c5e8c52e3ca ("Bluetooth: btmtk: move btusb_mtk_[setup, shutdown] to btmtk.c")
      Rewrites btusb_mtk_setup() to populate exactly those three fields before
      delegating to btmtk_usb_setup().

noble applied the first in 6.8.0-139.139, via LP: #2160250 ("Noble update:
upstream stable patchset 2026-07-09"), but not the second. The consumer landed
without its producer.

btusb_mtk_setup() in noble therefore still has its pre-6.11 shape and sets only
->dev_id and ->reset_sync, leaving ->intf, ->udev and ->ctrl_anchor NULL.
btmtk_usb_hci_wmt_sync() then calls usb_autopm_get_interface(NULL).

Upstream is not affected: v6.11 and later carry both commits, v6.10 and earlier
carry neither. Only a tree holding one without the other is broken.

Backporting 5c5e8c52e3ca in full is not appropriate here: it moves
btusb_mtk_setup()/btusb_mtk_shutdown() wholesale into btmtk.c and depends on the
rest of the 6.11 MediaTek restructuring (btmtk_usb_setup(), btmtk_usb_shutdown(),
the ISO data transmission series).

The attached patch instead seeds the three fields the moved WMT code requires,
which is what 5c5e8c52e3ca does for them upstream:

	mediatek = hci_get_priv(hdev);
	mediatek->dev_id = dev_id;
	mediatek->reset_sync = btusb_mtk_reset;
+	mediatek->intf = data->intf;
+	mediatek->udev = data->udev;
+	mediatek->ctrl_anchor = &data->ctrl_anchor;

[Test Case]

On an MT7925 USB adapter (0e8d:0616) running 6.8.0-139-generic, no Bluetooth
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

Booting 6.8.0-138-generic on the same machine: no oops, Bluetooth works.

With btusb.ko rebuilt from 6.8.0-139 sources plus the attached patch, the same
machine boots to:

  Bluetooth: hci0: HW/SW Version: 0x008a008a, Build Time: 20250523103438
  Bluetooth: hci0: Device setup in 159295 usecs
  Bluetooth: hci0: AOSP extensions version v1.00

  $ hciconfig -a | head -3
  hci0:   Type: Primary  Bus: USB
          BD Address: A8:3B:76:XX:XX:XX  ACL MTU: 1021:6  SCO MTU: 240:8
          UP RUNNING PSCAN

and audio devices pair and stream normally.

[Regression Potential]

Very low. Three assignments of already-available values, confined to the
MediaTek USB setup path, restoring parity with upstream btusb_mtk_setup().

Non-MediaTek controllers never execute this code. Without the assignments the
fields are NULL and every consumer of them oopses, so there is no existing
behaviour to preserve. Any risk would be confined to MediaTek USB Bluetooth,
which is currently 100% broken on this kernel.

[Other Info]

Broken:    linux-image-6.8.0-139-generic  6.8.0-139.139
Last good: linux-image-6.8.0-138-generic  6.8.0-138.138
Release:   Ubuntu 24.04.4 LTS (noble)

Adapter: MediaTek MT7925, USB 0e8d:0616 (companion to mt7921e Wi-Fi)
Board:   Micro-Star MSI MAG X670E TOMAHAWK WIFI (MS-7E12), BIOS 1.80 02/06/2024

Any MT7921/MT7922/MT7925 USB controller going through btusb_mtk_setup() should
reproduce this identically.

Patch, build scripts and full kernel logs for the broken, good and patched
boots: https://github.com/LouisJULIEN/btusb-mtk-fix
```

---

## Step 3 — Put the bug number in the patch

**Done.** The bug is [LP #2166509](https://bugs.launchpad.net/bugs/2166509) and
the patch already carries it:

```
BugLink: https://bugs.launchpad.net/bugs/2166509
```

A patch without a valid `BugLink:` is rejected, so if you ever regenerate the
patch, check it again:

```sh
head -5 0001-Bluetooth-btusb-mediatek-initialise-btmtk_data-USB-fields.patch
```

## Step 4 — Mail the patch

Send to **`kernel-team@lists.ubuntu.com`**. You do not need to subscribe to
post, but subscribing is how you see the replies:
https://lists.ubuntu.com/mailman/listinfo/kernel-team

The subject must carry the SRU tags so it is triaged correctly:

```
[SRU][noble][PATCH 1/1] Bluetooth: btusb: mediatek: initialise btmtk_data USB fields
```

### Recommended: git send-email

Mailing a patch through a GUI client usually mangles it — wrapped lines,
`format=flowed`, tabs turned into spaces — and a mangled patch does not apply.
`git send-email` sends it byte-exact.

```sh
sudo apt-get install git-email
```

Configure it once for your provider. The Laposte settings below are a starting
point — check them against your provider's own SMTP documentation, and note that
many providers now require an app-specific password rather than your account
password:

```sh
git config --global sendemail.smtpServer smtp.laposte.net
git config --global sendemail.smtpServerPort 587
git config --global sendemail.smtpEncryption tls
git config --global sendemail.smtpUser louis69600@laposte.net
```

Then send:

```sh
git send-email \
  --to kernel-team@lists.ubuntu.com \
  --subject-prefix "SRU][noble][PATCH" \
  0001-Bluetooth-btusb-mediatek-initialise-btmtk_data-USB-fields.patch
```

It prompts for your password and shows you the message before sending. Say
`n` if anything looks wrong.

### Fallback: Thunderbird

Only if `git send-email` is not an option.

1. Compose a **plain text** message — Thunderbird sends HTML by default, which
   will corrupt the patch. Hold **Shift** while clicking *Write*, or set
   *Account Settings → Composition & Addressing → Compose messages in HTML* off.
2. In `about:config`, set `mailnews.send_plaintext_flowed` to **false**.
3. Paste the entire patch file — headers, description, diff and the trailing
   `-- \n2.43.0` — as the message body. Do not attach it.
4. Send it to yourself first and check that `patch -p1 --dry-run` still accepts
   what arrives. If it does not, use `git send-email`.

---

## Step 5 — What happens next

- A kernel-team member replies **ACK** or asks for changes. Two ACKs are needed.
- Once applied you get a mail saying **"Applied to noble/master-next"**, and the
  bug moves to *Fix Committed*.
- The fix rides the next SRU cycle into `-proposed`, roughly three weeks.
- You will be asked to **verify**: enable `noble-proposed`, install the new
  kernel, confirm Bluetooth works, then replace the `verification-needed-noble`
  tag with `verification-done-noble`. **If nobody verifies, the fix is dropped**
  — so this last step matters.
- After that it is released to `noble-updates` and everyone gets it.

Until then, keep the module from this repo installed. Once the fixed kernel
lands, `sudo ./uninstall.sh`.

## If it goes quiet

The list is busy and patches do get missed. If there is no reply after about a
week, send a short follow-up **as a reply to your original mail**, keeping the
thread intact. Do not resend a fresh copy — that reads as a duplicate.
