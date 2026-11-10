#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${1:?OpenWrt source directory required}"
cd "$ROOT"

# Keep the PassWall repositories isolated from the official feeds. Their
# packages are compiled from source as part of this firmware build.
git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall2.git package/alexwrt/passwall2
git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/alexwrt/passwall-packages

{
  echo "passwall2 $(git -C package/alexwrt/passwall2 rev-parse HEAD)"
  echo "passwall-packages $(git -C package/alexwrt/passwall-packages rev-parse HEAD)"
} >> "$GITHUB_WORKSPACE/upstream-commits.txt"

# Build from source; never bypass APK/IPK repository signature verification.
