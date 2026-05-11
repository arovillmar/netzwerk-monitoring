function Check-Docker {
    param(
        [string]$IP                = "192.168.80.206",
        [int]$SSHPort              = 822,
        [string]$SSHUser           = "Armin",
        [array]$Containers         = @(),   # [{name, port, info}] aus config.json
        [int]$DockerPort           = 3000,  # Fallback wenn Containers leer
        [string]$AppName           = "docker",
        [int]$TimeoutMs            = 2000
    )

    # Fallback: Einzelner Container aus alten Feldern
    if ($Containers.Count -eq 0) {
        $Containers = @([PSCustomObject]@{ name = $AppName; port = $DockerPort; info = "" })
    }

    $ergebnisse  = @()
    $anzahlOK    = 0
    $anzahlFehler = 0

    foreach ($c in $Containers) {
        $port = if ($c.port) { [int]$c.port } else { [int]$c.Port }
        $name = if ($c.name) { $c.name }     else { $c.Name }

        $offen = $false
        try {
            $tcp  = New-Object System.Net.Sockets.TcpClient
            $conn = $tcp.BeginConnect($IP, $port, $null, $null)
            $offen = $conn.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            if ($offen) { try { $tcp.EndConnect($conn) } catch {} }
            $tcp.Close(); $tcp.Dispose()
        } catch { $offen = $false }

        if ($offen) { $anzahlOK++ } else { $anzahlFehler++ }

        $ergebnisse += [PSCustomObject]@{
            Name   = $name
            Port   = $port
            Status = if ($offen) { "OK" } else { "FEHLER" }
        }
    }

    $gesamtStatus = if ($anzahlFehler -gt 0 -and $anzahlOK -eq 0) { "FEHLER" } `
                    elseif ($anzahlFehler -gt 0) { "WARNUNG" } `
                    else { "OK" }

    # Kompakte Info-Zeile: "maennerballet(3000):OK  bookstack(6875):OK  nginx-rtmp(1935):FEHLER"
    $kurzInfo = ($ergebnisse | ForEach-Object {
        "$($_.Name)($($_.Port)):$($_.Status)"
    }) -join "  "

    return [PSCustomObject]@{
        Status           = $gesamtStatus
        Container_Name   = ($ergebnisse | Where-Object { $_.Status -eq "OK" } | Select-Object -First 1).Name
        Container_Status = if ($gesamtStatus -eq "OK") { "running" } else { "teilweise down" }
        Container_Uptime = "n/a"
        Port_Mapping     = ($ergebnisse | ForEach-Object { $_.Port }) -join ","
        Letzte_Logs      = @()
        Ergebnisse       = $ergebnisse
        Info             = "Docker: $kurzInfo"
    }
}
