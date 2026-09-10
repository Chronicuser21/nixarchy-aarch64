# The omarchy "ALARM-style" Apple Silicon installer: a whole-disk NixOS image
# installable from macOS with the single command in install.sh, no USB.
#
# Pipeline (ported from quinneden/nixos-asahi-package, see each file's header):
#
#   image-config.nix          -- the NixOS system the image carries
#   make-disk-image.nix       -- builds the GPT disk image (ESP + root) in qemu
#   package.nix               -- splits it into the Asahi os package:
#                                installer_data.json + esp + root.img + zip
#   install.sh                -- the macOS bootstrap one-liner
#
# The Asahi installer then lays the package down exactly as it would Fedora:
# macOS keeps its disk up to 1.5 TB budget, the image gets its own partitions,
# m1n1 + U-Boot are staged, and the machine boots NixOS. It is image-based by
# design -- there are no ask_disk_mode questions on this path.
{
  inputs,
  nixpkgs,
  version,
  ...
}:
let
  inherit (nixpkgs) lib;
  # The pkgs the build runs on: stock aarch64-linux, not the omarchy overlay,
  # so the disk-image tooling (vmTools, lkl, closureInfo) matches the exact
  # shapes upstream exercises with this pipeline.
  pkgs = import nixpkgs { system = "aarch64-linux"; };
  system = "aarch64-linux";

  mkNixosConfig =
    fsType:
    lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit
          inputs
          version
          ;
        inherit fsType;
        modulesPath = nixpkgs + "/nixos/modules";
      };
      modules = [ ./image-config.nix ];
    };

  mkInstallerPkg =
    fsType:
    let
      image = (mkNixosConfig fsType).config.system.build.asahi-image;
    in
    pkgs.callPackage ./package.nix {
      inherit
        image
        lib
        version
        ;
      baseUrl = "https://github.com/Chronicuser21/nixarchy-aarch64/releases/download/omarchy-asahi";
    };
in
{
  image = (mkNixosConfig "btrfs").config.system.build.asahi-image;
  installer = mkInstallerPkg "btrfs";
}
