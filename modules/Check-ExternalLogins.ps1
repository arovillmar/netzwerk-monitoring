function Check-ExternalLogins {
    param(
        [string]$FritzBoxIP  = "192.168.80.1",
        [string]$NAS1_IP     = "192.168.80.206",
        [int]$NAS1_SSHPort   = 822,
        [string]$NAS2_IP     = "192.168.80.207",
        [int]$NAS2_SSHPort   = 822,
        [string]$SSHUser     = "Armin"
    )

    $alleEintraege  = @()
    $verdaechtige   = 0
    $warnungen      = @()
    $zeitGrenze     = (Get-Date).AddHours(-24)

    function Invoke-SSH {
        param([string]$IP, [int]$Port, [string]$Befehl)
        $sshArgs = @(
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=no",
            "-p", $Port,
            "$SSHUser@$IP",
            $befehl
        )
        $ausgabe  = & ssh.exe @sshArgs 2>&1
        $exitCode = $LASTEXITCODE
        return [PSCustomObject]@{ Ausgabe = $ausgabe; ExitCode = $exitCode }
    }

    function Parse-AuthLog {
        param([string[]]$Zeilen, [string]$Quelle)
        $eintraege = @()
        $jahr = (Get-Date).Year

        foreach ($zeile in $Zeilen) {
            if ($zeile -notmatch "\S") { continue }

            $typ     = "Unbekannt"
            $ergebnis = "Unbekannt"
            $quellIP  = "n/a"

            if ($zeile -match "Accepted\s+\S+\s+for\s+\S+\s+from\s+([\d\.]+)") {
                $typ      = "SSH-Login"
                $ergebnis = "Erfolg"
                $quellIP  = $Matches[1]
            }
            elseif ($zeile -match "Failed\s+\S+\s+for\s+\S+\s+from\s+([\d\.]+)") {
                $typ      = "SSH-Login"
                $ergebnis = "Fehlversuch"
                $quellIP  = $Matches[1]
            }
            elseif ($zeile -match "Invalid user\s+\S+\s+from\s+([\d\.]+)") {
                $typ      = "SSH-Login"
                $ergebnis = "Fehlversuch (ungültiger User)"
                $quellIP  = $Matches[1]
            }
            else { continue }

            # Zeitstempel parsen (Format: "Apr 25 10:15:03")
            $zeitstempel = "n/a"
            if ($zeile -match "^(\w{3}\s+\d+\s+\d+:\d+:\d+)") {
                try {
                    $zeitstempel = [DateTime]::ParseExact("$($Matches[1]) $jahr", "MMM d HH:mm:ss yyyy", [System.Globalization.CultureInfo]::InvariantCulture).ToString("dd.MM.yyyy HH:mm:ss")
                }
                catch { $zeitstempel = $Matches[1] }
            }

            $eintraege += [PSCustomObject]@{
                Zeitstempel = $zeitstempel
                QuellIP     = $quellIP
                Zielgeraet  = $Quelle
                Typ         = $typ
                Ergebnis    = $ergebnis
            }
        }
        return $eintraege
    }

    # QUELLE 1 – Fritz!Box TR-064 VPN-Status (vereinfacht: Port-Check + Info)
    try {
        $fritzPing = Test-Connection -ComputerName $FritzBoxIP -Count 1 -TimeoutSeconds 1 -ErrorAction Stop
        $alleEintraege += [PSCustomObject]@{
            Zeitstempel = (Get-Date).ToString("dd.MM.yyyy HH:mm:ss")
            QuellIP     = "intern"
            Zielgeraet  = "Fritz!Box"
            Typ         = "Status-Check"
            Ergebnis    = "Erreichbar (VPN-Log nur über Fritz!Box UI abrufbar)"
        }
    }
    catch {
        $alleEintraege += [PSCustomObject]@{
            Zeitstempel = (Get-Date).ToString("dd.MM.yyyy HH:mm:ss")
            QuellIP     = "n/a"
            Zielgeraet  = "Fritz!Box"
            Typ         = "Status-Check"
            Ergebnis    = "FEHLER: Fritz!Box nicht erreichbar"
        }
    }

    # QUELLE 2 – Synology DS1525+ Auth-Log
    try {
        $authBefehl = "sudo grep -E 'Accepted|Failed|Invalid' /var/log/auth.log 2>/dev/null | tail -100"
        $result1    = Invoke-SSH -IP $NAS1_IP -Port $NAS1_SSHPort -Befehl $authBefehl

        if ($result1.ExitCode -eq 0 -and $result1.Ausgabe) {
            $eintraege1 = Parse-AuthLog -Zeilen $result1.Ausgabe -Quelle "DS1525+ ($NAS1_IP)"
            $alleEintraege += $eintraege1
            $fehlversuche1  = ($eintraege1 | Where-Object { $_.Ergebnis -match "Fehlversuch" }).Count
            $verdaechtige  += $fehlversuche1
        }
    }
    catch {
        $alleEintraege += [PSCustomObject]@{
            Zeitstempel = (Get-Date).ToString("dd.MM.yyyy HH:mm:ss")
            QuellIP     = "n/a"
            Zielgeraet  = "DS1525+ ($NAS1_IP)"
            Typ         = "SSH-Fehler"
            Ergebnis    = "Auth-Log nicht abrufbar: $($_.Exception.Message)"
        }
    }

    # QUELLE 3 – Synology DS723+ Auth-Log
    try {
        $authBefehl = "sudo grep -E 'Accepted|Failed|Invalid' /var/log/auth.log 2>/dev/null | tail -100"
        $result2    = Invoke-SSH -IP $NAS2_IP -Port $NAS2_SSHPort -Befehl $authBefehl

        if ($result2.ExitCode -eq 0 -and $result2.Ausgabe) {
            $eintraege2 = Parse-AuthLog -Zeilen $result2.Ausgabe -Quelle "DS723+ ($NAS2_IP)"
            $alleEintraege += $eintraege2
            $fehlversuche2  = ($eintraege2 | Where-Object { $_.Ergebnis -match "Fehlversuch" }).Count
            $verdaechtige  += $fehlversuche2
        }
    }
    catch {
        $alleEintraege += [PSCustomObject]@{
            Zeitstempel = (Get-Date).ToString("dd.MM.yyyy HH:mm:ss")
            QuellIP     = "n/a"
            Zielgeraet  = "DS723+ ($NAS2_IP)"
            Typ         = "SSH-Fehler"
            Ergebnis    = "Auth-Log nicht abrufbar: $($_.Exception.Message)"
        }
    }

    # QUELLE 4 – SASCHA_SERVER Ping + RDP Port 3389
    try {
        Test-Connection -ComputerName "192.168.80.87" -Count 1 -TimeoutSeconds 1 -ErrorAction Stop | Out-Null
        $rdpClient     = New-Object System.Net.Sockets.TcpClient
        $rdpVerbindung = $rdpClient.BeginConnect("192.168.80.87", 3389, $null, $null)
        $rdpErfolg     = $rdpVerbindung.AsyncWaitHandle.WaitOne(2000, $false)
        $rdpOffen      = $rdpErfolg -and $rdpClient.Connected
        if ($rdpErfolg -and $rdpClient.Connected) { $rdpClient.EndConnect($rdpVerbindung) }
        $rdpClient.Close(); $rdpClient.Dispose()

        $alleEintraege += [PSCustomObject]@{
            Zeitstempel = (Get-Date).ToString("dd.MM.yyyy HH:mm:ss")
            QuellIP     = "intern"
            Zielgeraet  = "SASCHA_SERVER (192.168.80.87)"
            Typ         = "RDP-Port-Check"
            Ergebnis    = if ($rdpOffen) { "Erreichbar – RDP Port 3389 offen" } else { "Warnung – RDP Port 3389 geschlossen" }
        }
    }
    catch {
        $alleEintraege += [PSCustomObject]@{
            Zeitstempel = (Get-Date).ToString("dd.MM.yyyy HH:mm:ss")
            QuellIP     = "n/a"
            Zielgeraet  = "SASCHA_SERVER (192.168.80.87)"
            Typ         = "RDP-Port-Check"
            Ergebnis    = "FEHLER: Server nicht erreichbar"
        }
    }

    $warnung      = $verdaechtige -gt 5
    $gesamtStatus = if ($warnung) { "WARNUNG" } else { "OK" }
    $infoText     = "$($alleEintraege.Count) Einträge geprüft. $verdaechtige Fehlversuche in den letzten 24h."
    if ($warnung) { $infoText += " WARNUNG: Mehr als 5 Fehlversuche erkannt!" }

    return [PSCustomObject]@{
        Status      = $gesamtStatus
        Eintraege   = $alleEintraege
        Verdaechtige = $verdaechtige
        Warnung     = $warnung
        Info        = $infoText
    }
}
