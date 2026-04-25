function Check-SSH {
    param(
        [Parameter(Mandatory)][string]$IP,
        [int]$Port = 22,
        [Parameter(Mandatory)][string]$User
    )

    try {
        $befehl = "uptime && df -h / && free -m"
        $sshArgs = @(
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=no",
            "-p", $Port,
            "$User@$IP",
            $befehl
        )

        $ausgabe = & ssh.exe @sshArgs 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            return [PSCustomObject]@{
                Status    = "FEHLER"
                Uptime    = "n/a"
                Disk_Info = "n/a"
                RAM_Info  = "n/a"
                Info      = "SSH fehlgeschlagen (Exit $exitCode): $($ausgabe -join ' ')"
            }
        }

        $zeilen = $ausgabe -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

        $uptime   = if ($zeilen.Count -ge 1) { $zeilen[0] } else { "n/a" }
        $diskInfo = if ($zeilen.Count -ge 2) { ($zeilen | Where-Object { $_ -match "^/" -or $_ -match "\s+/\s*$" } | Select-Object -First 1) } else { "n/a" }
        $ramInfo  = if ($zeilen.Count -ge 3) { ($zeilen | Where-Object { $_ -match "^Mem:" } | Select-Object -First 1) } else { "n/a" }

        if (-not $diskInfo) { $diskInfo = "n/a" }
        if (-not $ramInfo)  { $ramInfo  = "n/a" }

        return [PSCustomObject]@{
            Status    = "OK"
            Uptime    = $uptime
            Disk_Info = $diskInfo
            RAM_Info  = $ramInfo
            Info      = "SSH-Verbindung erfolgreich"
        }
    }
    catch {
        return [PSCustomObject]@{
            Status    = "FEHLER"
            Uptime    = "n/a"
            Disk_Info = "n/a"
            RAM_Info  = "n/a"
            Info      = "Ausnahme: $($_.Exception.Message)"
        }
    }
}
