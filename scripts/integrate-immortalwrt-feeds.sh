#!/usr/bin/env bash
# Add the ImmortalWrt package and LuCI feeds as a non-destructive overlay.
# OpenWrt's own feeds remain enabled and are installed first. The feed tool is
# deliberately NOT invoked with -f: an ImmortalWrt package must never silently
# replace a core OpenWrt package or an already-installed official feed package.
set -Eeuo pipefail

ROOT="${1:?OpenWrt source directory required}"
cd "$ROOT"

if [ ! -f feeds.conf ] && [ -f feeds.conf.default ]; then
  cp feeds.conf.default feeds.conf
fi
touch feeds.conf

add_feed() {
  local name="$1" url="$2"
  if grep -Eq "^[[:space:]]*src-git[[:space:]]+$name[[:space:]]+" feeds.conf; then
    grep -Eq "^[[:space:]]*src-git[[:space:]]+$name[[:space:]]+$url([[:space:]]|$)" feeds.conf || {
      echo "Feed name $name already exists with a different URL; refusing to overwrite it." >&2
      exit 1
    }
  else
    printf 'src-git %s %s\n' "$name" "$url" >> feeds.conf
  fi
}

add_feed immortal_packages https://github.com/immortalwrt/packages.git
add_feed immortal_luci https://github.com/immortalwrt/luci.git

# Keep the upstream OpenWrt feeds intact; fetch only the two ImmortalWrt
# overlay feeds here, after the official feeds have been installed.
./scripts/feeds update immortal_packages immortal_luci

# Non-forced installation preserves the OpenWrt base and official package
# definitions wherever package names overlap. Unique ImmortalWrt packages
# become selectable in menuconfig and their dependencies are resolved by feeds.
./scripts/feeds install -a -p immortal_packages
./scripts/feeds install -a -p immortal_luci

for feed in immortal_packages immortal_luci; do
  test -s "feeds/$feed.index"
  git -C "feeds/$feed" rev-parse HEAD
  ./scripts/feeds list -r "$feed" | wc -l
done

{
  echo "immortal_packages $(git -C feeds/immortal_packages rev-parse HEAD)"
  echo "immortal_luci $(git -C feeds/immortal_luci rev-parse HEAD)"
} >> "${GITHUB_WORKSPACE:-$ROOT}/upstream-commits.txt"

echo "ImmortalWrt package and LuCI feeds integrated as non-forced overlays."
