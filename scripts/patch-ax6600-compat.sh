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

# Samba 4.24.5: fix the Heimdal poll header and replace deprecated
# krb5_free_unparsed_name() calls with the documented krb5_xfree().
mkdir -p "$PACKAGES/net/samba4/patches"
cat > "$PACKAGES/net/samba4/patches/100-musl-heimdal-compat.patch" <<'PATCH'
--- a/third_party/heimdal/lib/krb5/krb5_locl.h
+++ b/third_party/heimdal/lib/krb5/krb5_locl.h
@@ -44,7 +44,7 @@
 
 #ifdef HAVE_POLL_H
-#include <sys/poll.h>
+#include <poll.h>
 #endif
 
 #include <krb5-types.h>
--- a/lib/krb5_wrap/krb5_samba.c
+++ b/lib/krb5_wrap/krb5_samba.c
@@ -713,7 +713,7 @@
 	*_salt_principal_str
 		= talloc_strdup(mem_ctx, salt_principal_malloc);
-	krb5_free_unparsed_name(krb5_ctx, salt_principal_malloc);
+	krb5_xfree(salt_principal_malloc);
 
 	if (*_salt_principal_str == NULL) {
 		return ENOMEM;
@@ -919,10 +919,10 @@
 	}
 
 	if (!pull_utf8_talloc(mem_ctx, unix_name, utf8_name, &converted_size)) {
-		krb5_free_unparsed_name(context, utf8_name);
+		krb5_xfree(utf8_name);
 		return ENOMEM;
 	}
-	krb5_free_unparsed_name(context, utf8_name);
+	krb5_xfree(utf8_name);
 	return 0;
 }
--- a/auth/credentials/credentials_krb5.c
+++ b/auth/credentials/credentials_krb5.c
@@ -256,7 +256,7 @@
 	}
 
 	ok = cli_credentials_set_principal(cred, name, obtained);
-	krb5_free_unparsed_name(ccache->smb_krb5_context->krb5_context, name);
+	krb5_xfree(name);
 	if (!ok) {
 		krb5_free_principal(ccache->smb_krb5_context->krb5_context, princ);
 		return ENOMEM;
--- a/source3/client/smbspool.c
+++ b/source3/client/smbspool.c
@@ -649,7 +649,7 @@
 			fprintf(stderr,
 				"DEBUG: Try to authenticate as %s\n",
 				princ_name);
-			krb5_free_unparsed_name(ctx, princ_name);
+			krb5_xfree(princ_name);
 		}
 		krb5_free_principal(ctx, default_princ);
PATCH

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

echo "Applied AX6600 compatibility fixes: libtirpc, udns, Samba/Heimdal, and iptables poll headers; Samba Heimdal deprecation cleanup."
