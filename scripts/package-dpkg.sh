#!/usr/bin/env bash
# ==============================================================================
# Script: package-dpkg.sh
# Purpose: Package staged files into rootless and RootHide .deb packages.
# ==============================================================================

set -euxo pipefail

source "$(dirname "$0")/common-env.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTROL_TEMPLATE="$REPO_ROOT/debian/control.in"
CHANGELOG_FILE="$REPO_ROOT/debian/changelog"
COPYRIGHT_FILE="$REPO_ROOT/debian/copyright"

build_deb() {
  local arch="$1"    # "iphoneos-arm64" or "iphoneos-arm64e"
  local prefix="$2"  # "/var/jb" for rootless, "" for RootHide

  local PKGROOT="$WORKDIR/pkgroot-${arch}"
  rm -rf "$PKGROOT"
  mkdir -p "$PKGROOT/DEBIAN"
  chmod 0755 "$PKGROOT" "$PKGROOT/DEBIAN"

  # Rootless debs carry /var/jb paths. RootHide debs carry native jbroot paths.
  mkdir -p "$PKGROOT${prefix}"
  cp -a "$STAGE/usr" "$PKGROOT${prefix}/usr"
  cp -a "$STAGE/etc" "$PKGROOT${prefix}/etc" 2>/dev/null || true

  if [ "$arch" = "iphoneos-arm64e" ]; then
    mv "$PKGROOT/usr/local/bin/python3.14" "$PKGROOT/usr/local/bin/python3.14.bin"
    cat > "$PKGROOT/usr/local/bin/python3.14" <<'EOF'
#!/bin/sh
if [ -n "${CFFIXED_USER_HOME:-}" ]; then
  jbroot="${CFFIXED_USER_HOME%/var/root}"
  if [ -d "$jbroot/usr/local/lib/python3.14" ]; then
    export PYTHONHOME="$jbroot/usr/local"
  fi
fi
exec /usr/local/bin/python3.14.bin "$@"
EOF
    chmod 0755 "$PKGROOT/usr/local/bin/python3.14" "$PKGROOT/usr/local/bin/python3.14.bin"
    mkdir -p "$PKGROOT/usr/bin"
    ln -sf /usr/local/bin/python3.14 "$PKGROOT/usr/bin/python3.14"
  fi

  INSTALLED_SIZE="$(du -sk "$PKGROOT${prefix}/usr" | awk '{print $1}')"

  sed -e "s#\${PY_VER}#${PY_VER}#g" \
      -e "s#\${INSTALLED_SIZE}#${INSTALLED_SIZE}#g" \
      -e "s#iphoneos-arm64#${arch}#g" \
      "$CONTROL_TEMPLATE" > "$PKGROOT/DEBIAN/control"

  if [ -f "$CHANGELOG_FILE" ]; then
      mkdir -p "$PKGROOT${prefix}/usr/share/doc/com.korboy.python314"
      gzip -9 -n -c "$CHANGELOG_FILE" > "$PKGROOT${prefix}/usr/share/doc/com.korboy.python314/changelog.gz"
  fi

  if [ -f "$COPYRIGHT_FILE" ]; then
      mkdir -p "$PKGROOT${prefix}/usr/share/doc/com.korboy.python314"
      cp "$COPYRIGHT_FILE" "$PKGROOT${prefix}/usr/share/doc/com.korboy.python314/copyright"
  fi

  local OUTPUT="com.korboy.python314_${PY_VER}_${arch}.deb"
  dpkg-deb --build --root-owner-group "$PKGROOT" "$WORKDIR/$OUTPUT"
  echo "Success: Package built at $WORKDIR/$OUTPUT"
}

# Rootless (iphoneos-arm64, installs to /var/jb)
build_deb "iphoneos-arm64" "/var/jb"

# RootHide (iphoneos-arm64e, installs to native jbroot paths)
build_deb "iphoneos-arm64e" ""
