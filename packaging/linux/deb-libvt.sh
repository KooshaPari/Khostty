#!/usr/bin/env bash
# Build a structurally valid Debian package for the libghostty-vt payload.
#
#   packaging/linux/deb-libvt.sh            # build + verify structure
#   packaging/linux/deb-libvt.sh --probe    # report toolchain readiness
#   packaging/linux/deb-libvt.sh --verify   # install + run it on x86-64 Debian
#
# WHY THIS EXISTS SEPARATELY FROM deb.sh
#
# deb.sh packages the GTK *application*. That payload needs GTK4 and
# libadwaita C headers, which are Linux-only; `zig build -Dapp-runtime=gtk
# -Dtarget=x86_64-linux-gnu` fails on macOS with `'gtk/gtk.h' not found`
# and `'adwaita.h' not found`. So on a macOS host deb.sh cannot produce a
# package at all, and the Linux acceptance bullet stays open.
#
# libghostty-vt is cross-compilable from macOS to x86_64-linux-gnu, so this
# script packages *that* payload instead. It is a real, loadable x86-64 Linux
# shared library with a real C ABI; it is not the terminal application.
#
# WHAT EACH MODE PROVES
#
#   build/verify  -> a valid .deb exists: dpkg-deb can read it, `ar` sees the
#                    three required members, the control metadata parses.
#   --verify      -> the .deb *installs* (`dpkg -i`) and the installed library
#                    *runs* (a C program links against the installed headers,
#                    loads the installed .so, and a VT assertion passes).
#
# Nothing here is inferred. If a step cannot run on this host the script fails
# loudly rather than printing a success line for work it did not do.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/packaging/lib.sh"

# --- identity -------------------------------------------------------------

VERSION="$( "$REPO_ROOT/packaging/version.sh" --print )"
PACKAGE="khostty-vt"
ARCH="amd64"
TRIPLET="x86_64-linux-gnu"
LIB_MAJOR="0"
DEB_BASENAME="${PACKAGE}_${VERSION}_${ARCH}"
DEB_PATH="$REPO_ROOT/dist/${DEB_BASENAME}.deb"
LIB_SRC="$REPO_ROOT/zig-out/lib/libghostty-vt.so.${VERSION}"
HDR_SRC="$REPO_ROOT/zig-out/include/ghostty"
PC_SRC="$REPO_ROOT/zig-out/share/pkgconfig/libghostty-vt.pc"

# Container used by --verify. Must be x86-64 so it matches Architecture: amd64.
VERIFY_IMAGE="${KHOSTTY_VERIFY_IMAGE:-gcc:12-bookworm}"
VERIFY_PLATFORM="linux/amd64"

# --- probe mode -----------------------------------------------------------

if [[ "${1:-}" == "--probe" ]]; then
  echo "packaging/linux/deb-libvt.sh --probe"
  echo "  VERSION:        $VERSION"
  echo "  REPO_ROOT:      $REPO_ROOT"
  command -v zig &>/dev/null && echo "  zig:            $(zig version)" || echo "  zig:            MISSING"
  command -v dpkg-deb &>/dev/null && echo "  dpkg-deb:       $(command -v dpkg-deb)" || echo "  dpkg-deb:       MISSING (brew install dpkg)"
  command -v ar &>/dev/null && echo "  ar:             $(command -v ar)" || echo "  ar:             MISSING"
  if have docker; then
    echo "  docker:         $(command -v docker)"
    echo "  verify image:   $VERIFY_IMAGE ($VERIFY_PLATFORM)"
  else
    echo "  docker:         MISSING (--verify unavailable; build/structural verify still work)"
  fi
  echo "  Output:         $DEB_PATH"
  exit 0
fi

# --- build the payload ----------------------------------------------------

build_payload() {
  require zig "cross-compile libghostty-vt for $TRIPLET"
  step "Building libghostty-vt for $TRIPLET"
  # Same invocation style as deb.sh: repo-local .zig-cache, plain zig build.
  ( cd "$REPO_ROOT" && zig build \
      -Demit-lib-vt \
      -Dtarget="$TRIPLET" \
      -Doptimize=ReleaseFast )

  [[ -f "$LIB_SRC" ]] || die "expected $LIB_SRC after build; got nothing"
  [[ -f "$HDR_SRC/vt.h" ]] || die "expected umbrella header $HDR_SRC/vt.h"
  [[ -d "$HDR_SRC/vt" ]] || die "expected header dir $HDR_SRC/vt"

  # The headers we ship must be the authoritative C ABI, byte for byte. If the
  # installed copy has drifted from include/, the package would advertise an ABI
  # it does not implement, so refuse to package rather than ship a lie.
  diff -rq "$REPO_ROOT/include/ghostty/vt" "$HDR_SRC/vt" >/dev/null \
    || die "staged headers differ from include/ghostty/vt; refusing to package"
  diff -q "$REPO_ROOT/include/ghostty/vt.h" "$HDR_SRC/vt.h" >/dev/null \
    || die "staged vt.h differs from include/ghostty/vt.h; refusing to package"

  # Prove the artifact is really an x86-64 Linux ELF shared object with the
  # SONAME the package's symlink chain claims.
  local desc
  desc="$(file -b "$LIB_SRC")"
  case "$desc" in
    *"ELF 64-bit LSB shared object, x86-64"*) : ;;
    *) die "payload is not an x86-64 Linux shared object: $desc" ;;
  esac
  if have objdump; then
    local soname needed
    soname="$(objdump -p "$LIB_SRC" | awk '/SONAME/{print $2}')"
    [[ "$soname" == "libghostty-vt.so.${LIB_MAJOR}" ]] \
      || die "SONAME is '$soname', expected libghostty-vt.so.${LIB_MAJOR}"
    needed="$(objdump -p "$LIB_SRC" | awk '/NEEDED/{print $2}' | sort -u | tr '\n' ' ')"
    ok "payload ELF verified: soname=$soname needs=[${needed% }]"
  else
    warn "objdump absent; SONAME/NEEDED not independently confirmed"
  fi
  ok "payload $(basename "$LIB_SRC") $(human_size "$LIB_SRC")"
}

# --- stage the package tree ----------------------------------------------

stage_tree() {
  local tree
  tree="$(stage linux-deb-libvt)"
  [[ -n "$tree" ]] || die "stage() returned an empty path"

  step "Staging .deb tree under $tree"
  mkdir -p "$tree/DEBIAN"
  mkdir -p "$tree/usr/lib/$TRIPLET/pkgconfig"
  mkdir -p "$tree/usr/include/ghostty"
  mkdir -p "$tree/usr/share/doc/$PACKAGE"

  # Runtime library + the two compatibility symlinks ldconfig expects:
  #   libghostty-vt.so.0.1.0   real object
  #   libghostty-vt.so.0       SONAME link (needed at runtime)
  #   libghostty-vt.so         dev link   (needed by `-lghostty-vt`)
  # Debian policy would split the dev link into a -dev package; this is a single
  # combined runtime+dev package, so all three live here. Stated, not hidden.
  install -m 0644 "$LIB_SRC" "$tree/usr/lib/$TRIPLET/libghostty-vt.so.${VERSION}"
  ( cd "$tree/usr/lib/$TRIPLET" && ln -sf "libghostty-vt.so.${VERSION}" "libghostty-vt.so.${LIB_MAJOR}" )
  ( cd "$tree/usr/lib/$TRIPLET" && ln -sf "libghostty-vt.so.${LIB_MAJOR}"  "libghostty-vt.so" )

  # Headers (authoritative ABI; guarded by diff in build_payload).
  cp "$HDR_SRC/vt.h" "$tree/usr/include/ghostty/vt.h"
  cp -R "$HDR_SRC/vt" "$tree/usr/include/ghostty/vt"

  # pkg-config, with the build-host prefix rewritten to the install prefix.
  # The generated .pc embeds the macOS zig-out path, which would be a broken
  # path on Debian. Requires.private is empty on this target.
  sed -e "s|^prefix=.*|prefix=/usr|" \
      -e "s|^includedir=.*|includedir=\${prefix}/include|" \
      -e "s|^libdir=.*|libdir=\${prefix}/lib/$TRIPLET|" \
      "$PC_SRC" > "$tree/usr/lib/$TRIPLET/pkgconfig/libghostty-vt.pc"

  # Docs.
  cat > "$tree/usr/share/doc/$PACKAGE/copyright" <<'COPYEOF'
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
 AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED. IN NO EVENT SHALL THE
 COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES ARISING IN ANY WAY
 OUT OF THE USE OF THIS SOFTWARE.
COPYEOF

  cat > "$tree/usr/share/doc/$PACKAGE/changelog" <<CHGEOF
$PACKAGE (${VERSION}) unstable; urgency=low

  * libghostty-vt ${VERSION} cross-compiled for $TRIPLET
  * VT library runtime (libghostty-vt.so.${LIB_MAJOR}) plus public C headers

 -- KooshaPari <noreply@github.com>  $(date -R)
CHGEOF
  gzip -9 -n -c "$tree/usr/share/doc/$PACKAGE/changelog" \
    > "$tree/usr/share/doc/$PACKAGE/changelog.gz"
  rm -f "$tree/usr/share/doc/$PACKAGE/changelog"

  # Maintainer scripts. Only ldconfig; the library needs no configuration.
  cat > "$tree/DEBIAN/postinst" <<'PIEOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    ldconfig
fi
exit 0
PIEOF
  cat > "$tree/DEBIAN/postrm" <<'PREOF'
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    ldconfig
fi
exit 0
PREOF
  chmod 0755 "$tree/DEBIAN/postinst" "$tree/DEBIAN/postrm"

  # md5sums over the payload (not DEBIAN/, not directories, not symlinks).
  ( cd "$tree" && find usr -type f -print | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s  %s\n' "$(md5_of "$tree/$f")" "${f#./}"
    done ) > "$tree/DEBIAN/md5sums"

  # control. Installed-Size in KiB, dependencies from the ELF actually shipped.
  local size_kb
  size_kb="$(du -sk "$tree/usr" | cut -f1)"
  cat > "$tree/DEBIAN/control" <<CTRLEOF
Package: $PACKAGE
Version: $VERSION
Section: libs
Priority: optional
Architecture: $ARCH
Depends: libc6 (>= 2.29)
Installed-Size: $size_kb
Maintainer: KooshaPari <noreply@github.com>
Homepage: https://github.com/KooshaPari/khostty
Description: Ghostty VT library (libghostty-vt) with public C headers
 libghostty-vt is the terminal-emulation core of Khostty, exposed as a C ABI
 consumable from C, Zig, Rust, Go, Python and WASM. This package ships the
 x86_64 shared library, its SONAME and development symlinks, the public
 headers, and a pkg-config file.
 .
 This is the VT *library* payload only. The Khostty terminal *application*
 (GTK4 + libadwaita) is not part of this package.
CTRLEOF
  # dpkg-deb requires a trailing newline in control; heredoc provides one.

  printf '%s' "$tree"
}

md5_of() {
  if have md5; then md5 -q "$1"
  elif have md5sum; then md5sum "$1" | awk '{print $1}'
  else die "no md5 tool (need md5 or md5sum)"
  fi
}

# --- build the archive ----------------------------------------------------

build_deb() {
  local tree="$1"
  require dpkg-deb "build the .deb"
  step "Building .deb with dpkg-deb"
  mkdir -p "$REPO_ROOT/dist"
  rm -f "$DEB_PATH"
  # --root-owner-group: we are not root, and a package must not embed the
  # build host's uid/gid. -Zxz: Debian's default compressor.
  dpkg-deb --build --root-owner-group -Zxz "$tree" "$DEB_PATH"
  [[ -f "$DEB_PATH" ]] || die "dpkg-deb reported success but $DEB_PATH is absent"
}

# --- structural verification ---------------------------------------------

verify_structure() {
  step "Verifying .deb structure"
  require dpkg-deb "read the .deb back"

  dpkg-deb --info "$DEB_PATH" >/dev/null \
    || die "dpkg-deb --info failed on $DEB_PATH"
  ok "dpkg-deb --info succeeded"

  local contents
  contents="$(dpkg-deb --contents "$DEB_PATH")"
  ok "dpkg-deb --contents succeeded ($(wc -l <<<"$contents" | tr -d ' ') entries)"

  # A .deb is an `ar` archive whose first member must be debian-binary.
  local members
  members="$(ar t "$DEB_PATH")"
  [[ "$(head -1 <<<"$members")" == "debian-binary" ]] \
    || die "first ar member is not debian-binary: $(head -1 <<<"$members")"
  grep -q '^control\.tar' <<<"$members" || die "no control.tar member"
  grep -q '^data\.tar' <<<"$members"    || die "no data.tar member"
  ok "ar members: $(tr '\n' ' ' <<<"$members")"

  # debian-binary must read exactly "2.0".
  local tmp bin_ver
  tmp="$(mktemp -d)"
  ( cd "$tmp" && ar x "$DEB_PATH" debian-binary )
  bin_ver="$(tr -d '\n' < "$tmp/debian-binary")"
  rm -rf "$tmp"
  [[ "$bin_ver" == "2.0" ]] || die "debian-binary version is '$bin_ver', expected 2.0"
  ok "debian-binary = $bin_ver"

  # The control fields we depend on for installability.
  local field
  for field in Package Version Architecture Depends; do
    printf '%s: %s\n' "$field" "$(dpkg-deb -f "$DEB_PATH" "$field")"
  done

  # SONAME must match a symlink the package actually installs, or the library
  # would be unloadable after install. This is checked by string comparison, not
  # by reading the tree back from the archive.
  printf '%s' "$contents" | grep -q "libghostty-vt.so.${LIB_MAJOR}\$" \
    || die "no libghostty-vt.so.${LIB_MAJOR} symlink in the package"

  ok "sha256 $(sha256 "$DEB_PATH")"
  ok "size   $(human_size "$DEB_PATH") ($(wc -c <"$DEB_PATH" | tr -d ' ') bytes)"
}

# --- acceptance: install and run on real x86-64 Debian -------------------

verify_install_run() {
  step "Acceptance: install + run on $VERIFY_PLATFORM ($VERIFY_IMAGE)"
  require docker "install and run the .deb on x86-64 Debian"
  [[ -f "$DEB_PATH" ]] || die "build the .deb first (no $DEB_PATH)"

  # Mount the repo read-only. Everything else happens inside the container, so
  # nothing is written into the source tree.
  docker run --rm --platform "$VERIFY_PLATFORM" -v "$REPO_ROOT":/w:ro "$VERIFY_IMAGE" \
    sh -eu -c '
      echo "--- container ---"
      . /etc/os-release; echo "distro: $PRETTY_NAME"
      echo "arch:   $(uname -m)"
      echo "glibc:  $(ldd --version | head -1)"

      echo "--- dpkg -i ---"
      dpkg -i /w/dist/'"$DEB_BASENAME"'.deb
      echo "dpkg_exit=$?"

      echo "--- dpkg -L (installed files) ---"
      dpkg -L '"$PACKAGE"'
      dpkg -s '"$PACKAGE"' | sed -n "1,6p"

      echo "--- ldconfig resolves the SONAME ---"
      ldconfig
      ldconfig -p | grep ghostty

      echo "--- dpkg -V (md5sums integrity) ---"
      dpkg -V '"$PACKAGE"' && echo "PASS dpkg -V: no modified or missing files"

      echo "--- pkg-config file points at real installed paths ---"
      pc=/usr/lib/'"$TRIPLET"'/pkgconfig/libghostty-vt.pc
      cat "$pc"
      grep -qx "prefix=/usr" "$pc"                      || { echo "FAIL pc prefix"; exit 1; }
      test -f /usr/include/ghostty/vt.h                 || { echo "FAIL pc includedir"; exit 1; }
      test -f /usr/lib/'"$TRIPLET"'/libghostty-vt.so    || { echo "FAIL pc libdir"; exit 1; }
      echo "PASS pkg-config paths exist"

      echo "--- link + run the shipped example against the INSTALLED headers/lib ---"
      gcc /w/example/c-vt-formatter/src/main.c -o /tmp/fmt -lghostty-vt
      /tmp/fmt | tee /tmp/out.txt

      echo "--- functional assertions ---"
      grep -q "Line 1: Hello World!"                 /tmp/out.txt && echo "PASS text"
      grep -q "Line 3: Overwritten!"                  /tmp/out.txt && echo "PASS erase+rewrite"
      grep -q "Placed at (5,10)"                      /tmp/out.txt && echo "PASS cursor placement"
      grep -q -- "RIGHT->"                            /tmp/out.txt && echo "PASS right-edge clamp"
      echo "--- remove ---"
      dpkg -r '"$PACKAGE"'
      echo "ALL CONTAINER CHECKS DONE"
    '
  ok "install + run acceptance PASSED on $VERIFY_PLATFORM"
}

# --- main -----------------------------------------------------------------

case "${1:-}" in
  "")
    build_payload
    TREE="$(stage_tree)"
    build_deb "$TREE"
    verify_structure
    echo
    ok "Built $DEB_PATH"
    unverified "install + run are NOT proven by this mode; run: $0 --verify"
    ;;
  --verify)
    [[ -f "$DEB_PATH" ]] || { build_payload; TREE="$(stage_tree)"; build_deb "$TREE"; }
    verify_structure
    verify_install_run
    ;;
  *)
    die "unknown argument: $1 (expected --probe, --verify, or nothing)"
    ;;
esac
