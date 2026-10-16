param([Parameter(Mandatory)][string]$ServerExe)
$ErrorActionPreference = 'Stop'
# The fixture is a separate process; this client uses independent .NET APIs.
$startInfo = [Diagnostics.ProcessStartInfo]::new($ServerExe)
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$server = [Diagnostics.Process]::Start($startInfo)
$null = $server.Handle
try {
    for ($connection = 0; $connection -lt 2; $connection++) {
        $pipe = [System.IO.Pipes.NamedPipeClientStream]::new('.', "khostty-$($server.Id)", [System.IO.Pipes.PipeDirection]::InOut)
        try {
            $pipe.Connect(10000)
            foreach ($case in @(@{ Action = 0; Payload = 'ping' }, @{ Action = 1; Payload = '{"action":"new_tab"}' })) {
                $payload = [Text.Encoding]::UTF8.GetBytes($case.Payload)
                $bytes = [BitConverter]::GetBytes([uint16]$case.Action) + [BitConverter]::GetBytes([uint32]$payload.Length) + $payload
                # Fragment every byte to verify exact-read handling without relying on write boundaries.
                foreach ($byte in $bytes) { $pipe.WriteByte($byte) }
                $actual = [byte[]]::new($bytes.Length)
                $offset = 0
                while ($offset -lt $actual.Length) {
                    $count = $pipe.Read($actual, $offset, $actual.Length - $offset)
                    if ($count -eq 0) { throw 'Unexpected EOF' }
                    $offset += $count
                }
                if ([Convert]::ToHexString($actual) -cne [Convert]::ToHexString($bytes)) { throw 'Frame mismatch' }
                Write-Output "PASS process round-trip connection=$connection action=$($case.Action) payload=$($case.Payload)"
            }
        } finally { $pipe.Dispose() }
    }
    if (-not $server.WaitForExit(10000)) { throw 'Server did not exit' }
    if ($server.ExitCode -ne 0) { throw "Server exited $($server.ExitCode)" }
    # No listener remains: stale endpoint must fail rather than report success.
    $stale = [System.IO.Pipes.NamedPipeClientStream]::new('.', "khostty-$($server.Id)", [System.IO.Pipes.PipeDirection]::InOut)
    try {
        try { $stale.Connect(200); throw 'Stale endpoint unexpectedly connected' }
        catch [TimeoutException] { Write-Output 'PASS stale endpoint refused' }
    } finally { $stale.Dispose() }
} finally {
    if (-not $server.HasExited) { $server.Kill(); $server.WaitForExit() }
    $server.Dispose()
}

