#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${1:?OpenWrt source directory required}"
cd "$ROOT"

# Argon v3.1.4: pin the peeled upstream commit, not a moving branch/tag.
ARGON_REF="c5c0873e122dc767c7ab0198c8bffc6e952b5cfb"
DEST="package/alexwrt/luci-theme-argon"
mkdir -p package/alexwrt
if [ -e "$DEST" ]; then
  echo "Refusing to overwrite existing Argon source directory: $DEST" >&2
  exit 1
fi
git init "$DEST"
git -C "$DEST" remote add origin https://github.com/jerrykuku/luci-theme-argon.git
git -C "$DEST" fetch --depth 1 origin "$ARGON_REF"
git -C "$DEST" checkout --detach FETCH_HEAD
ACTUAL="$(git -C "$DEST" rev-parse HEAD)"
[ "$ACTUAL" = "$ARGON_REF" ] || { echo "Argon source pin mismatch: $ACTUAL != $ARGON_REF" >&2; exit 1; }
test -f "$DEST/Makefile"
grep -q '^PKG_VERSION:=3.1.4$' "$DEST/Makefile"

# Select Argon and its Chinese translation, plus Chinese catalogs for core LuCI
# pages and the bundled applications. PassWall2's own translation is mandatory.
# Enable the Simplified Chinese LuCI catalog so make defconfig retains generated i18n packages.
echo 'CONFIG_LUCI_LANG_zh_Hans=y' >> .config
for package in \
  luci-theme-argon \
  luci-i18n-base-zh-cn \
  luci-i18n-firewall-zh-cn \
  luci-i18n-package-manager-zh-cn \
  luci-i18n-attendedsysupgrade-zh-cn \
  luci-i18n-passwall2-zh-cn; do
  printf 'CONFIG_PACKAGE_%s=y\n' "$package" >> .config
done

# Install Chinese as the initial LuCI language and Argon as the default theme.
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-alexwrt-luci-defaults <<'EOF'
#!/bin/sh
uci -q set luci.main.lang='zh_cn'
uci -q set luci.main.mediaurlbase='/luci-static/argon'
uci -q commit luci
exit 0
EOF
chmod 0755 files/etc/uci-defaults/99-alexwrt-luci-defaults

{
  echo "luci-theme-argon $ARGON_REF"
  echo "argon-release v3.1.4"
} >> "$GITHUB_WORKSPACE/upstream-commits.txt"

echo "Argon v3.1.4 and required Chinese LuCI translations selected."
