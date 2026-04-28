function Check-SynologyAPI {
    param(
        [Parameter(Mandatory)][string]$IP,
        [int]$Port                        = 5000,
        [Parameter(Mandatory)][string]$User,
        [System.Security.SecureString]$PassSecure = $null
    )

    $befehl = "df -h 2>/dev/null | grep '/volume'; cat /proc/mdstat 2>/dev/null | grep -E 'md[0-9]+\s*:'; free -m 2>/dev/null | grep Mem; uptime 2>/dev/null"

    $sshArgs = @(
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", "StrictHostKeyChecking=no",
        "-p", $Port,
        "$User@$IP",
        $befehl
    )

    $job = Start-Job -ScriptBlock {
        param($a)
        $out  = & ssh.exe @a 2>&1
        $code = $LASTEXITCODE
        [PSCustomObject]@{ Output = $out; ExitCode = $code }
    } -ArgumentList (,$sshArgs)

    $fertig = Wait-Job $job -Timeout 12
    if (-not $fertig) {
        Stop-Job $job
        Remove-Job $job -Force
        return [PSCustomObject]@{
            Status       = "FEHLER"
            Volumes      = @()
            SMART_Status = @()
            CPU_Temp     = "n/a"
            Uptime       = "n/a"
            Warnung      = $false
            Info         = "SSH Timeout – Synology $IP nicht erreichbar"
        }
    }

    $result = Receive-Job $job
    Remove-Job $job -Force

    if ($result.ExitCode -ne 0) {
        return [PSCustomObject]@{
            Status       = "FEHLER"
            Volumes      = @()
            SMART_Status = @()
            CPU_Temp     = "n/a"
            Uptime       = "n/a"
            Warnung      = $false
            Info         = "SSH fehlgeschlagen (Exit $($result.ExitCode)) – SSH-Key fuer $User@$IP eingerichtet?"
        }
    }

    $zeilen  = $result.Output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    $volumes = @()
    $warnung = $false

    foreach ($zeile in $zeilen) {
        if ($zeile -match '/volume') {
            $t = $zeile -split '\s+' | Where-Object { $_ -ne "" }
            if ($t.Count -ge 6) {
                $mountPoint = $t[5]
                # Nur echte Volumes (/volume1, /volume2 ...) – keine Sub-Pfade
                if ($mountPoint -notmatch '^/volume\d+$') { continue }
                $pStr    = $t[4] -replace '%', ''
                $prozent = 0
                [int]::TryParse($pStr, [ref]$prozent) | Out-Null
                if ($prozent -gt 80) { $warnung = $true }
                $volumes += [PSCustomObject]@{
                    Name        = $mountPoint
                    Groesse_GB  = $t[1]
                    Frei_GB     = $t[3]
                    Prozent     = $prozent
                    RAID_Status = "n/a"
                }
            }
        }
    }

    $raidZeilen  = $zeilen | Where-Object { $_ -match '^md[0-9]' }
    $uptimeZeile = $zeilen | Where-Object { $_ -match '\bup\b' } | Select-Object -Last 1
    $uptime      = if ($uptimeZeile) {
        if ($uptimeZeile -match 'up\s+(.+?),\s+\d+ user') { $Matches[1].Trim() } else { $uptimeZeile }
    } else { "n/a" }

    $gesamtStatus = if ($warnung) { "WARNUNG" } else { "OK" }
    $infoText     = "SSH OK. $($volumes.Count) Volume(s)."
    if ($volumes.Count -gt 0) {
        $infoText += " " + ($volumes | ForEach-Object { "$($_.Name): $($_.Prozent)%" }) -join " | "
    }
    if ($warnung)       { $infoText += " – Warnung: Volume > 80% belegt!" }
    if ($raidZeilen)    { $infoText += " | RAID: $($raidZeilen -join ', ')" }

    return [PSCustomObject]@{
        Status       = $gesamtStatus
        Volumes      = $volumes
        SMART_Status = @()
        CPU_Temp     = "n/a"
        Uptime       = $uptime
        Warnung      = $warnung
        Info         = $infoText
    }
}
