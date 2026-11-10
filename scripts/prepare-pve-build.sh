#!/usr/bin/env bash
# Keep the OpenWrt release's normal feeds, but use the matching current Go
# toolchain recipes because the current PassWall Xray-core source requires Go 1.27.
set -Eeuo pipefail

ROOT="${1:?OpenWrt source directory required}"
FEED_DIR="$ROOT/feeds/packages/lang/golang"
TMP_DIR="${RUNNER_TEMP:-/tmp}/alexwrt-openwrt-packages-go"

test -d "$ROOT/feeds/packages"
rm -rf "$TMP_DIR"
git clone --depth 1 --filter=blob:none --sparse --branch master \
  https://github.com/openwrt/packages.git "$TMP_DIR"
git -C "$TMP_DIR" sparse-checkout set lang/golang
test -f "$TMP_DIR/lang/golang/golang1.27/Makefile"
test -f "$TMP_DIR/lang/golang/golang-package.mk"

rm -rf "$FEED_DIR"
mkdir -p "$(dirname "$FEED_DIR")"
cp -a "$TMP_DIR/lang/golang" "$FEED_DIR"

{
  echo "openwrt-packages-lang-golang $(git -C "$TMP_DIR" rev-parse HEAD)"
} >> "${GITHUB_WORKSPACE:-$ROOT}/upstream-commits.txt"

echo "Overlaid only packages/lang/golang from OpenWrt packages master."
echo "Go toolchain default: $(sed -n 's/^GO_DEFAULT_VERSION:=//p' "$FEED_DIR/golang-values.mk" | head -n1)"
