#!/usr/bin/env bash
# OpenWrt stable 25.12 currently ships Go 1.26, while the current PassWall
# Xray-core source declares Go >= 1.27. Overlay only the Go toolchain recipes
# from OpenWrt packages master and explicitly select Go 1.27. Keep the rest of
# the stable release feeds unchanged.
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
test -f "$TMP_DIR/lang/golang/golang-values.mk"
test -f "$TMP_DIR/lang/golang/golang-package.mk"

rm -rf "$FEED_DIR"
mkdir -p "$(dirname "$FEED_DIR")"
cp -a "$TMP_DIR/lang/golang" "$FEED_DIR"

# Do not rely on the default selected by whichever feed snapshot was fetched.
sed -i 's/^GO_DEFAULT_VERSION:=.*/GO_DEFAULT_VERSION:=1.27/' "$FEED_DIR/golang-values.mk"
grep -qx 'GO_DEFAULT_VERSION:=1.27' "$FEED_DIR/golang-values.mk"
test -f "$FEED_DIR/golang1.27/Makefile"

{
  echo "openwrt-packages-lang-golang $(git -C "$TMP_DIR" rev-parse HEAD)"
  echo "Go host toolchain selected: 1.27"
} >> "${GITHUB_WORKSPACE:-$ROOT}/upstream-commits.txt"

echo "Overlaid only packages/lang/golang from OpenWrt packages master."
echo "Verified GO_DEFAULT_VERSION=$(sed -n 's/^GO_DEFAULT_VERSION:=//p' "$FEED_DIR/golang-values.mk" | head -n1)"
