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

    # ── Reolink Snapshot ──────────────────────────────────────────────────────
    if ($Typ -eq "reolink" -and $ReolinkPassSecure -and $httpOK) {
        $bstr     = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ReolinkPassSecure)
        $passKlar = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        $pEnc = [Uri]::EscapeDataString($passKlar)
        $uEnc = [Uri]::EscapeDataString($ReolinkUser)
        $rs   = Get-Random -Maximum 9999

        $snapUrls = @(
            "https://$IP/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=$rs&user=$uEnc&password=$pEnc",
            "https://${IP}:${HttpPort}/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=$rs&user=$uEnc&password=$pEnc",
            "http://${IP}:${HttpPort}/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=$rs&user=$uEnc&password=$pEnc",
            "https://$IP/api.cgi?cmd=Snap&channel=0&rs=$rs&user=$uEnc&password=$pEnc",
            "https://${IP}:${HttpPort}/api.cgi?cmd=Snap&channel=0&rs=$rs&user=$uEnc&password=$pEnc",
            "http://${IP}:${HttpPort}/api.cgi?cmd=Snap&channel=0&rs=$rs&user=$uEnc&password=$pEnc"
        )

        # TLS-Downgrade: alte Reolink-Firmware nutzt TLS 1.0/1.1
        $tlsAlt = [Net.ServicePointManager]::SecurityProtocol
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12 } catch {}

        foreach ($snapUri in $snapUrls) {
            if ($snapshotB64) { break }
            try {
                $r = Invoke-WebRequest -Uri $snapUri -SkipCertificateCheck -TimeoutSec 12 -ErrorAction Stop
                if ($r.StatusCode -eq 200 -and $r.Headers['Content-Type'] -match 'image') {
                    $snapshotB64 = [Convert]::ToBase64String($r.Content)
                    $apiStatus   = "Snapshot OK"
                }
            }
            catch {}
        }

        # curl.exe-Fallback falls Invoke-WebRequest an TLS scheitert
        if (-not $snapshotB64) {
            $curlExe = Get-Command "curl.exe" -ErrorAction SilentlyContinue
            if ($curlExe) {
                $tmpFile = [System.IO.Path]::GetTempFileName()
                foreach ($snapUri in $snapUrls) {
                    if ($snapshotB64) { break }
                    try {
                        & curl.exe --silent --insecure --max-time 10 --output $tmpFile $snapUri 2>$null
                        if (Test-Path $tmpFile) {
                            $bytes = [System.IO.File]::ReadAllBytes($tmpFile)
                            if ($bytes.Length -gt 1000 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) {
                                $snapshotB64 = [Convert]::ToBase64String($bytes)
                                $apiStatus   = "Snapshot OK (curl)"
                            }
                        }
                    }
                    catch {}
                }
                try { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue } catch {}
            }
        }

        [Net.ServicePointManager]::SecurityProtocol = $tlsAlt
        if (-not $snapshotB64) { $apiStatus = "Snapshot fehlgeschlagen" }
        $passKlar = $null
    }

    # ── INSTAR Snapshot (Basic Auth → Digest via curl) ────────────────────────
    elseif ($Typ -eq "instar" -and $ReolinkPassSecure -and $httpOK) {
        $bstr     = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ReolinkPassSecure)
        $passKlar = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        $b64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${ReolinkUser}:${passKlar}"))
        $authHdr = @{ Authorization = "Basic $b64Auth" }

        $instarUrls = @(
            "http://${IP}:${HttpPort}/snap.cgi",
            "http://${IP}:${HttpPort}/tmpfs/snap.jpg",
            "http://${IP}:${HttpPort}/cgi-bin/snapshot.cgi"
        )

        # Basic Auth Versuch
        foreach ($snapUri in $instarUrls) {
            if ($snapshotB64) { break }
            try {
                $r = Invoke-WebRequest -Uri $snapUri -Headers $authHdr -TimeoutSec 10 -ErrorAction Stop
                if ($r.StatusCode -eq 200 -and $r.Headers['Content-Type'] -match 'image') {
                    $snapshotB64 = [Convert]::ToBase64String($r.Content)
                    $apiStatus   = "Snapshot OK"
                }
            }
            catch {}
        }

        # Digest Auth via curl.exe als Fallback
        if (-not $snapshotB64) {
            $curlExe = Get-Command "curl.exe" -ErrorAction SilentlyContinue
            if ($curlExe) {
                $tmpFile = [System.IO.Path]::GetTempFileName()
                foreach ($snapUri in $instarUrls) {
                    if ($snapshotB64) { break }
                    try {
                        & curl.exe --silent --digest --user "${ReolinkUser}:${passKlar}" --max-time 10 --output $tmpFile $snapUri 2>$null
                        if (Test-Path $tmpFile) {
                            $bytes = [System.IO.File]::ReadAllBytes($tmpFile)
                            if ($bytes.Length -gt 500 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) {
                                $snapshotB64 = [Convert]::ToBase64String($bytes)
                                $apiStatus   = "Snapshot OK (Digest)"
                            }
                        }
                    }
                    catch {}
                }
                try { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue } catch {}
            }
        }

        if (-not $snapshotB64) { $apiStatus = "HTTP OK (kein Snapshot)" }
        $passKlar = $null
    }
    elseif ($Typ -eq "instar" -and $httpOK) {
        $apiStatus = "HTTP OK"
    }

    # ── Gesamtstatus ──────────────────────────────────────────────────────────
    # FEHLER: kein Ping, oder weder HTTP noch RTSP erreichbar
    # WARNUNG: HTTP offen aber RTSP geschlossen (RTSP deaktiviert in Kamera-Settings)
    # OK: HTTP offen (+ optional RTSP)
    $gesamtStatus = if (-not $pingOK)                        { "FEHLER"  }
                    elseif (-not $httpOK -and -not $rtspOK)  { "FEHLER"  }
                    else                                      { "OK"      }

    $infoTeile = @(
        "RTSP/554: $(if ($rtspOK) { 'OFFEN' } else { 'ZU' })",
        "HTTP/$HttpPort`: $(if ($httpOK) { 'OFFEN' } else { 'ZU' })"
    )
    if ($snapshotB64)          { $infoTeile += "Snapshot OK" }
    if ($streamInfo -ne "n/a") { $infoTeile += $streamInfo }
    if ($geraetInfo)           { $infoTeile += $geraetInfo }

    $startzeit.Stop()

    return [PSCustomObject]@{
        Status         = $gesamtStatus
        Ping_OK        = $pingOK
        RTSP_Port      = if ($rtspOK) { "OFFEN" } else { "GESCHLOSSEN" }
        HTTP_Port      = if ($httpOK) { "OFFEN" } else { "GESCHLOSSEN" }
        HTTP_PortNr    = $HttpPort
        Stream_Aktiv   = if ($snapshotB64) { $true } else { $false }
        Aufloesung     = $aufloesung
        Codec          = $codec
        Snapshot_B64   = $snapshotB64
        API_Status     = $apiStatus
        Lockout_Aktiv  = $false
        Antwortzeit_ms = $startzeit.ElapsedMilliseconds
        Info           = $infoTeile -join " | "
    }
}
