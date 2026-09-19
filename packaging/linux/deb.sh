#!/usr/bin/env bash
# WBS 9.12 — build and package a Linux .deb for Khostty.
#
#   packaging/linux/deb.sh              # build .deb from source
#   packaging/linux/deb.sh --probe      # report toolchain readiness
#
# Requirements:
#   - zig 0.16.0
#   - dpkg-deb (Debian/Ubuntu) or equivs (macOS cross-build)
#
# Output: dist/khostty_<version>_amd64.deb

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/packaging/lib.sh"

# --- version resolution ---------------------------------------------------
VERSION="$( "$REPO_ROOT/packaging/version.sh" --print )"
PACKAGE="khostty"
ARCH="amd64"
DEB_NAME="${PACKAGE}_${VERSION}_${ARCH}"
DEB_DIR="$REPO_ROOT/dist/${DEB_NAME}"

# --- probe mode -----------------------------------------------------------
if [[ "${1:-}" == "--probe" ]]; then
    echo "packaging/linux/deb.sh --probe"
    echo "  VERSION:        $VERSION"
    echo "  REPO_ROOT:      $REPO_ROOT"
    command -v zig     &>/dev/null && echo "  zig:            $(zig version)" || echo "  zig:            MISSING"
    command -v dpkg-deb &>/dev/null && echo "  dpkg-deb:       $(command -v dpkg-deb)" || echo "  dpkg-deb:       MISSING (install dpkg)"
    echo "  Output:         $REPO_ROOT/dist/${DEB_NAME}.deb"
    exit 0
fi

# --- build Linux binary ---------------------------------------------------
echo "==> Building Linux binary..."
cd "$REPO_ROOT"

# Only pass an explicit -Dtarget when we are NOT already on native x86_64 Linux.
# Passing -Dtarget=x86_64-linux-gnu on that host makes Zig treat the build as a
# cross-compile and refuse to link the system's shared libraries
# ("unable to find dynamic system library 'gobject-2.0' ... searched paths:
# none"), which is the exact failure mode this avoids. Cross-building from
# macOS or another architecture still needs the explicit target.
BUILD_TARGET_ARGS=()
if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
    BUILD_TARGET_ARGS+=("-Dtarget=x86_64-linux-gnu")
fi

zig build \
    "${BUILD_TARGET_ARGS[@]}" \
    -Dapp-runtime=gtk \
    -Demit-macos-app=false \
    -Doptimize=ReleaseFast

BINARY="$REPO_ROOT/zig-out/bin/ghostty"
[[ -f "$BINARY" ]] || die "Binary not found at $BINARY"

# --- assemble .deb tree ---------------------------------------------------
echo "==> Assembling .deb tree..."
rm -rf "$DEB_DIR"
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/usr/bin"
mkdir -p "$DEB_DIR/usr/share/applications"
mkdir -p "$DEB_DIR/usr/share/icons/hicolor/512x512/apps"
mkdir -p "$DEB_DIR/usr/share/metainfo"
mkdir -p "$DEB_DIR/usr/share/doc/$PACKAGE"

# Binary
cp "$BINARY" "$DEB_DIR/usr/bin/$PACKAGE"
chmod 755 "$DEB_DIR/usr/bin/$PACKAGE"

# Desktop entry (from upstream template)
sed -e "s/@NAME@/Khostty/g" \
    -e "s/@GHOSTTY@/$PACKAGE/g" \
    -e "s/@APPID@/com.khostty.Khostty/g" \
    "$REPO_ROOT/dist/linux/app.desktop.in" \
    > "$DEB_DIR/usr/share/applications/com.khostty.Khostty.desktop"

# Icon: install size-matched hicolor PNGs extracted from the upstream .ico.
ICO="$REPO_ROOT/dist/windows/ghostty.ico"
PNG_DIR="$DEB_DIR/usr/share/icons/hicolor"
if command -v magick &>/dev/null && [[ -f "$ICO" ]]; then
    EXTRACT_DIR="$(mktemp -d)"
    # The .ico embeds several sizes (16..256). ImageMagick writes them as
    # icon-0.png, icon-1.png, ...; pick the largest frame as the master.
    magick "$ICO" -background none "$EXTRACT_DIR/icon.png"
    MASTER="$(ls -S "$EXTRACT_DIR"/icon-*.png 2>/dev/null | head -1)"
    if [[ -z "$MASTER" ]]; then
        MASTER="$EXTRACT_DIR/icon.png"
    fi
    for size in 16 24 32 48 256 512; do
        dir="$PNG_DIR/${size}x${size}/apps"
        mkdir -p "$dir"
        magick "$MASTER" -resize "${size}x${size}" -background none \
            "$dir/com.khostty.Khostty.png"
    done
    rm -rf "$EXTRACT_DIR"
else
    echo "  Warning: no icon installed (install imagemagick for icon support)"
fi

# Metainfo
cat > "$DEB_DIR/usr/share/metainfo/com.khostty.Khostty.metainfo.xml" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>com.khostty.Khostty</id>
  <name>Khostty</name>
  <summary>A terminal emulator with agent/IPC support</summary>
  <metadata_license>MIT</metadata_license>
  <project_license>MIT</project_license>
  <url type="homepage">https://github.com/KooshaPari/khostty</url>
  <description>
    <p>Khostty is a Ghostty fork with native Windows support, expansive
    agent/IPC surfaces, and polyglot FFI (Rust, Go, Python, WASM).</p>
  </description>
  <provides>
    <binary>ghostty</binary>
  </provides>
</component>
XMLEOF

# Copyright
cat > "$DEB_DIR/usr/share/doc/$PACKAGE/copyright" << COPYEOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Khostty
Upstream-Contact: KooshaPari
Source: https://github.com/KooshaPari/khostty

Files: *
Copyright: 2024 Mitchell Hashimoto, 2026 KooshaPari
License: MIT
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 .
 1. Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.
 .
 2. Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.
 .
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
COPYEOF

# Changelog
cat > "$DEB_DIR/usr/share/doc/$PACKAGE/changelog" << CHGEOF
khostty (${VERSION}) unstable; urgency=low

  * Initial Khostty release
  * Windows cross-compilation support
  * Agent/IPC surface
  * Polyglot FFI (Rust, Go, Python, WASM)

 -- KooshaPari <noreply@github.com>  $(date -R)
CHGEOF

# DEBIAN control file
SIZE_KB=$(du -sk "$DEB_DIR" | cut -f1)

# Derive the real glibc floor from the built binary instead of hard-coding it.
# The native build inherits the build host's glibc symbol versions (e.g. a
# Fedora 44 host with glibc 2.43 pulls in GLIBC_2.43 acosf/atan2f and the
# GLIBC_2.38 __isoc23_* strto* family), so a stale floor like "libc6 >= 2.17"
# lets dpkg -i succeed on older distros and the binary then fails at load time
# ("version `GLIBC_2.43' not found"). readelf reports the highest GLIBC_x.y
# referenced by any object in the link; that exact value is the floor.
GLIBC_FLOOR=""
if command -v readelf &>/dev/null; then
    GLIBC_FLOOR="$(readelf -V "$BINARY" 2>/dev/null \
        | grep -oE 'GLIBC_2\.[0-9]+' | sort -uV | tail -1 | cut -d_ -f2 || true)"
fi
if [[ -z "$GLIBC_FLOOR" ]]; then
    die "Cannot derive glibc floor from $BINARY (readelf missing or no versioned symbols)"
fi
echo "==> Derived glibc floor: libc6 >= $GLIBC_FLOOR"

cat > "$DEB_DIR/DEBIAN/control" << CTRLEOF
Package: $PACKAGE
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Depends: libc6 (>= $GLIBC_FLOOR)
Installed-Size: $SIZE_KB
Maintainer: KooshaPari <noreply@github.com>
Homepage: https://github.com/KooshaPari/khostty
Description: Terminal emulator with agent/IPC support
 Khostty is a Ghostty fork with native Windows support,
 expansive agent/IPC surfaces, and polyglot FFI bindings
 (Rust, Go, Python, WASM). Built on the Ghostty terminal
 with additional features for agent-driven workflows.
CTRLEOF

# --- build .deb -----------------------------------------------------------
echo "==> Building .deb..."
mkdir -p "$REPO_ROOT/dist"
dpkg-deb --build "$DEB_DIR" "$REPO_ROOT/dist/${DEB_NAME}.deb"

echo "==> Done: $REPO_ROOT/dist/${DEB_NAME}.deb"
echo "    Install with: sudo dpkg -i dist/${DEB_NAME}.deb"
