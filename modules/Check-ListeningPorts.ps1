function Check-ListeningPorts {
    param(
        [string]$IP,
        [int]$SSHPort    = 22,
        [string]$SSHUser = "pi",
        [string]$Hostname = $IP
    )

    # ss bevorzugen, netstat als Fallback (Synology BusyBox hat kein ss)
    $befehl  = 'ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null'
    $sshArgs = @(
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", "StrictHostKeyChecking=no",
        "-p", $SSHPort,
        "$SSHUser@$IP",
        $befehl
    )

    $ausgabe  = & ssh.exe @sshArgs 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        return [PSCustomObject]@{
            Status   = "FEHLER"
            Hostname = $Hostname
            Ports    = @()
            Info     = "SSH nicht erreichbar ($IP)"
        }
    }

    $ports = @()
    foreach ($zeile in $ausgabe) {
        if ($zeile -notmatch "LISTEN") { continue }

        # Lokale Adresse:Port finden – erstes Feld im Format ETWAS:ZAHL
        $teile    = @($zeile -split '\s+') | Where-Object { $_ -ne "" }
        $addrFeld = $teile | Where-Object { $_ -match '^\S+:\d+$' } | Select-Object -First 1
        if (-not $addrFeld) { continue }
        if ($addrFeld -notmatch ':(\d+)$') { continue }
        $portNr  = [int]$Matches[1]
        $adresse = $addrFeld -replace ':\d+$', ''

        # Prozessname: ss-Format users:(("name",...)) oder netstat pid/name
        $prozess = ""
        if ($zeile -match 'users:\(\("([^"]+)"')   { $prozess = $Matches[1] }
        elseif ($zeile -match '\s\d+/(\S+)\s*$')   { $prozess = $Matches[1] }

        $ports += [PSCustomObject]@{
            Port    = $portNr
            Adresse = $adresse
            Prozess = $prozess
        }
    }

    # Duplikate entfernen: Pro Port eine Zeile, bevorzugt die mit Prozessname
    $ports = $ports | Group-Object Port | ForEach-Object {
        $mitProz = $_.Group | Where-Object { $_.Prozess -ne "" } | Select-Object -First 1
        if ($mitProz) { $mitProz } else { $_.Group[0] }
    } | Sort-Object Port

    return [PSCustomObject]@{
        Status   = "OK"
        Hostname = $Hostname
        Ports    = $ports
        Info     = "$($ports.Count) lauschende Ports auf $Hostname"
    }
}
