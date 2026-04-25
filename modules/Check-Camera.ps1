function Check-Camera {
    param(
        [Parameter(Mandatory)][string]$IP,
        [Parameter(Mandatory)][ValidateSet("reolink","instar")][string]$Typ,
        [string]$FfprobePfad = "",
        [string]$Name        = ""
    )

    $httpPort  = if ($Typ -eq "reolink") { 80   } else { 8080 }
    $rtspUrl   = if ($Typ -eq "reolink") { "rtsp://$IP:554/h264Preview_01_main" } else { "rtsp://$IP:554/11" }

    $pingOK     = $false
    $rtspPort   = "GESCHLOSSEN"
    $httpPort_S = "GESCHLOSSEN"
    $streamAktiv = $false
    $aufloesung = "n/a"
    $codec      = "n/a"
    $ffprobeVerfuegbar = $false

    # Ping
    try {
        Test-Connection -ComputerName $IP -Count 1 -TimeoutSeconds 1 -ErrorAction Stop | Out-Null
        $pingOK = $true
    }
    catch { $pingOK = $false }

    # RTSP Port 554
    try {
        $client     = New-Object System.Net.Sockets.TcpClient
        $verbindung = $client.BeginConnect($IP, 554, $null, $null)
        $erfolg     = $verbindung.AsyncWaitHandle.WaitOne(2000, $false)
        if ($erfolg -and $client.Connected) {
            $client.EndConnect($verbindung)
            $rtspPort = "OFFEN"
        }
        $client.Close(); $client.Dispose()
    }
    catch { $rtspPort = "GESCHLOSSEN" }

    # HTTP Port (80 fuer Reolink, 8080 fuer INSTAR)
    try {
        $client     = New-Object System.Net.Sockets.TcpClient
        $verbindung = $client.BeginConnect($IP, $httpPort, $null, $null)
        $erfolg     = $verbindung.AsyncWaitHandle.WaitOne(2000, $false)
        if ($erfolg -and $client.Connected) {
            $client.EndConnect($verbindung)
            $httpPort_S = "OFFEN"
        }
        $client.Close(); $client.Dispose()
    }
    catch { $httpPort_S = "GESCHLOSSEN" }

    # ffprobe Stream-Check (optional)
    if ($FfprobePfad -ne "" -and (Test-Path $FfprobePfad) -and $rtspPort -eq "OFFEN") {
        $ffprobeVerfuegbar = $true
        try {
            $ffprobeArgs = @(
                "-v", "quiet",
                "-print_format", "json",
                "-show_streams",
                "-rtsp_transport", "tcp",
                "-timeout", "5000000",
                $rtspUrl
            )

            $job = Start-Job -ScriptBlock {
                param($exe, $argList)
                & $exe @argList 2>&1
            } -ArgumentList $FfprobePfad, $ffprobeArgs

            $fertig = Wait-Job $job -Timeout 8
            if ($fertig) {
                $ffAusgabe = Receive-Job $job
                Remove-Job $job -Force

                if ($ffAusgabe) {
                    $jsonText = ($ffAusgabe | Where-Object { $_ -match "\S" }) -join "`n"
                    try {
                        $ffJson = $jsonText | ConvertFrom-Json -ErrorAction Stop
                        if ($ffJson.streams -and $ffJson.streams.Count -gt 0) {
                            $streamAktiv = $true
                            $videoStream = $ffJson.streams | Where-Object { $_.codec_type -eq "video" } | Select-Object -First 1
                            if ($videoStream) {
                                $codec      = if ($videoStream.codec_name)  { $videoStream.codec_name }  else { "n/a" }
                                $aufloesung = if ($videoStream.width -and $videoStream.height) {
                                    "$($videoStream.width)x$($videoStream.height)"
                                } else { "n/a" }
                            }
                        }
                    }
                    catch { $streamAktiv = $false }
                }
            }
            else {
                Remove-Job $job -Force
                $streamAktiv = $false
            }
        }
        catch { $streamAktiv = $false }
    }

    $streamAnzeige = if (-not $ffprobeVerfuegbar) { "ffprobe nicht verfuegbar" }
                     elseif ($streamAktiv)         { $true }
                     else                          { $false }

    # Gesamtstatus ermitteln
    $gesamtStatus = if (-not $pingOK)               { "FEHLER"   }
                    elseif ($rtspPort -eq "OFFEN")   { "OK"       }
                    else                             { "WARNUNG"  }

    $kameraLabel = if ($Name -ne "") { $Name } else { $IP }
    $infoText = "$kameraLabel – Ping: $(if ($pingOK) { 'OK' } else { 'FEHLER' }) | RTSP: $rtspPort | HTTP: $httpPort_S"
    if ($ffprobeVerfuegbar) {
        $infoText += " | Stream: $(if ($streamAktiv) { 'aktiv' } else { 'inaktiv' })"
        if ($streamAktiv) { $infoText += " | $aufloesung $codec" }
    }

    return [PSCustomObject]@{
        Status       = $gesamtStatus
        Ping_OK      = $pingOK
        RTSP_Port    = $rtspPort
        HTTP_Port    = $httpPort_S
        Stream_Aktiv = $streamAnzeige
        Aufloesung   = $aufloesung
        Codec        = $codec
        Info         = $infoText
    }
}
