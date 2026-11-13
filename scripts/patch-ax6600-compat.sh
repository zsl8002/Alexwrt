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



# AX6600: avoid userspace fallback for optional ath11k firmware-2.bin.
# ath11k treats firmware-2.bin as optional and falls back to amss.bin/API 1.
# Avoid sending a needless missing-file request through OpenWrt's userspace
# firmware fallback loader (which produces procd errors during normal boot).
ATH11K_PATCH_DIR="$ROOT/package/kernel/mac80211/patches/ath11k"
mkdir -p "$ATH11K_PATCH_DIR"
ATH11K_OPTIONAL_FW_PATCH="$ATH11K_PATCH_DIR/103-ath11k-optional-fw-no-userspace-fallback.patch"
if [ ! -f "$ATH11K_OPTIONAL_FW_PATCH" ]; then
  cat > "$ATH11K_OPTIONAL_FW_PATCH" <<'PATCH'
From: AlexWrt compatibility patch
Subject: [PATCH] ath11k: request optional firmware-2.bin without userspace fallback

The API-N firmware-2.bin file is optional. If it is absent, ath11k falls
back to API 1 (amss.bin). Use request_firmware_direct() so OpenWrt's
userspace firmware fallback does not log a false missing-firmware error.

--- a/drivers/net/wireless/ath/ath11k/fw.c
+++ b/drivers/net/wireless/ath/ath11k/fw.c
@@ -16,10 +16,14 @@ static int ath11k_fw_request_firmware_api_n(struct ath11k_base *ab,
 	struct ath11k_fw_ie *hdr;
 	const u8 *data;
 	__le32 *timestamp;
-
-	ab->fw.fw = ath11k_core_firmware_request(ab, name);
-	if (IS_ERR(ab->fw.fw)) {
-		ret = PTR_ERR(ab->fw.fw);
+	char path[100];
+
+	/* The file is optional: look for it on the filesystem only, so a
+	 * missing one does not go through the user-space fallback loader.
+	 */
+	ath11k_core_create_firmware_path(ab, name, path, sizeof(path));
+	ret = request_firmware_direct(&ab->fw.fw, path, ab->dev);
+	if (ret) {
 		ath11k_dbg(ab, ATH11K_DBG_BOOT, "failed to load %s: %d\n", name, ret);
 		ab->fw.fw = NULL;
 		return ret;
PATCH
fi

# AX6600: do not ship the fork's custom regulatory override.
# The upstream fork's 600 patch raises CN/US transmit power and removes
# DFS/NO-OUTDOOR restrictions. Restore the upstream wireless-regdb rules.
REGDB_OVERRIDE="$BASE/firmware/wireless-regdb/patches/600-custom-change-txpower-and-dfs.patch"
if [ -f "$REGDB_OVERRIDE" ]; then
  rm -f "$REGDB_OVERRIDE"
  echo "Removed non-compliant custom CN/US regulatory override; using upstream wireless-regdb limits."
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

# AX6600 QCN9074 regulatory diagnostics.
# KERNEL_DYNAMIC_DEBUG is selected through the OpenWrt top-level .config.
# These raw Linux Kconfig symbols are target-specific and are merged from
# target/linux/qualcommax/config-6.18 into the final kernel .config.
KERNEL_CONFIG_FRAGMENT="$ROOT/target/linux/qualcommax/config-6.18"
test -f "$KERNEL_CONFIG_FRAGMENT" || {
  echo "Expected kernel config fragment missing: $KERNEL_CONFIG_FRAGMENT" >&2
  exit 1
}
set_kernel_config() {
  local symbol="$1"
  local value="$2"
  if grep -q "^# ${symbol} is not set$" "$KERNEL_CONFIG_FRAGMENT"; then
    sed -i "s/^# ${symbol} is not set$/${symbol}=${value}/" "$KERNEL_CONFIG_FRAGMENT"
  elif grep -q "^${symbol}=" "$KERNEL_CONFIG_FRAGMENT"; then
    sed -i "s|^${symbol}=.*$|${symbol}=${value}|" "$KERNEL_CONFIG_FRAGMENT"
  else
    printf '%s=%s\n' "$symbol" "$value" >> "$KERNEL_CONFIG_FRAGMENT"
  fi
}
set_kernel_config CONFIG_ATH11K_DEBUG y
set_kernel_config CONFIG_IKCONFIG y
set_kernel_config CONFIG_IKCONFIG_PROC y

echo "Applied AX6600 compatibility fixes: libtirpc, udns, Samba/Heimdal, and iptables poll headers; Samba Heimdal deprecation cleanup."
