function Check-MailstoreAPI {
    param(
        [string]$IP                                          = "192.168.80.120",
        [string]$User                                        = "admin",
        [System.Security.SecureString]$PassSecure            = $null,
        [string]$WinUser                                     = "Administrator",
        [System.Security.SecureString]$WinPassSecure         = $null,
        [int]$ApiPort                                        = 8463
    )

    $startzeit = [System.Diagnostics.Stopwatch]::StartNew()

    $passwort = ""
    if ($PassSecure) {
        $bstr     = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PassSecure)
        $passwort = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }

    # ── STUFE 1 – Ping + RDP-Port ────────────────────────────────────────────
    $vmErreichbar = $false
    try {
        $vmErreichbar = (New-Object System.Net.NetworkInformation.Ping).Send($IP, 2000).Status -eq 'Success'
        if (-not $vmErreichbar) { throw "Kein Ping" }
    }
    catch {}

    if (-not $vmErreichbar) {
        $startzeit.Stop()
        return [PSCustomObject]@{
            Status          = "FEHLER"
            VM_Erreichbar   = $false
            Dienst_Laeuft   = $false
            API_Verfuegbar  = $false
            Fehler_Jobs     = 0
            Archiv_Gesamt   = 0
            Jobs            = @()
            Kritische_Jobs  = @()
            Antwortzeit_ms  = $startzeit.ElapsedMilliseconds
            Info            = "Mailstore VM nicht erreichbar (kein Ping auf $IP)"
        }
    }

    $rdpOffen = $false
    try {
        $client   = New-Object System.Net.Sockets.TcpClient
        $ar       = $client.BeginConnect($IP, 3389, $null, $null)
        $rdpOffen = $ar.AsyncWaitHandle.WaitOne(2000, $false) -and $client.Connected
        $client.Close(); $client.Dispose()
    }
    catch {}

    # ── STUFE 2 – Service-Status via PowerShell Remoting ─────────────────────
    $dienstLaeuft   = $false
    $remotingOK     = $false
    $remotingFehler = ""

    try {
        $sessionOpt    = New-PSSessionOption -OpenTimeout 8000 -OperationTimeout 20000
        $sessionParams = @{
            ComputerName  = $IP
            SessionOption = $sessionOpt
            ErrorAction   = "Stop"
        }
        if ($WinPassSecure) {
            $sessionParams.Credential = New-Object System.Management.Automation.PSCredential($WinUser, $WinPassSecure)
        }
        $session    = New-PSSession @sessionParams
        $remotingOK = $true

        $dienstResult = Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
            Get-Service | Where-Object { $_.DisplayName -like "*MailStore*" -or $_.Name -like "*MailStore*" } |
                Select-Object DisplayName, Name, Status
        }
        if ($dienstResult) {
            $dienstLaeuft = ($dienstResult | Where-Object { $_.Status -eq "Running" }).Count -gt 0
        }
        Remove-PSSession $session -ErrorAction SilentlyContinue
    }
    catch {
        $remotingFehler = $_.Exception.Message
    }

    # ── STUFE 3 – MailStore Administration API (HTTP POST, Port 8463) ────────
    # Datumsformat: yyyy-MM-ddTHH:mm:ss (kein Timezone-Suffix, kein Locale-Trennzeichen)
    $apiVerfuegbar = $false
    $archivGesamt  = 0
    $jobs          = @()
    $kritischeJobs = @()
    $apiHinweis    = ""

    if ($passwort -ne "") {
        try {
            $baseUrl = "https://${IP}:${ApiPort}/api/invoke"
            $authB64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${User}:${passwort}"))
            $headers = @{ Authorization = "Basic $authB64" }

            function Invoke-MailstoreAPI {
                param([string]$Url, [hashtable]$Headers, [string]$Body = "")
                $p = @{
                    Uri                  = $Url
                    Method               = "POST"
                    Headers              = $Headers
                    SkipCertificateCheck = $true
                    TimeoutSec           = 15
                    ErrorAction          = "Stop"
                }
                if ($Body) {
                    $p.Body        = $Body
                    $p.ContentType = "application/x-www-form-urlencoded"
                }
                $raw = Invoke-RestMethod @p
                # MailStore sendet UTF-8 BOM – muss vor ConvertFrom-Json entfernt werden
                if ($raw -is [string]) {
                    return $raw.TrimStart([char]0xFEFF) | ConvertFrom-Json
                }
                return $raw
            }

            # GetServerInfo
            $siResp = Invoke-MailstoreAPI -Url "$baseUrl/GetServerInfo" -Headers $headers
            if ($siResp.statusCode -eq "succeeded") {
                $apiVerfuegbar = $true
                $dienstLaeuft  = $true

                # GetJobs – Namen der Jobs laden
                $jobNamen = @{}
                $gjResp = Invoke-MailstoreAPI -Url "$baseUrl/GetJobs" -Headers $headers
                if ($gjResp.statusCode -eq "succeeded" -and $gjResp.result) {
                    foreach ($j in $gjResp.result) {
                        $jobNamen[[string]$j.id] = $j.name
                    }
                }

                # GetJobResults – letzte 24 Stunden
                $von = (Get-Date).AddHours(-24).ToString("yyyy-MM-ddTHH:mm:ss")
                $bis = (Get-Date).AddDays(1).ToString("yyyy-MM-ddTHH:mm:ss")
                $body = "fromIncluding=$([Uri]::EscapeDataString($von))" +
                        "&toExcluding=$([Uri]::EscapeDataString($bis))" +
                        "&timeZoneId=$([Uri]::EscapeDataString('W. Europe Standard Time'))"

                $jrResp = Invoke-MailstoreAPI -Url "$baseUrl/GetJobResults" -Headers $headers -Body $body

                if ($jrResp.statusCode -eq "succeeded" -and $jrResp.result) {
                    # Pro Job nur das neueste Ergebnis auswerten
                    $neuesteProJob = @{}
                    foreach ($jr in $jrResp.result) {
                        $jid = [string]$jr.jobId
                        if (-not $neuesteProJob.ContainsKey($jid)) {
                            $neuesteProJob[$jid] = $jr
                        }
                    }

                    foreach ($jr in $neuesteProJob.Values) {
                        $jid     = [string]$jr.jobId
                        $name    = if ($jobNamen.ContainsKey($jid)) { $jobNamen[$jid] } else { "Job #$jid" }
                        $status  = $jr.result   # succeeded / failed / cancelled

                        $jobObj = [PSCustomObject]@{
                            Name     = $name
                            JobId    = $jr.jobId
                            Status   = $status
                            Start    = $jr.startTime
                            Ende     = $jr.completeTime
                        }
                        $jobs += $jobObj

                        if ($status -eq "failed") {
                            $kritischeJobs += $jobObj
                        }
                    }
                }
            }
            elseif ($siResp.error) {
                $apiHinweis = "API-Fehler: $($siResp.error.message)"
            }
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg -match "refused|connect|unable") {
                $apiHinweis = "API nicht erreichbar – Port $ApiPort offen? API in Service-Config aktiviert?"
            }
            elseif ($msg -match "401|Unauthorized") {
                $apiHinweis = "API: Authentifizierung fehlgeschlagen – Passwort pruefen"
            }
            else {
                $apiHinweis = "API-Fehler: $msg"
            }
        }
    }

    $passwort = $null

    # ── Gesamtstatus ─────────────────────────────────────────────────────────
    $gesamtStatus = if (-not $vmErreichbar)                        { "FEHLER"  }
                    elseif ($remotingOK -and -not $dienstLaeuft)   { "FEHLER"  }
                    elseif ($kritischeJobs.Count -gt 0)            { "WARNUNG" }
                    else                                           { "OK"      }

    $infoTeile = @()
    $infoTeile += "VM: OK"
    $infoTeile += "RDP: $(if ($rdpOffen) { 'offen' } else { 'zu' })"

    if ($remotingOK) {
        $infoTeile += "Remoting: OK | Dienst: $(if ($dienstLaeuft) { 'Running' } else { 'GESTOPPT!' })"
    }
    else {
        $infoTeile += "Remoting: n.v.$(if ($remotingFehler) { " ($remotingFehler)" })"
    }

    if ($apiVerfuegbar) {
        $cancelled = ($jobs | Where-Object { $_.Status -eq "cancelled" }).Count
        $infoTeile += "API: OK | $($jobs.Count) Jobs (24h)"
        if ($kritischeJobs.Count -gt 0) { $infoTeile += "$($kritischeJobs.Count) FEHLGESCHLAGEN!" }
        if ($cancelled -gt 0)           { $infoTeile += "$cancelled abgebrochen" }
    }
    elseif ($apiHinweis) {
        $infoTeile += $apiHinweis
    }

    $startzeit.Stop()

    return [PSCustomObject]@{
        Status         = $gesamtStatus
        VM_Erreichbar  = $vmErreichbar
        RDP_Offen      = $rdpOffen
        Remoting_OK    = $remotingOK
        Dienst_Laeuft  = $dienstLaeuft
        API_Verfuegbar = $apiVerfuegbar
        Fehler_Jobs    = $kritischeJobs.Count
        Archiv_Gesamt  = $archivGesamt
        Jobs           = $jobs
        Kritische_Jobs = $kritischeJobs
        Antwortzeit_ms = $startzeit.ElapsedMilliseconds
        Info           = $infoTeile -join " | "
    }
}
