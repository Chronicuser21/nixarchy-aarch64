# Grok Bot, an Electron app shipped as a .deb.
#
# Inlined rather than built through a shared helper: it is the only .deb app
# left here now that nixpkgs carries the ChatGPT desktop, and a factory with
# one product is just indirection.
{
  lib,
  stdenv,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libnotify,
  libsecret,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  udev,
  libGL,
  vulkan-loader,
  libX11,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libXScrnSaver,
  libxtst,
  libxcb,
  xdg-utils,
  libusb1,
  fetchurl,
}:
let
  version = "0.24.0";
  commit = "302d75da596fc8d11ee0446a19b31c33c6676c2c";
in
stdenv.mkDerivation {
  pname = "grok-bot";
  inherit version;

  src = fetchurl {
    url = "https://downloads.cursor.com/grokbot/stable/${commit}/linux/x64/Grok_Bot_${version}.deb";
    sha256 = "5fd091d63fa410717737797ae0b14967e4f1567cae201d10c834430e4807f32d";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libnotify
    libsecret
    libxkbcommon
    mesa
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libXScrnSaver
    libxtst
    libxcb
    libusb1
  ];

  # Loaded with dlopen at runtime, so autoPatchelf cannot see the need for
  # them from the ELF headers alone.
  runtimeDependencies = [
    udev
    libGL
    vulkan-loader
  ];

  # The Qt shims are dlopened only when the platform theme is Qt, and the
  # musl reference comes from a statically linked helper. Neither is needed on
  # a GTK desktop, and neither can be satisfied from nixpkgs' glibc world.
  autoPatchelfIgnoreMissingDeps = [
    "libc.musl-x86_64.so.1"
    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
    "libQt6Core.so.6"
    "libQt6Gui.so.6"
    "libQt6Widgets.so.6"
  ];

  unpackCmd = "dpkg-deb -x $curSrc source";
  sourceRoot = "source";
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share
    cp -r "opt/Grok Bot" "$out/share/grok-bot"
    cp -r usr/share/icons $out/share/ 2>/dev/null || true

    # chrome-sandbox wants setuid root, which a store path can never be. The
    # sandbox is provided by the kernel's user namespaces on NixOS instead, so
    # remove it rather than ship a binary that aborts on launch.
    rm -f "$out/share/grok-bot/chrome-sandbox"

    install -Dm444 usr/share/applications/grok-bot.desktop \
      $out/share/applications/grok-bot.desktop

    # Some ship an absolute /opt path in Exec (which does not exist here);
    # others already use a bare command name. Rewrite either to our wrapper.
    substituteInPlace $out/share/applications/grok-bot.desktop \
      --replace-quiet '"/opt/Grok Bot/grok-bot"' "grok-bot" \
      --replace-quiet '/opt/Grok Bot/grok-bot' "grok-bot"

    runHook postInstall
  '';

  # gappsWrapperArgs is filled in by wrapGAppsHook3; wrapping by hand here
  # would drop the GSettings and GDK_PIXBUF paths it sets up.
  postFixup = ''
    makeWrapper "$out/share/grok-bot/grok-bot" "$out/bin/grok-bot" \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"
  '';

  meta = {
    description = "Grok Bot desktop agent";
    homepage = "https://x.ai/bot";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    # Shipped as an x86-only .deb (see the header). On any other platform the
    # fork builds it fine -- dpkg-deb just unpacks it -- but the result is a
    # binary that cannot run. Fail loudly at nix build time rather than
    # installing one the desktop then cannot exec.
    broken = !stdenv.hostPlatform.isx86_64;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "grok-bot";
  };
}
