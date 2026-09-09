# Apple Silicon (M1/M2/M3/M4) support for the installed machine.
#
# The aarch64 installer ISO (this fork's iso-net) boots an M1 through the
# m1n1 and U-Boot that the Asahi installer already put on the box -- but the
# machine the installer WRITES is a plain UEFI systemd-boot machine and
# cannot boot on Apple Silicon again without the m1n1/U-Boot round trip its
# own bootloader provides. This module adds exactly that plumbing.
#
# It is deliberately NOT imported by the installer's templates: the same
# installer serves every aarch64 host, and only Apple Silicon machines
# want it. Add it to the generated flake's hosts/<name>/ on one of these:
#
#   {
#     imports = [
#       nixarchy.nixosModules.appleSilicon
#     ];
#     hardware.asahi.enable = true;
#   }
inputs:
{
  lib,
  ...
}:
{
  imports = [
    inputs.apple-silicon.nixosModules.apple-silicon-support
  ];

  # Kernel, m1n1, U-Boot and Mesa wrap come from the module; opting in is the
  # only knob this fork adds (most machines will also want the ASAHI kernel's
  # GPU stack, which the module wires up behind this flag).
  hardware.asahi.enable = lib.mkDefault true;
}
