---
title: Dual boot install
---

# Dual boot install

The nixarchy installer offers three disk modes, the way Omarchy's does two:

- **Full disk install** — the disk is nixarchy's, and everything on it is gone.
- **Free space install** — nixarchy goes into the largest unpartitioned region
  on the disk, and every partition already there is left exactly as it was.
- **Apple Silicon dual boot** — on a Mac the Asahi installer already made the
  partitions; nixarchy installs into them, and macOS is left exactly as it was.

The mode screen only appears when it can. On a disk with no existing operating
system there is nothing to install beside, so the question is not asked at all.

## Apple Silicon (Macs)

The free-space path below is about Windows, and none of its preparation applies
to a Mac: the partitioning was already done by the
[Asahi Linux installer](https://asahilinux.org/install/), which set up a
dedicated EFI system partition and a Linux root partition on the internal NVMe
between the macOS containers. The Apple Silicon version of this installer
detects exactly that layout and offers *Apple Silicon dual boot*.

What it does:

1. Reads the partition the firmware itself records booting Linux from
   (`asahi,efi-system-partition` in the device tree) — it does not guess which
   ESP is "the" one by partition type.
2. Looks on that same disk for the single Linux partition the Asahi installer
   left (GPT type 8300, or 8309 once encrypted). More than one, or none, and
   the mode is not offered.
3. Formats **only that root partition** and installs into it. macOS, the
   partition table, and every partition that is not the root are untouched.

What it does not do:

**It does not reformat the ESP.** The Asahi installer stores the peripheral
firmware — Wi-Fi, webcam — in `vendorfw/` on the ESP, and loads it from there
every boot. Reformatting it would cost you the hardware, so nixarchy adopts it
as-is: the installer mounts it for the bootloader, and that is all.

**It does not touch the partition table.** The `disk-config.nix` it writes
describes no partition table and names only the two partitions the firmware
boots from — the same "disko never reaches a partition nixarchy did not
create" promise the free-space mode makes, at the cost that the file cannot
rebuild the disk. Running disko against it on a wiped disk produces nothing.

**It does not add macOS to the boot menu.** You hold the power button (or
Option at boot) to get firmware's chooser, the same way you boot the installer
— macOS's own boot entry is untouched.

### The two boots of the installer ISO

The ISO on Apple Silicon still boots through the m1n1/U-Boot the Asahi
installer put on the box. Two things to know from the nixos-hardware guide that
apply verbatim:

1. **`dd` the ISO to the whole device** — `/dev/diskX`, never a partition, and
   nothing but `dd`. When the label is wrong, the boot waits on
   `A start job is running for /dev/disk/by-label/NIXARCHY_*_AARCH64...`.
2. **If you are already waiting 30 seconds, replug the USB stick.** This is a
   known quirk of certain flash drives on this hardware, not an installer bug;
   the image force-loads the USB stack in its initrd up front to make the probe
   happen at boot rather than on demand, but a stick that genuinely drops off
   the bus still has to be replugged.

If USB boot will not cooperate at all, the installer's other road is the
phase-1 style command from any aarch64 Linux, which needs no boot medium:

```
nix run github:Chronicuser21/NixOmarchy-aarch64#install
```

## Before you start

**Shrink Windows from inside Windows.** Disk Management, *Shrink Volume*, and
leave at least 32 GiB unallocated — that is the floor the installer enforces,
and it is a floor rather than a recommendation: a desktop with a Nix store in
it is not comfortable below it. That half of
[the upstream page](https://omarchy.org/manual/dual-boot-install/) is about
Windows, not Omarchy, and applies unchanged here.

**Turn BitLocker off first.** The installer refuses a free-space install on a
disk BitLocker is holding, and the reason is worth knowing rather than working
around: nothing nixarchy does would touch the encrypted volume, but the install
adds an EFI boot entry and changes the boot order, and BitLocker measures the
boot chain. The next boot of Windows asks for a recovery key. If you have it,
you lost an afternoon. If you do not — and most people do not — the data is
gone as surely as if the disk had been formatted.

**Back up anyway.** This is a partitioning operation on a disk holding somebody
else's operating system. It is tested — `nix build .#checks.x86_64-linux.free-space`
installs onto a disk carrying a Windows-shaped ESP and data partition and
asserts both come out byte-identical — but a tested operation and a safe one
are different claims, and the second one is not available.

## What it does

1. Finds the largest unpartitioned region with `sgdisk`, and requires 32 GiB.
2. Cuts two partitions out of it with `sgdisk --new=0:`, where `0` is sgdisk's
   own *next free partition number* — so a new partition can never be given a
   number that is already in use.
3. Formats **only those two**, mounts them and installs, exactly as the
   whole-disk mode does.

nixarchy gets its own 2 GiB ESP. It does not adopt the ESP Windows is using,
even when there is one and it would technically work, which is also what
Omarchy does. An ESP nixarchy created is one it is allowed to write to; an ESP
somebody else created is not.

## What it does not do

**It does not add Windows to the boot menu.** Omarchy runs `limine-scan` for
this; nixarchy's bootloader is systemd-boot, which does not scan. Both
operating systems are installed and bootable, and you choose between them from
your firmware's boot menu (usually F12, F11 or Esc at power-on). Adding a
systemd-boot entry for Windows by hand is a few lines in your configuration and
is a NixOS question rather than a nixarchy one.

**It does not shrink anything.** The free space has to be free before you
start. The installer will not resize a partition, and that is deliberate: a
resize is the operation in this whole area most likely to lose data, and it has
a much better tool on the Windows side.

**It does not describe your partition table.** The `disk-config.nix` in the
flake it writes addresses two partitions by label — `nixarchy-esp` and
`nixarchy-root` — and declares no partition table at all. That is what keeps
disko from ever reaching a partition nixarchy did not create, and the cost is
that the file cannot rebuild your disk. Running disko against it on a wiped
disk produces nothing. The file says so at the top; read it before assuming
otherwise.
