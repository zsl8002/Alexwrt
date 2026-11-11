#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${1:?OpenWrt source directory required}"
PACKAGES="$ROOT/feeds/packages"

# musl intentionally provides a compatibility shim for the obsolete
# <sys/poll.h> include and emits a warning when packages still use it.
# Patch only the two source files confirmed by the AX6600 build log.
for package in libtirpc udns; do
  test -d "$PACKAGES/libs/$package" || {
    echo "Expected package directory missing: $PACKAGES/libs/$package" >&2
    exit 1
  }
done

mkdir -p "$PACKAGES/libs/libtirpc/patches" "$PACKAGES/libs/udns/patches"

cat > "$PACKAGES/libs/libtirpc/patches/100-musl-poll-header.patch" <<'PATCH'
--- a/src/svc_run.c
+++ b/src/svc_run.c
@@ -40 +40 @@
-#include <sys/poll.h>
+#include <poll.h>
PATCH

cat > "$PACKAGES/libs/udns/patches/100-musl-poll-header.patch" <<'PATCH'
--- a/udns_resolver.c
+++ b/udns_resolver.c
@@ -38 +38 @@
-#include <sys/poll.h>
+#include <poll.h>
PATCH

echo "Applied source patches for obsolete sys/poll.h includes (libtirpc, udns)."
