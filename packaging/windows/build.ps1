# Native desk build gate. Requires pinned Zig, Git Bash and Inno Setup 6.3+.
[CmdletBinding()]
param([ValidateRange(1, 64)][int]$Jobs = 2)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$previousLocation = Get-Location
try {
    Set-Location $repo
    $version = (& zig version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -ne '0.16.0') {
        throw "error.ZigVersionMismatch: expected=0.16.0 actual=$version"
    }
    $logs = Join-Path $repo 'dist-release/logs'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    $cache = Join-Path $repo 'dist-release/cache/zc/o'
    $globalCache = Join-Path $repo 'dist-release/cache/zc/g'
    function Invoke-ZigBuild([string]$Name, [string[]]$BuildArguments, [int]$TimeoutSeconds = 0) {
        $arguments = @('build', "-j$Jobs", '--cache-dir', $cache,
            '--global-cache-dir', $globalCache) + $BuildArguments
        Write-Output ("COMMAND: zig " + ($arguments -join ' '))
        if ($TimeoutSeconds -eq 0) {
            & zig @arguments 2>&1 | Tee-Object -FilePath (Join-Path $logs "$Name.log")
            if ($LASTEXITCODE -ne 0) {
                throw "error.ZigBuildFailed: step=$Name exit=$LASTEXITCODE"
            }
            return
        }
        # A Windows test runner can stop answering its native timeout protocol.
        # Bound the entire owned test-build process tree independently as well.
        $run = [System.Diagnostics.Process]::new()
        $run.StartInfo.FileName = (Get-Command zig -ErrorAction Stop).Source
        $run.StartInfo.WorkingDirectory = $repo
        $run.StartInfo.UseShellExecute = $false
        $run.StartInfo.CreateNoWindow = $true
        $run.StartInfo.RedirectStandardOutput = $true
        $run.StartInfo.RedirectStandardError = $true
        foreach ($argument in $arguments) { $run.StartInfo.ArgumentList.Add($argument) }
        if (-not $run.Start()) { throw 'error.TestsStartFailed' }
        $outTask = $run.StandardOutput.ReadToEndAsync()
        $errTask = $run.StandardError.ReadToEndAsync()
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $timedOut = $false
        while (-not $run.WaitForExit(1000)) {
            if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $timedOut = $true
                $run.Kill($true)
                [void]$run.WaitForExit(5000)
                break
            }
        }
        $tasks = [System.Threading.Tasks.Task[]]@($outTask, $errTask)
        if (-not [System.Threading.Tasks.Task]::WaitAll($tasks, 5000)) {
            throw 'error.TestsTimedOut: output drain did not complete'
        }
        ($outTask.Result + $errTask.Result) |
            Tee-Object -FilePath (Join-Path $logs "$Name.log")
        if ($timedOut) { throw "error.TestsTimedOut: step=$Name limit=${TimeoutSeconds}s" }
        if ($run.ExitCode -ne 0) {
            throw "error.ZigBuildFailed: step=$Name exit=$($run.ExitCode)"
        }
    }
    Invoke-ZigBuild 'windows-vt' @('-Dtarget=x86_64-windows-gnu',
        '-Demit-lib-vt', '-Doptimize=ReleaseFast', '--summary', 'all')
    Invoke-ZigBuild 'windows-exe' @('-Dtarget=x86_64-windows-gnu',
        '-Dapp-runtime=windows', '-Demit-macos-app=false',
        '-Doptimize=ReleaseFast', '--summary', 'all')
    Invoke-ZigBuild 'windows-tests' @('test-windows-apprt',
        '-Dtarget=x86_64-windows-gnu', '--test-timeout', '60s', '--summary', 'all') -TimeoutSeconds 900

    if (-not $env:KHOSTTY_ISCC) {
        $env:KHOSTTY_ISCC = 'C:/Program Files (x86)/Inno Setup 6/ISCC.exe'
    }
    if (-not (Test-Path -LiteralPath $env:KHOSTTY_ISCC)) {
        throw 'error.InnoSetupCompilerMissing'
    }
    # Both payloads above were rebuilt successfully; packaging reuses those bytes.
    & bash packaging/windows/installer.sh --no-build 2>&1 |
        Tee-Object -FilePath (Join-Path $logs 'windows-installer.log')
    if ($LASTEXITCODE -ne 0) {
        throw "error.InstallerBuildFailed: exit=$LASTEXITCODE"
    }
    $stdout = Join-Path $logs 'windows-version.stdout.log'
    $stderr = Join-Path $logs 'windows-version.stderr.log'
    # Start-Process can lose ExitCode for a very short-lived GUI-subsystem exe.
    # Own the .NET process handle and drain both streams without blocking it.
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo.FileName = Join-Path $repo 'zig-out/bin/ghostty.exe'
    $process.StartInfo.ArgumentList.Add('+version')
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    if (-not $process.Start()) { throw 'error.VersionSmokeStartFailed' }
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(30000)) {
        $process.Kill()
        throw 'error.VersionSmokeTimedOut'
    }
    $outTask.GetAwaiter().GetResult() | Set-Content $stdout
    $errTask.GetAwaiter().GetResult() | Set-Content $stderr
    Get-Content $stdout, $stderr
    if ($process.ExitCode -ne 0) {
        throw "error.VersionSmokeFailed: exit=$($process.ExitCode)"
    }
    Write-Output 'Build, Windows runtime tests, installer compilation and +version passed.'
    Write-Output 'GUI rendering and installer install/uninstall remain separate acceptance gates.'
} finally {
    Set-Location $previousLocation
}
