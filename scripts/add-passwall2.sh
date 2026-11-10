#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${1:?OpenWrt source directory required}"
cd "$ROOT"

git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall2.git package/alexwrt/passwall2
git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/alexwrt/passwall-packages

# OpenWrt 25.12 currently builds with Go 1.26.x. The PassWall packages
# repository's newest Xray-core may require Go 1.27, so pin a compatible
# upstream Xray release for this build line only. Keep the upstream source
# URL and its published SHA256; do not disable source verification.
if [ -n "${ALEXWRT_XRAY_COMPAT:-}" ]; then
  case "$ALEXWRT_XRAY_COMPAT" in
    26.7.11)
      sed -i \
        -e 's/^PKG_VERSION:=.*/PKG_VERSION:=26.7.11/' \
        -e 's/^PKG_HASH:=.*/PKG_HASH:=7c191254c0d8cc8be7673904739fc7329b601947da5377ef85900a0cd0a85e23/' \
        package/alexwrt/passwall-packages/xray-core/Makefile
      ;;
    *)
      echo "Unsupported Xray compatibility pin: $ALEXWRT_XRAY_COMPAT" >&2
      exit 1
      ;;
  esac
  echo "Pinned Xray-core to $ALEXWRT_XRAY_COMPAT for the selected Go toolchain."
fi

{
  echo "passwall2 $(git -C package/alexwrt/passwall2 rev-parse HEAD)"
  echo "passwall-packages $(git -C package/alexwrt/passwall-packages rev-parse HEAD)"
  if [ -n "${ALEXWRT_XRAY_COMPAT:-}" ]; then
    echo "xray-core compatibility pin $ALEXWRT_XRAY_COMPAT (upstream package hash verified)"
  fi
} >> "$GITHUB_WORKSPACE/upstream-commits.txt"

# Build from source; never bypass APK/IPK repository signature verification.
