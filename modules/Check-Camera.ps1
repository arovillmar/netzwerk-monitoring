function Check-Camera {
    param(
        [Parameter(Mandatory)][string]$IP,
        [Parameter(Mandatory)][ValidateSet("reolink","instar")][string]$Typ,
        [int]$HttpPort                                    = 0,
        [string]$FfprobePfad                             = "",
        [string]$RtspUrl                                 = "",
        [string]$Name                                    = "",
        [string]$ReolinkUser                             = "admin",
        [System.Security.SecureString]$ReolinkPassSecure = $null
    )

    # HTTP-Port: aus Parameter (config.json), sonst Typ-Standard
    if ($HttpPort -eq 0) {
        $HttpPort = if ($Typ -eq "reolink") { 80 } else { 8080 }
    }

    $startzeit   = [System.Diagnostics.Stopwatch]::StartNew()
    $pingOK      = $false
    $rtspOK      = $false
    $httpOK      = $false
    $streamInfo  = "n/a"
    $snapshotB64 = $null
    $apiStatus   = "n/a"
    $geraetInfo  = ""

    # ── Lockout-Schutz (nur Reolink) ─────────────────────────────────────────
    $lockoutPfad   = ""
    $lockoutAktiv  = $false

    if ($Typ -eq "reolink") {
        $scriptRoot  = Split-Path -Parent $PSScriptRoot
        $lockoutPfad = Join-Path $scriptRoot "logs\camera_lockout.json"

        if (Test-Path $lockoutPfad) {
            try {
                $lockoutDaten = Get-Content $lockoutPfad -Raw | ConvertFrom-Json
                $ipKey        = $IP -replace '\.','-'
                if ($lockoutDaten.$ipKey) {
                    $eintrag    = $lockoutDaten.$ipKey
                    $letzteZeit = [datetime]::Parse($eintrag.letzte_zeit)
                    $versuche   = [int]$eintrag.versuche
                    # Reset nach 60 Minuten
                    if ((Get-Date) - $letzteZeit -gt [TimeSpan]::FromMinutes(60)) {
                        $lockoutDaten.$ipKey = $null
                        $lockoutDaten | ConvertTo-Json | Set-Content $lockoutPfad -Encoding UTF8
                    }
                    elseif ($versuche -ge 3) {
                        $lockoutAktiv = $true
                    }
                }
            }
            catch {}
        }
    }

    # ── Ping ──────────────────────────────────────────────────────────────────
    try {
        Test-Connection -ComputerName $IP -Count 1 -TimeoutSeconds 2 -ErrorAction Stop | Out-Null
        $pingOK = $true
    }
    catch { $pingOK = $false }

    if (-not $pingOK) {
        $startzeit.Stop()
        return [PSCustomObject]@{
            Status         = "FEHLER"
            Ping_OK        = $false
            RTSP_Port      = "n/a"
            HTTP_Port      = "n/a"
            Stream_Aktiv   = $false
            Aufloesung     = "n/a"
            Codec          = "n/a"
            Snapshot_B64   = $null
            API_Status     = "n/a"
            Lockout_Aktiv  = $false
            Antwortzeit_ms = $startzeit.ElapsedMilliseconds
            Info           = "Kamera nicht erreichbar (kein Ping auf $IP)"
        }
    }

    # ── RTSP Port 554 ─────────────────────────────────────────────────────────
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $ar     = $client.BeginConnect($IP, 554, $null, $null)
        $rtspOK = $ar.AsyncWaitHandle.WaitOne(2000, $false) -and $client.Connected
        $client.Close(); $client.Dispose()
    }
    catch {}

    # ── HTTP-Port (aus config.json) ───────────────────────────────────────────
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $ar     = $client.BeginConnect($IP, $HttpPort, $null, $null)
        $httpOK = $ar.AsyncWaitHandle.WaitOne(2000, $false) -and $client.Connected
        $client.Close(); $client.Dispose()
    }
    catch {}

    # ── ffprobe Stream-Check (optional) ──────────────────────────────────────
    $aufloesung = "n/a"
    $codec      = "n/a"

    if ($FfprobePfad -and (Test-Path $FfprobePfad) -and $rtspOK -and $RtspUrl) {
        try {
            $ffArgs = @(
                "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "stream=width,height,codec_name",
                "-of", "csv=p=0",
                "-rtsp_transport", "tcp",
                "-timeout", "5000000",
                $RtspUrl
            )
            $job = Start-Job -ScriptBlock {
                param($exe, $args)
                & $exe @args 2>&1
            } -ArgumentList $FfprobePfad, $ffArgs

            $fertig = Wait-Job $job -Timeout 12
            if ($fertig) {
                $ausgabe = Receive-Job $job
                if ($ausgabe -match "(\d+),(\d+),(\w+)") {
                    $aufloesung = "$($Matches[1])x$($Matches[2])"
                    $codec      = $Matches[3]
                    $streamInfo = "Stream OK ($aufloesung $codec)"
                }
            }
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }
        catch {}
    }

    # ── Reolink API (nur wenn Passwort vorhanden und kein Lockout) ────────────
    if ($Typ -eq "reolink" -and $ReolinkPassSecure -and $httpOK -and -not $lockoutAktiv) {
        $bstr     = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ReolinkPassSecure)
        $passKlar = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        $ssl    = @{ SkipCertificateCheck = $true }
        $token  = $null
        $aktApi = $null

        $loginObj  = @([PSCustomObject]@{
            cmd    = "Login"
            action = 0
            param  = @{ User = @{ userName = $ReolinkUser; password = $passKlar } }
        })
        $loginBody  = $loginObj | ConvertTo-Json -Depth 6 -Compress
        if (-not $loginBody.StartsWith('[')) { $loginBody = "[$loginBody]" }
        $loginBytes = [System.Text.Encoding]::UTF8.GetBytes($loginBody)

        foreach ($endpoint in @("https://$IP/api.cgi", "https://$IP/cgi-bin/api.cgi")) {
            try {
                $resp = Invoke-RestMethod -Uri $endpoint -Method Post @ssl `
                    -Body $loginBytes -ContentType "application/json" -TimeoutSec 8 -ErrorAction Stop
                if ($resp -and $resp[0].code -eq 0) {
                    $token  = $resp[0].value.Token.name
                    $aktApi = $endpoint
                    $apiStatus = "Login OK"
                    break
                }
            }
            catch {}
        }

        # Lockout-Zähler aktualisieren
        if ($lockoutPfad) {
            try {
                $ld    = if (Test-Path $lockoutPfad) { Get-Content $lockoutPfad -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
                $ipKey = $IP -replace '\.','-'
                if ($token) {
                    # Login erfolgreich → Zähler zurücksetzen
                    $ld | Add-Member -NotePropertyName $ipKey -NotePropertyValue $null -Force
                }
                else {
                    # Login fehlgeschlagen → Zähler erhöhen
                    $alt     = if ($ld.$ipKey) { [int]$ld.$ipKey.versuche } else { 0 }
                    $neuerEintrag = [PSCustomObject]@{ versuche = $alt + 1; letzte_zeit = (Get-Date -Format "o") }
                    $ld | Add-Member -NotePropertyName $ipKey -NotePropertyValue $neuerEintrag -Force
                    if ($alt + 1 -ge 3) {
                        $apiStatus = "Lockout-Schutz aktiv (>= 3 Fehlversuche)"
                    }
                }
                $ld | ConvertTo-Json | Set-Content $lockoutPfad -Encoding UTF8
            }
            catch {}
        }

        if ($token -and $aktApi) {
            $tq = "?token=$([Uri]::EscapeDataString($token))"
            # Geräte-Info
            try {
                $ir = Invoke-RestMethod -Uri "$aktApi$tq" -Method Post @ssl `
                    -Body '[{"cmd":"GetDevInfo","action":0,"param":{"channel":0}}]' `
                    -ContentType "application/json" -TimeoutSec 8 -ErrorAction Stop
                if ($ir -and $ir[0].value.DevInfo) {
                    $di        = $ir[0].value.DevInfo
                    $geraetInfo = "$($di.model) FW:$($di.firmVer)"
                    $apiStatus  = "OK"
                }
            }
            catch {}

            # Snapshot
            $snapBase = $aktApi -replace '/(api|cgi-bin/api)\.cgi.*', ''
            foreach ($snapUri in @(
                "$snapBase/cgi-bin/api.cgi?cmd=Snap&channel=0&token=$([Uri]::EscapeDataString($token))",
                "$snapBase/snap.cgi?chn=0&user=$([Uri]::EscapeDataString($ReolinkUser))&password=$([Uri]::EscapeDataString($passKlar))"
            )) {
                if ($snapshotB64) { break }
                try {
                    $r = Invoke-WebRequest -Uri $snapUri @ssl -TimeoutSec 10 -ErrorAction Stop
                    if ($r.StatusCode -eq 200 -and $r.Headers['Content-Type'] -match 'image') {
                        $snapshotB64 = [Convert]::ToBase64String($r.Content)
                    }
                }
                catch {}
            }

            # Logout
            try {
                Invoke-RestMethod -Uri "$aktApi`?token=$token" -Method Post @ssl `
                    -Body '[{"cmd":"Logout","action":0,"param":{}}]' `
                    -ContentType "application/json" -TimeoutSec 4 | Out-Null
            }
            catch {}
        }
        $passKlar = $null
    }
    elseif ($Typ -eq "reolink" -and $lockoutAktiv) {
        $apiStatus = "Lockout-Schutz aktiv – Check übersprungen"
    }
    elseif ($Typ -eq "instar" -and $httpOK) {
        $apiStatus = "HTTP OK"
    }

    # ── Gesamtstatus ──────────────────────────────────────────────────────────
    $gesamtStatus = if (-not $pingOK)         { "FEHLER"  }
                    elseif (-not $rtspOK -and -not $httpOK) { "FEHLER"  }
                    elseif (-not $rtspOK -or -not $httpOK)  { "WARNUNG" }
                    else                                     { "OK"      }

    $infoTeile = @(
        "RTSP/554: $(if ($rtspOK) { 'OFFEN' } else { 'ZU' })",
        "HTTP/$HttpPort`: $(if ($httpOK) { 'OFFEN' } else { 'ZU' })"
    )
    if ($streamInfo -ne "n/a") { $infoTeile += $streamInfo }
    if ($geraetInfo)           { $infoTeile += $geraetInfo }
    if ($lockoutAktiv)         { $infoTeile += "LOCKOUT aktiv!" }

    $startzeit.Stop()

    return [PSCustomObject]@{
        Status         = $gesamtStatus
        Ping_OK        = $pingOK
        RTSP_Port      = if ($rtspOK) { "OFFEN" } else { "GESCHLOSSEN" }
        HTTP_Port      = if ($httpOK) { "OFFEN" } else { "GESCHLOSSEN" }
        HTTP_PortNr    = $HttpPort
        Stream_Aktiv   = if ($aufloesung -ne "n/a") { $true } else { $false }
        Aufloesung     = $aufloesung
        Codec          = $codec
        Snapshot_B64   = $snapshotB64
        API_Status     = $apiStatus
        Lockout_Aktiv  = $lockoutAktiv
        Antwortzeit_ms = $startzeit.ElapsedMilliseconds
        Info           = $infoTeile -join " | "
    }
}
