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

# The package's image-build hook sources a router runtime library. During
# rootfs installation, IPKG_INSTROOT points at the staged target filesystem;
# on the running router it is empty and the normal absolute path is correct.
UTILS="$ROOT/package/alexwrt/passwall2/luci-app-passwall2/root/usr/share/passwall2/utils.sh"
if [ -f "$UTILS" ]; then
  python3 - "$UTILS" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = ". /lib/functions/network.sh"
new = """if [ -n "${IPKG_INSTROOT:-}" ]; then
\t[ -r "${IPKG_INSTROOT}/lib/functions/network.sh" ] && . "${IPKG_INSTROOT}/lib/functions/network.sh"
else
\t. /lib/functions/network.sh
fi"""
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("PassWall2 utils.sh network library source line changed; refusing an unsafe patch")
path.write_text(text)
PY
else
  echo "PassWall2 utils.sh not found at expected path: $UTILS" >&2
  exit 1
fi

# Build from source; never bypass APK/IPK repository signature verification.

