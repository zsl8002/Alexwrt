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


# elfutils defines gettext_noop unconditionally even when gettext.h has
# already supplied the same macro. Guard the fallback instead of allowing
# hundreds of duplicate-definition warnings in host/target builds.
ELFUTILS_PATCHES="$ROOT/package/libs/elfutils/patches"
test -d "$ELFUTILS_PATCHES" || {
  echo "Expected elfutils patch directory missing: $ELFUTILS_PATCHES" >&2
  exit 1
}
cat > "$ELFUTILS_PATCHES/102-guard-gettext-noop.patch" <<'PATCH'
--- a/lib/system.h
+++ b/lib/system.h
@@ -162 +162,3 @@
-#define gettext_noop(Str) Str
+#ifndef gettext_noop
+#define gettext_noop(Str) Str
+#endif
PATCH

echo "Applied AX6600 compatibility patches: musl poll headers and elfutils gettext macro guard."
