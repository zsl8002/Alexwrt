#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${1:?OpenWrt source directory required}"
PACKAGES="$ROOT/feeds/packages"
BASE="$ROOT/package"

# Validate feed locations before making any change.
for dir in "$PACKAGES/libs/libtirpc" "$PACKAGES/libs/udns" "$PACKAGES/net/samba4"; do
  test -d "$dir" || {
    echo "Expected package directory missing: $dir" >&2
    exit 1
  }
done
test -f "$BASE/network/utils/iptables/Makefile" || {
  echo "Expected iptables package Makefile missing" >&2
  exit 1
}

# libtirpc 1.3.7: svc_run.c includes the obsolete sys/poll.h.
mkdir -p "$PACKAGES/libs/libtirpc/patches"
cat > "$PACKAGES/libs/libtirpc/patches/100-musl-poll-header.patch" <<'PATCH'
--- a/src/svc_run.c
+++ b/src/svc_run.c
@@ -40 +40 @@
-#include <sys/poll.h>
+#include <poll.h>
PATCH

# udns 0.7 has two obsolete includes: udns_resolver.c and ex-rdns.c.
# Apply the substitution after the normal source extraction/patch phase.
UDNS_MK="$PACKAGES/libs/udns/Makefile"
if ! grep -q 'AX6600 musl poll-header compatibility' "$UDNS_MK"; then
  cat >> "$UDNS_MK" <<'MAKE'

# AX6600 musl poll-header compatibility
define Build/Prepare
	$(call Build/Prepare/Default)
	@for f in $(PKG_BUILD_DIR)/udns_resolver.c $(PKG_BUILD_DIR)/ex-rdns.c; do \
		if [ -f "$$f" ]; then \
			sed -i 's@<sys/poll.h>@<poll.h>@g' "$$f"; \
		fi; \
	done
endef
MAKE
fi

# Samba 4.24.5: apply compatibility substitutions after source extraction.
# Use a post-prepare hook rather than a context-sensitive patch: Samba's
# vendored Heimdal header layout differs from older releases.
SAMBA_MK="$PACKAGES/net/samba4/Makefile"
if ! grep -q 'AX6600 musl poll-header and Heimdal deprecation compatibility' "$SAMBA_MK"; then
  cat >> "$SAMBA_MK" <<'MAKE'

# AX6600 musl poll-header and Heimdal deprecation compatibility
define Build/Prepare
	$(call Build/Prepare/Default)
	@set -e; \
	for f in \
		$(PKG_BUILD_DIR)/third_party/heimdal/lib/krb5/krb5_locl.h \
		$(PKG_BUILD_DIR)/lib/krb5_wrap/krb5_samba.c \
		$(PKG_BUILD_DIR)/auth/credentials/credentials_krb5.c \
		$(PKG_BUILD_DIR)/source3/client/smbspool.c; do \
		[ ! -f "$f" ] || sed -i \
			-e 's@<sys/poll.h>@<poll.h>@g' \
			-e 's@krb5_free_unparsed_name([^,]*, *\([^)]*\))@krb5_xfree(\1)@g' \
			"$f"; \
	done
endef
MAKE
fi

# iptables 1.8.10: nfnl_osf.c includes sys/poll.h directly.
IPTABLES_MK="$BASE/network/utils/iptables/Makefile"
if ! grep -q 'AX6600 musl poll-header compatibility' "$IPTABLES_MK"; then
  cat >> "$IPTABLES_MK" <<'MAKE'

# AX6600 musl poll-header compatibility
define Build/Prepare
	$(call Build/Prepare/Default)
	@if [ -f "$(PKG_BUILD_DIR)/utils/nfnl_osf.c" ]; then \
		sed -i 's@<sys/poll.h>@<poll.h>@g' "$(PKG_BUILD_DIR)/utils/nfnl_osf.c"; \
	fi
endef
MAKE
fi

# firewall4 2026-11-08 source mirror hash:
# The upstream source archive generated from this exact Git commit hashes to
# a95c6cfe...; an earlier recipe carried an incorrect 70cba... value.
# Correct only this known stale hash and fail closed for any other revision.
FW4_MK="$BASE/network/config/firewall4/Makefile"
FW4_VERSION="3722eadc088c3ab81389596ca9796112b436583a"
FW4_HASH_OLD="70cbaec533e7d635c00f5288a31a1d5d44cd43390d18c2df296e00079d1e4efe"
FW4_HASH_GOOD="a95c6cfe419c7d4e22bda5608aa6e46c67dadc9c7096879702d614cc498759d0"

if [ -f "$FW4_MK" ] && grep -q "PKG_SOURCE_VERSION:=$FW4_VERSION" "$FW4_MK"; then
  if grep -q "PKG_MIRROR_HASH:=$FW4_HASH_OLD" "$FW4_MK"; then
    sed -i "s/$FW4_HASH_OLD/$FW4_HASH_GOOD/" "$FW4_MK"
    echo "Corrected stale firewall4 mirror hash for $FW4_VERSION."
  elif ! grep -q "PKG_MIRROR_HASH:=$FW4_HASH_GOOD" "$FW4_MK"; then
    echo "Unexpected firewall4 mirror hash for pinned source $FW4_VERSION." >&2
    grep -E '^PKG_(SOURCE_DATE|SOURCE_VERSION|MIRROR_HASH):=' "$FW4_MK" >&2 || true
    exit 1
  fi

  # Remove any archive produced under the stale hash before the clean fetch.
  rm -f "$ROOT/dl/firewall4-2026.11.08~3722eadc.tar.zst"
  rm -rf "$ROOT/tmp/dl/firewall4-2026.11.08~3722eadc"
else
  echo "firewall4 source revision differs from the audited revision; no hash override applied."
fi

echo "Applied AX6600 compatibility fixes: libtirpc, udns, Samba/Heimdal, and iptables poll headers; Samba Heimdal deprecation cleanup."
