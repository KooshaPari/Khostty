param([Parameter(Mandatory)][string]$Command, [int]$Seconds = 900, [string]$Name = 'verify')
$ErrorActionPreference = 'Stop'
$env:PATH = 'C:\Users\koosh\zig\zig-x86_64-windows-0.16.0;' + $env:PATH
$root = (Get-Location).Path
$log = Join-Path $root '.zig-cache/lane-c-receipts'
New-Item -ItemType Directory -Force $log | Out-Null
$script = Join-Path $log "$Name-command.ps1"
$exitFile = Join-Path $log "$Name.exit"
if (Test-Path $exitFile) { Remove-Item -LiteralPath $exitFile }
Set-Content $script ($Command + "`n`$code = `$LASTEXITCODE; if (`$null -eq `$code) { `$code = 1 }; Set-Content '$exitFile' `$code; exit `$code")
$process = Start-Process pwsh -WindowStyle Hidden -ArgumentList @('-NoProfile', '-File', $script) -PassThru -RedirectStandardOutput (Join-Path $log "$Name.stdout") -RedirectStandardError (Join-Path $log "$Name.stderr")
$finished = $process.WaitForExit($Seconds * 1000)
if (!$finished) {
    taskkill /PID $process.Id /T /F | Out-Null
    Write-Output "TIMEOUT after $Seconds seconds: $Command"
    exit 124
}
Get-Content (Join-Path $log "$Name.stdout")
Get-Content (Join-Path $log "$Name.stderr")
if (!(Test-Path $exitFile)) { throw "Missing process exit receipt" }
$code = [int](Get-Content $exitFile)
Write-Output "EXIT ${code}: $Command"
exit $code

