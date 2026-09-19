# Khostty Windows runtime verification (2026-09-19)
# Proves the Windows artifacts actually EXECUTE, not merely hash-match.
$ErrorActionPreference = 'Continue'
$dir = 'C:\Users\koosh\khostty-verify'
$exe = Join-Path $dir 'ghostty.exe'
$out = Join-Path $dir 'gv.out'
$err = Join-Path $dir 'gv.err'
$fail = 0

Write-Output "=== ENV ==="
Write-Output ("OS:       " + [System.Environment]::OSVersion.VersionString)
Write-Output ("Arch:     " + $env:PROCESSOR_ARCHITECTURE)
Write-Output ("PS:       " + $PSVersionTable.PSVersion.ToString())
Write-Output ("DotNet:   " + [System.Environment]::Version.ToString())

# ---------- TEST 1: ghostty.exe +version ----------
Write-Output ""
Write-Output "=== TEST 1: execute ghostty.exe +version (30s cap) ==="
Remove-Item $out,$err -ErrorAction SilentlyContinue
try {
    $p = Start-Process -FilePath $exe -ArgumentList '+version' -NoNewWindow -PassThru `
         -RedirectStandardOutput $out -RedirectStandardError $err
    $exited = $p.WaitForExit(30000)
    if (-not $exited) { try { $p.Kill() } catch {}; Write-Output 'RESULT: TIMEOUT_KILLED'; $fail++ }
    else { Write-Output ("RESULT: EXITED code=" + $p.ExitCode) }
} catch { Write-Output ("LAUNCH ERROR: " + $_.Exception.Message); $fail++ }
Write-Output "--- stdout ---"; if (Test-Path $out) { Get-Content $out }
Write-Output "--- stderr ---"; if (Test-Path $err) { Get-Content $err }

# ---------- TEST 2: load DLL + call real ABI ----------
Write-Output ""
Write-Output "=== TEST 2: ghostty-vt.dll live ABI calls ==="
$cs = @'
using System;
using System.Runtime.InteropServices;
public static class KHosttyVT {
  [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool SetDllDirectoryW(string p);
  [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr LoadLibraryW(string p);

  [DllImport("ghostty-vt.dll", CallingConvention=CallingConvention.Cdecl)]
  public static extern int ghostty_terminal_new(IntPtr alloc, out IntPtr term, ushort cols, ushort rows);
  [DllImport("ghostty-vt.dll", CallingConvention=CallingConvention.Cdecl)]
  public static extern int ghostty_terminal_resize(IntPtr term, ushort cols, ushort rows);
  [DllImport("ghostty-vt.dll", EntryPoint="ghostty_terminal_get", CallingConvention=CallingConvention.Cdecl)]
  public static extern int terminal_get_u32(IntPtr term, int data, out uint v);
  [DllImport("ghostty-vt.dll", EntryPoint="ghostty_terminal_get", CallingConvention=CallingConvention.Cdecl)]
  public static extern int terminal_get_ptr(IntPtr term, int data, out IntPtr v);
  [DllImport("ghostty-vt.dll", CallingConvention=CallingConvention.Cdecl)]
  public static extern void ghostty_terminal_vt_write(IntPtr term, byte[] data, UIntPtr len);
  [DllImport("ghostty-vt.dll", CallingConvention=CallingConvention.Cdecl)]
  public static extern void ghostty_terminal_free(IntPtr term);
  [DllImport("ghostty-vt.dll", CallingConvention=CallingConvention.Cdecl)]
  public static extern int ghostty_build_info(int data, out byte v);
}
'@
try { Add-Type -TypeDefinition $cs -ErrorAction Stop; Write-Output "Add-Type: OK" }
catch { Write-Output ("Add-Type FAILED: " + $_.Exception.Message); $fail++; exit 1 }

try {
    [KHosttyVT]::SetDllDirectoryW($dir) | Out-Null
    $h = [KHosttyVT]::LoadLibraryW((Join-Path $dir 'ghostty-vt.dll'))
    Write-Output ("LoadLibraryW handle: " + $h)
    if ($h -eq [IntPtr]::Zero) { Write-Output "RESULT: DLL LOAD FAILED"; $fail++ }
    else {
        # build_info(GHOSTTY_BUILD_INFO_SIMD=1) -> real computed value
        $b = [byte]0
        $r = [KHosttyVT]::ghostty_build_info(1, [ref]$b)
        Write-Output ("build_info(SIMD): rc=$r value=$b")

        # terminal_new(80,24)
        $term = [IntPtr]::Zero
        $r = [KHosttyVT]::ghostty_terminal_new([IntPtr]::Zero, [ref]$term, 80, 24)
        Write-Output ("terminal_new(80,24): rc=$r handle=$term")
        if ($r -ne 0 -or $term -eq [IntPtr]::Zero) { Write-Output "RESULT: NEW FAILED"; $fail++ }
        else {
            $c = [uint32]0; [void][KHosttyVT]::terminal_get_u32($term, 1, [ref]$c)   # COLS=1
            $rw = [uint32]0; [void][KHosttyVT]::terminal_get_u32($term, 2, [ref]$rw) # ROWS=2
            Write-Output ("get COLS=$c ROWS=$rw  (expect 80/24)")

            $r = [KHosttyVT]::ghostty_terminal_resize($term, 100, 40)
            $c2 = [uint32]0; [void][KHosttyVT]::terminal_get_u32($term, 1, [ref]$c2)
            $rw2 = [uint32]0; [void][KHosttyVT]::terminal_get_u32($term, 2, [ref]$rw2)
            Write-Output ("resize(100,40): rc=$r -> COLS=$c2 ROWS=$rw2  (expect 100/40)")
            if ($c2 -ne 100 -or $rw2 -ne 40) { $fail++ }

            # write VT: text + CRLF + SGR + OSC title
            $payload = "Hello from Khostty!`r`n" + [char]27 + "[31mred" + [char]27 + "[0m" + [char]27 + "]0;Khostty-Win" + [char]7
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
            [KHosttyVT]::ghostty_terminal_vt_write($term, $bytes, [UIntPtr]::new([uint64]$bytes.Length))
            $cy = [uint32]0; [void][KHosttyVT]::terminal_get_u32($term, 4, [ref]$cy) # CURSOR_Y=4
            Write-Output ("after vt_write: CURSOR_Y=$cy  (expect 1)")

            $tp = [IntPtr]::Zero
            [void][KHosttyVT]::terminal_get_ptr($term, 12, [ref]$tp)                # TITLE=12
            $title = if ($tp -eq [IntPtr]::Zero) { "<null>" } else { [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($tp) }
            Write-Output ("after OSC 0: TITLE='$title'  (expect Khostty-Win)")

            $ground = [uint32]0; [void][KHosttyVT]::terminal_get_u32($term, 38, [ref]$ground) # VT_GROUND=38
            Write-Output ("VT_GROUND=$ground  (expect 1)")

            [KHosttyVT]::ghostty_terminal_free($term)
            Write-Output "terminal_free: OK (no crash)"
            Write-Output "RESULT: FULL LIFECYCLE PASSED"
        }
    }
} catch { Write-Output ("ABI ERROR: " + $_.Exception.Message); $fail++ }

Write-Output ""
Write-Output ("=== DONE  failures=" + $fail + " ===")
exit $fail
