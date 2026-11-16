#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${1:?OpenWrt source directory required}"
cd "$ROOT"

# Keep PassWall repositories isolated from official feeds and pinned to the
# commits used by the last fully validated AX6600 release. Never build moving
# main/master heads implicitly.
: "${PASSWALL2_SOURCE_REF:?PASSWALL2_SOURCE_REF must be a reviewed 40-character commit}"
: "${PASSWALL_PACKAGES_SOURCE_REF:?PASSWALL_PACKAGES_SOURCE_REF must be a reviewed 40-character commit}"
for ref in "$PASSWALL2_SOURCE_REF" "$PASSWALL_PACKAGES_SOURCE_REF"; do
  [[ "$ref" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid pinned PassWall commit: $ref" >&2; exit 1; }
done
mkdir -p package/alexwrt
for spec in \
  "passwall2|https://github.com/Openwrt-Passwall/openwrt-passwall2.git|$PASSWALL2_SOURCE_REF" \
  "passwall-packages|https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git|$PASSWALL_PACKAGES_SOURCE_REF"; do
  IFS='|' read -r name url ref <<< "$spec"
  dest="package/alexwrt/$name"
  git init "$dest"
  git -C "$dest" remote add origin "$url"
  git -C "$dest" fetch --depth 1 origin "$ref"
  git -C "$dest" checkout --detach FETCH_HEAD
  actual="$(git -C "$dest" rev-parse HEAD)"
  [ "$actual" = "$ref" ] || { echo "Pinned $name commit mismatch: $actual != $ref" >&2; exit 1; }
done

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

