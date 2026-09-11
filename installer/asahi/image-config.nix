{
  config,
  fsType,
  inputs,
  lib,
  modulesPath,
  pkgs,
  version,
  ...
}:
let
  # Every locked input, transitively, as a store path.
  collectInputs =
    flake: [ flake.outPath ] ++ lib.concatMap collectInputs (lib.attrValues (flake.inputs or { }));
  inputSources = lib.unique (collectInputs inputs.self);

  # Generate /etc/nixos/flake.nix for the installed machine.
  # Declares every input the parent flake locks, so nixos-rebuild
  # switch works fully offline from the store.
  etcFlakeNix = pkgs.writeText "flake.nix" ''
    {
      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/${inputs.nixpkgs.rev}";
        apple-silicon = {
          url = "github:nix-community/nixos-apple-silicon/${inputs.apple-silicon.rev}";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        home-manager = {
          url = "github:nix-community/home-manager/${inputs.home-manager.rev}";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        hyprland.url = "github:hyprwm/Hyprland/${inputs.hyprland.rev}";
        disko = {
          url = "github:nix-community/disko/${inputs.disko.rev}";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        nixos-hardware = {
          url = "github:NixOS/nixos-hardware/${inputs.nixos-hardware.rev}";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        nix-flatpak.url = "github:gmodena/nix-flatpak/${inputs.nix-flatpak.rev}";
        sops-nix = {
          url = "github:Mic92/sops-nix/${inputs.sops-nix.rev}";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        omarchy = {
          url = "github:basecamp/omarchy/${inputs.omarchy.rev}";
          flake = false;
        };
        systems.url = "github:nix-systems/default-linux";
        zen-browser = {
          url = "github:0xc000022070/zen-browser-flake/${inputs.zen-browser.rev}";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        hypr-rdp = {
          url = "github:MuNeNiCK/hypr-rdp/${inputs.hypr-rdp.rev}";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        nixi = {
          url = "github:olafkfreund/nixi-nixarchy/${inputs.nixi.rev}";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        microvm = {
          url = "github:microvm-nix/microvm.nix/${inputs.microvm.rev}";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        nixarchy = {
          url = "github:Chronicuser21/nixarchy-aarch64/${inputs.self.shortRev or "dirty"}";
          inputs.nixpkgs.follows = "nixpkgs";
        };
      };
      outputs = { self, nixpkgs, nixarchy, home-manager, disko, ... }@inputs:
        let
          lib = nixpkgs.lib;
        in {
          nixosConfigurations.nixarchy = lib.nixosSystem {
            system = "aarch64-linux";
            specialArgs = {
              inputs = inputs // { self = nixarchy; };
            };
            modules = [
              nixarchy.nixosModules.nixarchy
              home-manager.nixosModules.home-manager
              disko.nixosModules.disko
              ./configuration.nix
            ];
          };
        };
    }
  '';

  etcConfig = pkgs.runCommand "etc-nixos" { } ''
    mkdir -p $out
    cp ${./template}/configuration.nix $out/configuration.nix
    cp ${etcFlakeNix} $out/flake.nix
    cp ${inputs.self}/flake.lock $out/flake.lock
    chmod -R u+w $out
  '';
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    inputs.apple-silicon.nixosModules.apple-silicon-support
  ];

  system = {
    # Every locked input, transitively, so a fully offline
    # nixos-rebuild switch works against /etc/nixos' flake.
    extraDependencies = inputSources;

    build.asahi-image = import ./make-disk-image.nix {
      copyConfig = etcConfig;
      memSize = 8192;
      inherit
        config
        fsType
        lib
        pkgs
        version
        ;
    };

    stateVersion = "25.05";
  };

  boot = {
    initrd.availableKernelModules = [
      "xhci_pci"
      "usb_storage"
      "usbhid"
    ];

    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = false;
  };

  boot.postBootCommands =
    let
      binPath = lib.makeBinPath (
        with pkgs;
        [
          asahi-fwextract
          btrfs-progs
          cpio
          e2fsprogs
          gawk
          parted
          util-linux
        ]
      );
    in
    ''
      PATH=${binPath}:$PATH

      if [[ -f /expand-on-first-boot ]]; then
        # Figure out device names for the boot device and root filesystem.
        rootPart=$(findmnt -nvo SOURCE /)
        rootFsType=$(lsblk -npo FSTYPE "$rootPart")
        firmwareDevice=$(lsblk -npo PKNAME $rootPart)
        partNum=$(lsblk -npo MAJ:MIN "$rootPart" | awk -F: '{print $2}' | tr -d '[:space:]')

        # Resize the root partition and the filesystem to fit the disk
        echo ',+,' | sfdisk -N"$partNum" --no-reread "$firmwareDevice"

        partprobe

        if [[ $rootFsType == "btrfs" ]]; then
          btrfs filesystem resize max /
        else
          resize2fs "$rootPart"
        fi

        rm -f /expand-on-first-boot
      fi

      echo Extracting Asahi firmware...
      mkdir -p /tmp/.fwsetup/{esp,extracted}

      mount /dev/disk/by-partuuid/`cat /proc/device-tree/chosen/asahi,efi-system-partition` /tmp/.fwsetup/esp
      asahi-fwextract /tmp/.fwsetup/esp/asahi /tmp/.fwsetup/extracted
      umount /tmp/.fwsetup/esp

      pushd /tmp/.fwsetup/
      cat /tmp/.fwsetup/extracted/firmware.cpio | cpio -id --quiet --no-absolute-filenames
      mkdir -p /lib/firmware
      mv vendorfw/* /lib/firmware
      popd
      rm -rf /tmp/.fwsetup
    '';

  fileSystems = {
    "/boot" = {
      device = "/dev/disk/by-uuid/12CE-A600";
      fsType = "vfat";
      options = [
        "fmask=0022"
        "dmask=0022"
      ];
    };
    "/" = {
      device = "/dev/disk/by-label/nixos";
      inherit fsType;
    }
    // lib.optionalAttrs (fsType == "btrfs") {
      options = [
        "compress=zstd"
        "subvol=@"
      ];
    };
  }
  // (lib.optionalAttrs (fsType == "btrfs") {
    "/home" = {
      device = "/dev/disk/by-label/nixos";
      inherit fsType;
      options = [
        "compress=zstd"
        "subvol=@home"
      ];
    };

    "/nix" = {
      device = "/dev/disk/by-label/nixos";
      inherit fsType;
      options = [
        "compress=zstd"
        "noatime"
        "subvol=@nix"
      ];
    };
  });

  hardware.asahi = {
    # Can't legally be included in the image: the Wi-Fi/webcam firmware lives
    # on the ESP the Asahi installer stages and is extracted on first boot.
    enable = true;
    extractPeripheralFirmware = false;
  };

  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  nix = {
    nixPath = [ "nixpkgs=flake:nixpkgs" ];
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      warn-dirty = false;
      tarball-ttl = 0;
      flake-registry = "";
    };
  };

  networking = {
    networkmanager.enable = true;
    networkmanager.wifi.backend = "iwd";
    wireless.iwd = {
      enable = true;
      settings = {
        General.EnableNetworkConfiguration = true;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    asahi-bless
    git
  ];

  programs.git.enable = true;

  services = {
    getty.autologinUser = "root";
    openssh.enable = true;
  };

  users.mutableUsers = true;

}
