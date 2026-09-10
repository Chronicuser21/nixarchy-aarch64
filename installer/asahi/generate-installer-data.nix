{
  baseUrl,
  lib,
  partInfo,
  version,
}:
let
  nixpkgsVersion = lib.versions.majorMinor lib.version;
  pkgName = "omarchy-asahi-" + version + "-" + partInfo.fsType;
in
lib.generators.toJSON { } {
  name = "Omarchy ${nixpkgsVersion} (${pkgName})";
  default_os_name = "Omarchy";

  boot_object = "m1n1.bin";
  next_object = "m1n1/boot.bin";

  package = baseUrl + "/" + pkgName + ".zip";

  supported_fw = [
    "12.3"
    "12.3.1"
    "13.5"
  ];

  partitions = [
    {
      name = "EFI";
      type = "EFI";
      size = "${toString partInfo.espSize}B";
      format = "fat";
      volume_id = "0x12cea600";
      copy_firmware = true;
      copy_installer_data = true;
      source = "esp";
    }
    {
      name = "Root";
      type = "Linux";
      size = "${toString partInfo.rootSize}B";
      expand = true;
      image = "root.img";
    }
  ];
}
