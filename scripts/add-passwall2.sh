#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${1:?OpenWrt source directory required}"
cd "$ROOT"

# OpenWrt release tags already pin official feeds to immutable commits in
# feeds.conf.default (URL^<40-char-commit>). Preserve those release-matched
# pins exactly. Appending a branch selector to a URL that already contains
# ^<commit> makes the feeds parser treat the commit as part of the URL.
OPENWRT_TAG="$(git describe --tags --exact-match 2>/dev/null || true)"
VERSION_NUMBER="${OPENWRT_TAG#v}"
if [[ ! "$VERSION_NUMBER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Unable to determine an exact OpenWrt release tag from the checked-out source: '$OPENWRT_TAG'" >&2
  exit 1
fi
for feed in packages luci routing telephony; do
  if ! awk -v feed="$feed" '
    $1 == "src-git" && $2 == feed {
      revision = $3
      sub(/^.*\^/, "", revision)
      if (revision ~ /^[0-9a-f]{40}$/) found = 1
    }
    END { if (!found) exit 1 }
  ' feeds.conf.default; then
    echo "OpenWrt release $OPENWRT_TAG does not contain an immutable commit pin for official feed '$feed'" >&2
    exit 1
  fi
done

# The release-pinned commits are mirrored on the official openwrt GitHub
# repositories. Use those mirrors because git.openwrt.org returned repository
# not found for these exact valid commits in the 2026-11-16 runner logs.
python3 - feeds.conf.default <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
mirrors = {
    "packages": ("https://git.openwrt.org/feed/packages.git", "https://github.com/openwrt/packages.git"),
    "luci": ("https://git.openwrt.org/project/luci.git", "https://github.com/openwrt/luci.git"),
    "routing": ("https://git.openwrt.org/feed/routing.git", "https://github.com/openwrt/routing.git"),
    "telephony": ("https://git.openwrt.org/feed/telephony.git", "https://github.com/openwrt/telephony.git"),
}
for feed, (old, new) in mirrors.items():
    pattern = re.compile(rf"^(src-git\\s+{re.escape(feed)}\\s+){re.escape(old)}(\\^[0-9a-f]{{40}})$", re.M)
    text, count = pattern.subn(rf"\\g<1>{new}\\g<2>", text)
    if count != 1:
        raise SystemExit(f"Expected exactly one immutable {feed} feed entry; found {count}")
path.write_text(text)
PY

echo "Rewrote only official feed transport URLs to GitHub mirrors; immutable release pins are unchanged."

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
  echo "openwrt-official-feeds $OPENWRT_TAG (release-pinned commits preserved)"
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
