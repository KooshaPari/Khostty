# Khostty Windows installer end-to-end verification (2026-09-19)
# Reproducible: compiles nothing, reuses the staged package already on the host.
# Sequence: silent install -> hash check -> run installed exe -> silent uninstall.
param(
  [string]$Stage = 'C:\Users\koosh\khostty-verify\Khostty-0.1.0-win64',
  [string]$Dir   = 'C:\Users\koosh\khostty-verify\installed'
)
$ErrorActionPreference = 'Continue'
$setup = Join-Path $Stage 'output\Khostty-0.1.0-windows-x86_64-setup.exe'
$log   = Join-Path $Stage 'output\install.log'
$fail  = 0

Write-Output "=== SETUP ARTIFACT ==="
$si = Get-Item $setup
Write-Output ("path:   " + $setup)
Write-Output ("bytes:  " + $si.Length)
Write-Output ("sha256: " + (Get-FileHash $setup -Algorithm SHA256).Hash)
Write-Output ("ver:    " + $si.VersionInfo.FileVersion)

Write-Output ""
Write-Output "=== SILENT INSTALL ==="
Write-Output ("target: " + $Dir)
$p = Start-Process -FilePath $setup `
     -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',("/DIR=" + $Dir),("/LOG=" + $log) -PassThru
Write-Output ("installer exited: " + $p.WaitForExit(180000))

Write-Output ""
Write-Output "=== INSTALLED PAYLOAD ==="
$expect = @{
  'ghostty.exe'    = 'DF0B4C8772AD5DE8C65078CF0ADE6645AD16601B1B4CA37097E314ABF028D03E'
  'ghostty-vt.dll' = 'B4CFF87E6EE95DD97E0872FDAF752122ACEB4F7536662F6CEADF3905EAE6654F'
}
foreach ($n in $expect.Keys) {
  $f = Join-Path $Dir $n
  if (-not (Test-Path $f)) { Write-Output ("MISSING: $n"); $fail++; continue }
  $h = (Get-FileHash $f -Algorithm SHA256).Hash
  $ok = if ($h -eq $expect[$n]) { 'MATCH' } else { 'MISMATCH'; }
  if ($h -ne $expect[$n]) { $fail++ }
  Write-Output ("$ok  $h  $n")
}
$un = Join-Path $Dir 'unins000.exe'
Write-Output ("uninstaller present: " + (Test-Path $un))

Write-Output ""
Write-Output "=== RUN INSTALLED ghostty.exe +version ==="
$o = Join-Path $Dir 'v.out'
$p2 = Start-Process -FilePath (Join-Path $Dir 'ghostty.exe') -ArgumentList '+version' `
      -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError (Join-Path $Dir 'v.err')
Write-Output ("exited: " + $p2.WaitForExit(30000))
Write-Output "--- stdout ---"
if (Test-Path $o) { Get-Content $o }

Write-Output ""
Write-Output "=== SILENT UNINSTALL ==="
$u = Start-Process -FilePath $un -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -PassThru
Write-Output ("uninstaller exited: " + $u.WaitForExit(120000))
Start-Sleep -Seconds 3
$left = @(Get-ChildItem $Dir -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('v.out','v.err') })
Write-Output ("residual installed files: " + $left.Count)
if ($left.Count -ne 0) { $left | ForEach-Object { Write-Output ("  " + $_.Name) }; $fail++ }

Write-Output ""
Write-Output ("=== DONE failures=" + $fail + " ===")
exit $fail
