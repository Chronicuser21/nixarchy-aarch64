#!/bin/sh
# SPDX-License-Identifier: MIT

# The macOS-side, no-USB installer for Apple Silicon: this is the Asahi
# bootstrap (copied from asahi-installer's scripts/bootstrap-prod.sh) pointed
# at the omarchy os package hosted in this repository's release assets.
#
# Run it from macOS:
#
#   sh <(curl -sL https://github.com/Chronicuser21/nixarchy-aarch64/releases/download/omarchy-asahi/install.sh)
#
# It installs the omarchy-asahi NixOS image the way the Asahi installer lays
# down any other distro: macOS is resized, the image is written to its own
# partitions, m1n1/U-Boot are staged, and the machine boots NixOS. It is NOT
# the interactive USB installer -- ask_disk_mode and the dual-boot questions
# never run here. See the README's Apple Silicon section for what you get.

# Truncation guard
if true; then
  set -e

  if [ ! -e /System ]; then
    echo "You appear to be running this script from Linux or another non-macOS system."
    echo "Asahi Linux can only be installed from macOS (or recoveryOS)."
    exit 1
  fi

  export LC_ALL=en_US.UTF-8
  export LANG=en_US.UTF-8
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

  # shellcheck disable=SC3020
  if ! curl --no-progress-meter file:/// &>/dev/null; then
    echo "Your version of cURL is too old. This usually means your macOS is very out"
    echo "of date. Installing Asahi Linux requires at least macOS version 13.5."
    exit 1
  fi

  export VERSION_FLAG=https://cdn.asahilinux.org/installer/latest
  export INSTALLER_BASE=https://cdn.asahilinux.org/installer
  export INSTALLER_DATA=https://github.com/Chronicuser21/nixarchy-aarch64/releases/download/omarchy-asahi/installer_data.json
  export REPO_BASE=https://github.com/Chronicuser21/nixarchy-aarch64/releases/download/omarchy-asahi

  TMP=/tmp/asahi-install

  echo
  echo "Bootstrapping installer:"

  if [ -e "$TMP" ]; then
    mv "$TMP" "$TMP-$(date +%Y%m%d-%H%M%S)"
  fi

  mkdir -p "$TMP"
  cd "$TMP"

  echo "  Checking version..."

  PKG_VER="$(curl --no-progress-meter -L "$VERSION_FLAG")"
  echo "  Version: $PKG_VER"

  PKG="installer-$PKG_VER.tar.gz"

  echo "  Downloading..."

  curl --no-progress-meter -L -o "$PKG" "$INSTALLER_BASE/$PKG"
  curl --no-progress-meter -L -O "$INSTALLER_DATA"

  echo "  Extracting..."

  tar xf "$PKG"

  echo "  Initializing..."
  echo

  if [ "$USER" != "root" ]; then
    echo "The installer needs to run as root."
    echo "Please enter your sudo password if prompted."
    exec caffeinate -dis sudo -E ./install.sh "$@"
  else
    exec caffeinate -dis ./install.sh "$@"
  fi
fi