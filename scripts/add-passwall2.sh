#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${1:?OpenWrt source directory required}"
cd "$ROOT"

# Keep official feeds on the same stable series as the OpenWrt source tree.
# Mixing a stable buildroot with rolling master feeds can introduce Kconfig
# packages/dependencies that do not exist in the selected stable release.
OPENWRT_TAG="$(git describe --tags --exact-match 2>/dev/null || true)"
VERSION_NUMBER="${OPENWRT_TAG#v}"
if [[ ! "$VERSION_NUMBER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Unable to determine an exact OpenWrt release tag from the checked-out source: '$OPENWRT_TAG'" >&2
  exit 1
fi
FEED_BRANCH="openwrt-${VERSION_NUMBER%.*}"
declare -A FEED_URLS=(
  [packages]="https://git.openwrt.org/feed/packages.git"
  [luci]="https://git.openwrt.org/project/luci.git"
  [routing]="https://git.openwrt.org/feed/routing.git"
  [telephony]="https://git.openwrt.org/feed/telephony.git"
)
for feed in packages luci routing telephony; do
  url="${FEED_URLS[$feed]}"
  git ls-remote --exit-code --heads "$url" "refs/heads/$FEED_BRANCH" >/dev/null || {
    echo "Stable feed branch $FEED_BRANCH is unavailable for $feed ($url)" >&2
    exit 1
  }
  if ! grep -Eq "^src-git $feed [^;[:space:]]+;$FEED_BRANCH$" feeds.conf.default; then
    sed -i -E "s#^(src-git $feed [^;[:space:]]+)(;[^[:space:]]+)?$#\\1;$FEED_BRANCH#" feeds.conf.default
  fi
  grep -Eq "^src-git $feed [^;[:space:]]+;$FEED_BRANCH$" feeds.conf.default || {
    echo "Failed to pin $feed feed to $FEED_BRANCH" >&2
    exit 1
  }
done
echo "Pinned official feeds to $FEED_BRANCH for OpenWrt $VERSION_NUMBER."

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
  echo "openwrt-official-feeds $FEED_BRANCH"
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
