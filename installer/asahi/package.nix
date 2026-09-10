# Turn the whole-disk .raw into the os package the Asahi installer consumes:
# installer_data.json describing the layout, plus a zip of the ESP contents
# and the compressed root partition image. Adapted from
# quinneden/nixos-asahi-package/package.nix (MIT).
{
  baseUrl,
  image,
  lib,
  pkgs,
  stdenv,
  version,
  ...
}:

let
  generateInstallerData = import ./generate-installer-data.nix { inherit lib; };
  partInfo = import (image + "/partinfo.nix");

  installerData = generateInstallerData {
    inherit baseUrl partInfo version;
  };
in

stdenv.mkDerivation (finalAttrs: {
  pname = "omarchy-asahi";
  version = version + "-${partInfo.fsType}";

  src = image;

  nativeBuildInputs = with pkgs; [
    coreutils
    gawk
    jq
    p7zip
    util-linux
  ];

  buildPhase = ''
    runHook preBuild

    diskImage="${image.name}.img"
    installerData="installer_data-${finalAttrs.version}.json"
    pkgZip="${finalAttrs.pname}-${finalAttrs.version}.zip"

    eval "$(
      fdisk -Lnever -lu -b 512 "$diskImage" |
      awk "/^$diskImage/ { printf \"dd if=$diskImage of=%s skip=%s count=%s bs=512\\n\", \$1, \$2, \$4 }"
    )"

    mkdir -p package/esp

    7z x -o"package/esp" "''${diskImage}1"
    mv "''${diskImage}2" package/root.img

    pushd package/ > /dev/null

    rm -rf esp/EFI/nixos/.extra-files

    echo -n 'creating compressed archive:'
    7z a -tzip -r -mx1 -bso0 ../"$pkgZip" ./.

    popd > /dev/null

    jq -r <<< ${lib.escapeShellArg installerData} > "$installerData"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out $pkgZip $installerData
    runHook postInstall
  '';

  meta = {
    homepage = "https://github.com/Chronicuser21/NixOmarchy-aarch64";
    platforms = [ "aarch64-linux" ];
    licence = lib.licenses.mit;
  };
})
