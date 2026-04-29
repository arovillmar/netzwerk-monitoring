function Check-Docker {
    param(
        [string]$IP          = "192.168.80.206",
        [int]$SSHPort        = 822,
        [string]$SSHUser     = "Armin",
        [int]$DockerPort     = 3000,
        [string]$AppName     = "maennerballet",
        [int]$TimeoutMs      = 3000
    )

    # TCP-Port-Check: Ist die App erreichbar?
    $portOffen = $false
    try {
        $tcp  = New-Object System.Net.Sockets.TcpClient
        $conn = $tcp.BeginConnect($IP, $DockerPort, $null, $null)
        $portOffen = $conn.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($portOffen) { try { $tcp.EndConnect($conn) } catch {} }
        $tcp.Close(); $tcp.Dispose()
    } catch { $portOffen = $false }

    if (-not $portOffen) {
        return [PSCustomObject]@{
            Status           = "FEHLER"
            Container_Name   = $AppName
            Container_Status = "nicht erreichbar"
            Container_Uptime = "n/a"
            Port_Mapping     = "Port $DockerPort"
            Letzte_Logs      = @()
            Info             = "Docker-App $($AppName): Port $DockerPort nicht erreichbar – Container gestoppt?"
        }
    }

    # Zusätzlich: SSH-basierte Container-Infos (optional, schlägt fehl wenn kein docker-Gruppen-Zugriff)
    $containerStatus = "running"
    $containerUptime = "n/a"
    $dockerInfoOk    = $false

    $dockerBin = "/var/packages/ContainerManager/target/usr/bin/docker"
    $sshArgs = @(
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", "StrictHostKeyChecking=no",
        "-p", $SSHPort,
        "$SSHUser@$IP",
        "$dockerBin ps --filter name=$AppName --format '{{.Status}}' 2>/dev/null"
    )
    try {
        $job    = Start-Job -ScriptBlock { param($a) $out = & ssh.exe @a 2>&1; [PSCustomObject]@{ Output=$out; ExitCode=$LASTEXITCODE } } -ArgumentList (,$sshArgs)
        $fertig = Wait-Job $job -Timeout 8
        if ($fertig) {
            $result = Receive-Job $job
            if ($result.ExitCode -eq 0 -and $result.Output -match "\S") {
                $containerStatus = ($result.Output -join " ").Trim()
                $dockerInfoOk    = $true
            }
        }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    } catch {}

    $infoText = if ($dockerInfoOk) {
        "Docker $($AppName): Port $DockerPort offen | Status: $containerStatus"
    } else {
        "Docker $($AppName): Port $DockerPort offen"
    }

    return [PSCustomObject]@{
        Status           = "OK"
        Container_Name   = $AppName
        Container_Status = $containerStatus
        Container_Uptime = $containerUptime
        Port_Mapping     = "Port $DockerPort"
        Letzte_Logs      = @()
        Info             = $infoText
    }
}
