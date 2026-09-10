# The disk layouts the installer offers. Imported by the installed system too,
# so a layout is declared once and is what `fileSystems` derives from -- epic
# invariant 1 applied to the disk: text in the user's flake, not a side effect
# of an install script.
#
# Three modes, one file, one btrfs layout. `mode` picks between them:
#
#   "whole"    the whole disk. `device` is the disk, disko owns the partition
#              table, and everything that was on it is gone.
#
#   "free"     installed into free space beside an existing OS (#47). There is
#              NO partition table here at all -- see the block below for why
#              that is the safety property and not an omission.
#
#   "existing" installed into a partition that already exists, beside an
#              operating system whose partition table must not move -- the
#              Apple Silicon dual-boot case (#453). `device` is the existing
#              Linux root partition (e.g. /dev/nvme0n1p5), `esp` the dedicated
#              ESP the firmware set up for this OS (e.g. /dev/nvme0n1p4).
#              Again there is NO partition table, and the ESP is adopted
#              without being reformatted -- see the block below.
{
  device,
  encrypt ? true,
  mode ? "whole",
  esp ? "/dev/disk/by-partlabel/nixarchy-esp",
}:
let
  # Omarchy's layout on Arch is @ @home @log and @pkg for pacman's cache.
  # @nix replaces @pkg: the store is the thing worth its own subvolume here,
  # and there is no package cache to keep.
  mountOptions = [
    "compress=zstd"
    "noatime"
  ];

  btrfs = {
    type = "btrfs";
    extraArgs = [ "-f" ];
    subvolumes = {
      "@" = {
        mountpoint = "/";
        inherit mountOptions;
      };
      "@home" = {
        mountpoint = "/home";
        inherit mountOptions;
      };
      "@nix" = {
        mountpoint = "/nix";
        inherit mountOptions;
      };
      "@log" = {
        mountpoint = "/var/log";
        inherit mountOptions;
      };

      # Where snapper keeps snapshots, and it has to exist before snapper can
      # take one: NixOS' snapper module does not create `.snapshots` itself
      # (nixpkgs#34595; the fix, PR #368449, is still unmerged), so a machine
      # without these subvolumes has a configured snapper that silently takes
      # nothing.
      #
      # Separate subvolumes rather than plain directories, which is also the
      # layout the ArchWiki recommends: a snapshot of `/` would otherwise
      # contain every previous snapshot of `/`, nested, growing each time.
      #
      # No compression: the contents are already-compressed extents shared
      # with the live subvolume, and snapshots cost nothing until the two
      # diverge. Setting compress here would be describing a copy that does
      # not happen.
      "@snapshots" = {
        mountpoint = "/.snapshots";
        mountOptions = [ "noatime" ];
      };
      "@home-snapshots" = {
        mountpoint = "/home/.snapshots";
        mountOptions = [ "noatime" ];
      };
    };
  };

  # LUKS, or not, around whatever content is handed in. Both modes ask the
  # same question and get the same answer, so the block is written once and
  # the two layouts differ only in what sits above it.
  luksOr =
    content:
    if encrypt then
      {
        type = "luks";
        name = "cryptroot";
        # Read once, by the disko script, at format time. The installer
        # writes it and removes it; the installed system never sees this
        # path -- its initrd prompts for the passphrase instead, and
        # nothing about this leaks into the closure. Never put it in the
        # generated flake directory: that becomes /etc/nixos and a git
        # repository.
        passwordFile = "/tmp/nixarchy-luks.key";
        # TRIM through LUKS. Upstream accepts the trade -- it makes the
        # free-space pattern visible on the device -- and so do we.
        settings.allowDiscards = true;
        inherit content;
      }
    else
      content;

  # ---------------------------------------------------------------------------
  # mode = "whole" -- the disk is ours, all of it.
  # ---------------------------------------------------------------------------
  whole = {
    disko.devices.disk.main = {
      inherit device;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          # /boot rather than /boot/efi: it is what boot.loader.systemd-boot
          # expects with no further options, and what Omarchy does with Limine.
          # 2G because a NixOS /boot holds every generation's kernel and initrd,
          # and the usual 512M runs out quietly, mid-rebuild.
          esp = {
            size = "2G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size = "100%";
            content = luksOr btrfs;
          };
        };
      };
    };
  };

  # ---------------------------------------------------------------------------
  # mode = "free" -- somebody else's OS is on this disk and stays on it.
  #
  # THIS DESCRIBES NO PARTITION TABLE, AND THAT IS THE POINT.
  #
  # The obvious way to write this is a `gpt` block with the existing
  # partitions declared alongside ours. It is also the way that destroys
  # data, and the reason is not obvious, so it is written down here:
  #
  #   disko's gpt type numbers partitions POSITIONALLY. lib/types/gpt.nix:244
  #   defaults `_index` to `diskoLib.indexOf ... sortedPartitions 0`, and
  #   indexOf counts from 1 (lib/default.nix:308, `iter 1 list`). The first
  #   partition disko declares is partition 1, always.
  #
  #   gpt's `_create` (gpt.nix:281) only clears a disk that blkid does not
  #   recognise, which sounds like the safe behaviour until the fallback at
  #   gpt.nix:315: when `sgdisk --new=1:...` fails because number 1 is in
  #   use, it retries WITHOUT --new -- `sgdisk --change-name=1 --typecode=1`
  #   on the partition that is already there. On a disk holding Windows,
  #   that relabels and retypes Windows' partition and reports success.
  #
  # `_index` is overridable -- `internal` hides an option from the docs, it
  # does not seal it -- so this is technically avoidable. It would still mean
  # a data-destroying operation depending on an undocumented internal that
  # disko may change without notice, so it is not done.
  #
  # Instead the partitions are cut by installer/install.sh with
  # `sgdisk --new=0:`, where 0 is sgdisk's own "next free partition number"
  # and a collision cannot arise, and this file describes the RESULT. Every
  # entry below is a disko `disk` whose device is one partition, addressed by
  # the partlabel install.sh gave it. disk._create is exactly its content's
  # _create (lib/types/disk.nix), and neither luks._create nor
  # filesystem._create touches anything but its own `device` -- so nothing in
  # this file can reach a partition the installer did not create. That is
  # disko's behaviour, relied on deliberately; the part enforced by our own
  # code is which partitions exist at all, and that is in install.sh.
  #
  # By-partlabel, not by-uuid: the labels are known before the partitions
  # exist, so this file can be written by the same template as the whole-disk
  # mode instead of being generated after the fact from whatever UUIDs came
  # out. The cost is that two nixarchy installs on one disk would collide on
  # the names; install.sh refuses to start a free-space install when either
  # label is already taken.
  #
  # And the thing somebody will otherwise assume: THIS FILE CANNOT REBUILD
  # YOUR PARTITION TABLE. It is not a whole-device description. Running
  # disko against it on a wiped disk produces nothing -- the partitions it
  # names would not exist. It keeps `fileSystems` and `boot.initrd.luks`
  # declarative, which is what invariant 1 asks of it, and that is all.
  #
  # `device` is unused here, deliberately. The installer still substitutes
  # the disk it partitioned into the template so the file records which disk
  # this machine came from; nothing addresses it.
  # ---------------------------------------------------------------------------
  free = {
    disko.devices.disk = {
      # Ours, cut fresh in the free space -- never the ESP that was already
      # on the disk. Upstream does not adopt an existing ESP either, even
      # when a Windows one is present and technically usable, and the reason
      # is this file: an adopted ESP is a partition we did not create, which
      # the paragraph above promises never to write to.
      #
      # 2G, for the same reason as the whole-disk mode: a NixOS /boot holds
      # every generation's kernel and initrd.
      esp = {
        type = "disk";
        device = "/dev/disk/by-partlabel/nixarchy-esp";
        content = {
          type = "filesystem";
          format = "vfat";
          mountpoint = "/boot";
          mountOptions = [ "umask=0077" ];
        };
      };

      root = {
        type = "disk";
        device = "/dev/disk/by-partlabel/nixarchy-root";
        content = luksOr btrfs;
      };
    };
  };

  # ---------------------------------------------------------------------------
  # mode = "existing" -- a partition somebody (or the Asahi installer) already
  # made, on a disk whose table must not move.
  #
  # This is the Apple Silicon dual boot: the Asahi installer leaves a
  # dedicated EFI system partition (EF00, "EFI - NIXOS") and a Linux root
  # partition (8300, typically /dev/nvme0n1p5) on the internal NVMe, between
  # the macOS containers. m1n1/U-Boot discovers THIS machine by that ESP, so
  # installing "beside" macOS means installing INTO those two partitions --
  # not cutting new ones, and not touching the partition table at all.
  #
  # Like `free`, this file therefore describes no partition table. disko sees
  # exactly one disk: the root partition already named, which is the only
  # partition this mode ever formats. Nothing else on the disk can be reached:
  # `whole`-mode's relabel-retry hazard (details in `free` above) cannot
  # happen because no `gpt` block exists to run it.
  #
  # The ESP is deliberately NOT given to disko, and that is a vendorfw
  # decision. The Asahi installer stores the peripheral firmware
  # (Wi-Fi, webcam, ...) in `vendorfw/` on that ESP, and the Apple Silicon
  # support module loads it from there by default (nixos-apple-silicon's
  # uefi-standalone guide). Formatting it would cost the hardware. So it is
  # adopted as-is: a plain `fileSystems` entry (disko never formats it), and
  # the installer mounts it at /mnt/boot before installing. What IS written
  # to it, by the bootloader at activation time, is the EFI/ directory
  # NixOS's own systemd-boot needs.
  #
  # `esp` defaults to the partlabel the free-space mode uses; existing-mode
  # installs always supply it explicitly (install.sh reads it from the
  # firmware's own asahi,efi-system-partition chosen node).
  existing = {
    disko.devices.disk.root = {
      inherit device;
      content = luksOr btrfs;
    };

    # Adopted, never formatted (see above). Kept out of `disko.devices` so
    # `whole`'s "a partition we did not create is never written to" promise
    # stays literally true here too.
    fileSystems."/boot" = {
      device = esp;
      fsType = "vfat";
      options = [ "umask=0077" ];
    };
  };
in
if mode == "whole" then
  whole
else if mode == "free" then
  free
else if mode == "existing" then
  existing
else
  throw "disk-config.nix: mode must be \"whole\", \"free\" or \"existing\", got: ${mode}"
