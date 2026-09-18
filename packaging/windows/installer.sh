#!/usr/bin/env bash
# WBS 9.13 — build and package a Windows .exe installer for Khostty.
#
#   packaging/windows/installer.sh --probe        # report toolchain readiness, change nothing
#   packaging/windows/installer.sh                # build (zig), stage, generate .iss, run ISCC
#   packaging/windows/installer.sh --stage-only   # build (zig), stage, generate .iss, stop
#   packaging/windows/installer.sh --no-build     # reuse zig-out/bin artifacts
#
# Requirements:
#   - zig 0.16.0 (cross-compiles ghostty.exe and ghostty-vt.dll for x86_64-windows-gnu)
#   - Inno Setup 6.3+ (ISCC.exe) to actually produce the installer. On a non-Windows
#     host ISCC.exe additionally needs wine.
#
#   Neither Inno Setup nor wine is present in this container, so the default mode
#   stops before ISCC and says so. --stage-only is the honest way to produce and
#   inspect the payload plus the generated .iss on such a host.
#
# Output (under $OUT, which defaults to <repo>/dist-release):
#   windows/stage/Khostty-<version>-win64/payload/    ghostty.exe, ghostty-vt.dll, LICENSE, ghostty.ico
#   windows/stage/Khostty-<version>-win64/khostty.iss generated Inno Setup definition
#   windows/stage/Khostty-<version>-win64/output/     ISCC output, on a host that has it
#   windows/toolchain-probe.txt                       probe evidence
#   windows/EVIDENCE.txt                              build evidence
#
# What is verifiable here
# -----------------------
# The staged payload and the generated .iss are fully verifiable on any host: the
# script hashes the payload and records exactly which bytes went in. Whether the
# resulting setup .exe *runs* on Windows is not verifiable here at all, and this
# script says so rather than claiming a smoke test it did not run.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/packaging/lib.sh"

# --- modes -----------------------------------------------------------------

MODE=build
DO_BUILD=1
for arg in "$@"; do
  case "$arg" in
    --probe) MODE=probe ;;
    --stage-only) MODE=stage ;;
    --no-build) DO_BUILD=0 ;;
    -h | --help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

# --- layout ----------------------------------------------------------------

VERSION="$(bash "$PKG_DIR/version.sh" --print)"
APP_NAME="Khostty"
TARGET_TRIPLE="x86_64-windows-gnu"
EXE_SRC="$REPO_ROOT/zig-out/bin/ghostty.exe"
DLL_SRC="$REPO_ROOT/zig-out/bin/ghostty-vt.dll"
ICON_SRC="$REPO_ROOT/dist/windows/ghostty.ico"
LICENSE_SRC="$REPO_ROOT/LICENSE"
STAGE_ROOT="$OUT/windows/stage/${APP_NAME}-${VERSION}-win64"
PAYLOAD="$STAGE_ROOT/payload"
ISS="$STAGE_ROOT/khostty.iss"
SETUP_NAME="${APP_NAME}-${VERSION}-windows-x86_64-setup.exe"
SETUP_PATH="$STAGE_ROOT/output/$SETUP_NAME"
PROBE_EVIDENCE="$OUT/windows/toolchain-probe.txt"
mkdir -p "$OUT/windows" "$LOG_DIR"

# A stable AppId is required so that an upgrade replaces the previous install
# instead of sitting next to it. Inno will otherwise generate a fresh random one
# per compilation, which makes every build look like a different product. This
# value is a UUIDv5 of the DNS name `khostty.com`, so it is reproducible by
# anyone:
#   python3 -c "import uuid; print(uuid.uuid5(uuid.NAMESPACE_DNS, 'khostty.com'))"
APP_ID="{14bf69b1-ddd1-54e3-81bc-898bdbacb251}"

# Inno's VersionInfoVersion must be four numeric components; AppVersion may be
# free text. The Khostty version is SemVer, so the build metadata never shows up
# here and a prerelease suffix is dropped for the numeric quad only.
v_major="${VERSION%%.*}"
v_rest="${VERSION#*.}"
v_minor="${v_rest%%.*}"
v_patch="${v_rest#*.}"
v_patch="${v_patch%%[!0-9]*}"
VERSION_QUAD="${v_major:-0}.${v_minor:-0}.${v_patch:-0}.0"

# ---------------------------------------------------------------- 1. probe --

step "probing the Windows packaging toolchain"

probe_status="ok"
probe_notes=()

record() { probe_notes+=("$1"); log "    $1"; }

if ! have zig; then
  probe_status="blocked"
  record "zig: MISSING (required to build the Windows binaries)"
else
  record "zig: $(zig version) ($(command -v zig))"
fi

# Inno Setup ships only as a Windows binary. On Windows it runs directly; on any
# other host it has to go through wine, so the two are reported separately: a
# present ISCC.exe with no wine is still a blocked toolchain.
ISCC_PATH="${KHOSTTY_ISCC:-}"
if [[ -z "$ISCC_PATH" ]]; then
  for candidate in \
    "$(command -v iscc 2>/dev/null || true)" \
    "$(command -v ISCC.exe 2>/dev/null || true)" \
    "/Applications/Inno Setup 6/ISCC.exe" \
    "$HOME/Applications/Inno Setup 6/ISCC.exe" \
    "${WINEPREFIX:-$HOME/.wine}/drive_c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
    "${WINEPREFIX:-$HOME/.wine}/drive_c/Program Files/Inno Setup 6/ISCC.exe"; do
    [[ -n "$candidate" && -f "$candidate" ]] && { ISCC_PATH="$candidate"; break; }
  done
fi

host_uname="$(uname -s)"
is_windows_host=0
case "$host_uname" in MINGW* | MSYS* | CYGWIN*) is_windows_host=1 ;; esac

if [[ -z "$ISCC_PATH" ]]; then
  probe_status="blocked"
  record "ISCC.exe: MISSING (install Inno Setup 6.3+, or set KHOSTTY_ISCC)"
else
  record "ISCC.exe: $ISCC_PATH"
fi

if ((is_windows_host)); then
  record "host: $host_uname (ISCC.exe runs natively; wine not required)"
elif [[ -z "$ISCC_PATH" ]]; then
  record "wine: not needed yet (ISCC.exe itself is missing)"
elif have wine; then
  record "wine: $(wine --version 2>/dev/null | head -1) ($(command -v wine))"
elif have wine64; then
  record "wine: wine64 present ($(command -v wine64))"
else
  probe_status="blocked"
  record "wine: MISSING (ISCC.exe is a Windows binary; needed on $host_uname)"
fi

# Inno reports its own version; useful because x64compatible architecture
# identifiers in the generated .iss require 6.3 or newer.
if [[ -n "$ISCC_PATH" ]] && ((is_windows_host)) && have "$ISCC_PATH"; then
  record "ISCC version: $("$ISCC_PATH" /? 2>/dev/null | head -1 || echo UNKNOWN)"
fi

# Optional alternative toolchains. Recorded only so the report is complete; this
# script does not drive them.
if have makensis; then record "makensis (NSIS): $(command -v makensis) — alternative, unused"; fi
if have wix; then record "wix (WiX): $(command -v wix) — alternative, unused"; fi

# Staged inputs.
if [[ -f "$EXE_SRC" ]]; then
  record "input ghostty.exe:    $(human_size "$EXE_SRC") (built $(date -u -r "$EXE_SRC" +%Y-%m-%dT%H:%M:%SZ))"
else
  record "input ghostty.exe:    not built yet (zig-out/bin/ghostty.exe absent)"
fi
if [[ -f "$DLL_SRC" ]]; then
  record "input ghostty-vt.dll: $(human_size "$DLL_SRC") (built $(date -u -r "$DLL_SRC" +%Y-%m-%dT%H:%M:%SZ))"
else
  record "input ghostty-vt.dll: not built yet (zig-out/bin/ghostty-vt.dll absent)"
fi
for asset in "$ICON_SRC" "$LICENSE_SRC"; do
  if [[ -f "$asset" ]]; then
    record "input $(basename "$asset"): $(human_size "$asset")"
  else
    probe_status="blocked"
    record "input $(basename "$asset"): MISSING ($asset)"
  fi
done

{
  echo "# Windows installer toolchain probe"
  echo "# generated by packaging/windows/installer.sh --probe"
  echo "# date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "status: $probe_status"
  for n in "${probe_notes[@]}"; do printf 'detail: %s\n' "$n"; done
} >"$PROBE_EVIDENCE"

if [[ "$MODE" == "probe" ]]; then
  echo "packaging/windows/installer.sh --probe"
  echo "  VERSION:        $VERSION"
  echo "  REPO_ROOT:      $REPO_ROOT"
  echo "  target:         $TARGET_TRIPLE"
  echo "  stage:          $STAGE_ROOT"
  echo "  setup:          $SETUP_NAME"
  for n in "${probe_notes[@]}"; do printf '  %s\n' "$n"; done
  echo "  evidence:       $PROBE_EVIDENCE"
  printf 'status: %s\n' "$probe_status"
  exit 0
fi

# ----------------------------------------------------------------- 2. build --

if ((DO_BUILD)); then
  # Two separate zig invocations, because they are two different products of the
  # same source tree:
  #   * `-Demit-lib-vt` with the default (none) app runtime builds the library
  #     and installs `ghostty-vt.dll` — this is the ABI consumers link against.
  #   * `-Dapp-runtime=windows` builds the executable and installs `ghostty.exe`.
  # The app runtime must be `none` for the dll build, since a non-none runtime
  # turns the build into an executable build (build.zig:224).
  step "building the Windows shared library (-Demit-lib-vt, target $TARGET_TRIPLE)"
  if ! zig_build -Dtarget="$TARGET_TRIPLE" -Demit-lib-vt -Doptimize=ReleaseFast \
    >"$LOG_DIR/windows-vt.log" 2>&1; then
    tail -30 "$LOG_DIR/windows-vt.log" >&2
    die "zig build (-Demit-lib-vt) failed; full log at $LOG_DIR/windows-vt.log"
  fi

  step "building the Windows executable (-Dapp-runtime=windows, target $TARGET_TRIPLE)"
  if ! zig_build -Dtarget="$TARGET_TRIPLE" -Dapp-runtime=windows \
    -Demit-macos-app=false -Doptimize=ReleaseFast \
    >"$LOG_DIR/windows-exe.log" 2>&1; then
    tail -30 "$LOG_DIR/windows-exe.log" >&2
    die "zig build (-Dapp-runtime=windows) failed; full log at $LOG_DIR/windows-exe.log"
  fi
else
  unverified "build skipped (--no-build): staging whatever is already in zig-out/bin"
fi

# ----------------------------------------------------------------- 3. stage --

step "staging the installer payload"
STAGE_ROOT="$(stage "windows/${APP_NAME}-${VERSION}-win64")"
PAYLOAD="$STAGE_ROOT/payload"
ISS="$STAGE_ROOT/khostty.iss"
SETUP_PATH="$STAGE_ROOT/output/$SETUP_NAME"
mkdir -p "$PAYLOAD" "$STAGE_ROOT/output"

for f in "$EXE_SRC" "$DLL_SRC" "$ICON_SRC" "$LICENSE_SRC"; do
  [[ -f "$f" ]] || die "required input missing: $f"
done
cp "$EXE_SRC" "$PAYLOAD/ghostty.exe"
cp "$DLL_SRC" "$PAYLOAD/ghostty-vt.dll"
cp "$ICON_SRC" "$PAYLOAD/ghostty.ico"
cp "$LICENSE_SRC" "$PAYLOAD/LICENSE"
ok "staged $(du -sh "$PAYLOAD" | cut -f1) into $PAYLOAD"

# ------------------------------------------------------ 4. generate the .iss --

step "generating the Inno Setup definition"
# Unquoted heredoc on purpose: $VERSION, $APP_ID and $VERSION_QUAD must expand.
# The Inno script has no `$` or backtick of its own, so nothing needs escaping.
cat >"$ISS" <<ISSEOF
; Generated by packaging/windows/installer.sh (WBS 9.13) - do not edit by hand.
; Regenerate with: packaging/windows/installer.sh --stage-only
;
; Compile with: ISCC.exe khostty.iss   (on Windows)
;               wine ISCC.exe khostty.iss   (anywhere else)

#define AppName "$APP_NAME"
#define AppVersion "$VERSION"
#define AppPublisher "KooshaPari"
#define AppURL "https://github.com/KooshaPari/khostty"
#define PayloadDir "payload"

[Setup]
; A stable AppId, see installer.sh for the UUIDv5 derivation.
AppId={{${APP_ID#\{}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
VersionInfoVersion=$VERSION_QUAD
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Setup
VersionInfoProductName={#AppName}
VersionInfoProductVersion=$VERSION_QUAD
; {autopf} resolves to Program Files in an administrative install and to the
; per-user location otherwise, so a non-admin user can install without elevation.
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
LicenseFile={#PayloadDir}\LICENSE
SetupIconFile={#PayloadDir}\ghostty.ico
UninstallDisplayIcon={app}\ghostty.exe
OutputDir=output
OutputBaseFilename=${APP_NAME}-${VERSION}-windows-x86_64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
SetupLogging=yes
; x64compatible requires Inno Setup 6.3+. On 6.0-6.2 replace it with x64 in
; both the line below and ArchitecturesInstallIn64BitMode.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#PayloadDir}\ghostty.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\ghostty-vt.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\ghostty.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\ghostty.exe"; IconFilename: "{app}\ghostty.ico"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\ghostty.exe"; IconFilename: "{app}\ghostty.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\ghostty.exe"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
ISSEOF
ok "wrote $ISS ($(wc -l <"$ISS" | tr -d ' ') lines, AppId $APP_ID, VersionInfoVersion $VERSION_QUAD)"

# Integrity of the payload, recorded now so the evidence file describes the exact
# bytes that the .iss above was generated against.
for f in ghostty.exe ghostty-vt.dll ghostty.ico LICENSE; do
  log "    $(sums_line "$PAYLOAD/$f")"
done

if [[ "$MODE" == "stage" ]]; then
  step "done (--stage-only: ISCC not invoked)"
  cat >&2 <<SUMMARY
  payload       $PAYLOAD
  inno script   $ISS
  next          run ISCC.exe on a Windows host (or wine here) with:
                  ISCC.exe "$ISS"
  not produced  $SETUP_NAME — no Inno Setup compiler on this host
SUMMARY
  exit 0
fi

# ---------------------------------------------------------------- 5. compile --

if [[ -z "$ISCC_PATH" ]]; then
  warn "ISCC.exe not found; searched PATH, /Applications, and \$WINEPREFIX"
  warn "  set KHOSTTY_ISCC=/path/to/ISCC.exe to point at one"
  die "cannot compile the installer: Inno Setup compiler missing (payload and .iss are ready in $STAGE_ROOT)"
fi

step "compiling the installer with $ISCC_PATH"
ISCC_RUNNER=()
if ((is_windows_host == 0)); then
  # Inno's compiler takes a Windows path for the script argument, so translate
  # when winepath is available rather than handing over a POSIX path.
  if have wine; then
    ISCC_RUNNER=(wine)
  elif have wine64; then
    ISCC_RUNNER=(wine64)
  else
    die "ISCC.exe is a Windows binary and no wine is installed (set KHOSTTY_ISCC to a native compiler, or install wine)"
  fi
  if have winepath; then
    ISS_ARG="$(winepath -w "$ISS" 2>/dev/null || printf '%s' "$ISS")"
  else
    ISS_ARG="$ISS"
  fi
else
  ISS_ARG="$ISS"
fi

# ISCC runs from the compiler's own working directory; the .iss uses paths
# relative to the script, so a `cd` is not required, but output lands in
# $STAGE_ROOT/output as declared by OutputDir.
set +e
"${ISCC_RUNNER[@]}" "$ISCC_PATH" /Q "$ISS_ARG" >"$LOG_DIR/windows-iscc.log" 2>&1
iscc_rc=$?
set -e
if [[ "$iscc_rc" -ne 0 ]]; then
  tail -30 "$LOG_DIR/windows-iscc.log" >&2
  die "ISCC failed (exit $iscc_rc); full log at $LOG_DIR/windows-iscc.log"
fi

[[ -f "$SETUP_PATH" ]] || die "ISCC reported success but $SETUP_PATH does not exist"
SETUP_SHA="$(sha256 "$SETUP_PATH")"
ok "built $SETUP_NAME ($(human_size "$SETUP_PATH"))"

# ------------------------------------------------------------- 6. evidence --

step "recording evidence"
{
  echo "# Windows installer — build evidence"
  echo "# generated by packaging/windows/installer.sh"
  echo "# date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "khostty_version: $VERSION"
  echo "source_commit: $(git -C "$REPO_ROOT" rev-parse HEAD)"
  echo "target_triple: $TARGET_TRIPLE"
  echo "zig: $(zig version 2>/dev/null || echo UNKNOWN)"
  echo "iscc: $ISCC_PATH"
  echo "app_id: $APP_ID"
  echo "version_info_version: $VERSION_QUAD"
  echo "inno_script: ${ISS#"$OUT"/}"
  echo "payload: ${PAYLOAD#"$OUT"/}"
  for f in ghostty.exe ghostty-vt.dll ghostty.ico LICENSE; do
    echo "payload_sha256[$(basename "$f")]: $(sha256 "$PAYLOAD/$f")"
  done
  echo "setup: $(basename "$SETUP_PATH")"
  echo "setup_sha256: $SETUP_SHA"
  echo "setup_bytes: $(wc -c <"$SETUP_PATH" | tr -d ' ')"
  echo "install_verified: NO — this host cannot run a Windows installer"
  echo "install_verified_reason: no Windows host or wine in this container; the setup .exe was compiled but never executed."
} >"$OUT/windows/EVIDENCE.txt"

( cd "$STAGE_ROOT/output" && sums_line "$SETUP_PATH" >"$SETUP_NAME.sha256" )

step "done"
cat >&2 <<SUMMARY
  artifact      $SETUP_PATH
  size          $(human_size "$SETUP_PATH")
  sha256        $SETUP_SHA
  payload       $PAYLOAD
  inno script   $ISS
  install test  not run — see $OUT/windows/EVIDENCE.txt
  logs          $LOG_DIR/
SUMMARY
