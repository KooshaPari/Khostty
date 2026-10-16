# Wait explicitly for the Windows GUI-subsystem executable; do not infer its
# status from PowerShell's asynchronous invocation behavior. Run via bounded.ps1.
$ErrorActionPreference = 'Stop'
$probe = [System.Diagnostics.Process]::new()
$probe.StartInfo.FileName = (Join-Path (Get-Location) 'zig-out/bin/ghostty.exe')
$probe.StartInfo.Arguments = '+version'
$probe.StartInfo.UseShellExecute = $false
$probe.StartInfo.CreateNoWindow = $true
$probe.StartInfo.RedirectStandardOutput = $true
$probe.StartInfo.RedirectStandardError = $true
$probe.Start() | Out-Null
$outTask = $probe.StandardOutput.ReadToEndAsync()
$errTask = $probe.StandardError.ReadToEndAsync()
$probe.WaitForExit()
$outTask.GetAwaiter().GetResult()
$errTask.GetAwaiter().GetResult()
$global:LASTEXITCODE = $probe.ExitCode
$probe.Dispose()
