function Check-MailstoreAPI {
    param(
        [string]$IP                                       = "192.168.80.120",
        [string]$User                                     = "admin",
        [System.Security.SecureString]$PassSecure         = $null
    )

    $startzeit = [System.Diagnostics.Stopwatch]::StartNew()

    # Passwort entschlüsseln (für Mailstore CLI Wrapper – Stufe 3)
    $passwort = ""
    if ($PassSecure) {
        $bstr     = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PassSecure)
        $passwort = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }

    # ── STUFE 1 – Ping + RDP-Port (immer verfügbar) ──────────────────────────
    $vmErreichbar = $false
    try {
        Test-Connection -ComputerName $IP -Count 1 -TimeoutSeconds 2 -ErrorAction Stop | Out-Null
        $vmErreichbar = $true
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
        $client = New-Object System.Net.Sockets.TcpClient
        $ar     = $client.BeginConnect($IP, 3389, $null, $null)
        $rdpOffen = $ar.AsyncWaitHandle.WaitOne(2000, $false) -and $client.Connected
        $client.Close(); $client.Dispose()
    }
    catch {}

    # ── STUFE 2 – Service-Status via PowerShell Remoting ─────────────────────
    $dienstLaeuft   = $false
    $remotingOK     = $false
    $apiVerfuegbar  = $false
    $archivGesamt   = 0
    $jobs           = @()
    $kritischeJobs  = @()
    $remotingFehler = ""

    try {
        $sessionOpt = New-PSSessionOption -OpenTimeout 8000 -OperationTimeout 20000
        $session    = New-PSSession -ComputerName $IP -SessionOption $sessionOpt -ErrorAction Stop

        $remotingOK = $true

        # Dienst-Status prüfen
        $dienstResult = Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
            Get-Service | Where-Object { $_.DisplayName -like "*MailStore*" -or $_.Name -like "*MailStore*" } |
                Select-Object DisplayName, Name, Status
        }

        if ($dienstResult) {
            $dienstLaeuft = ($dienstResult | Where-Object { $_.Status -eq "Running" }).Count -gt 0
        }

        # ── STUFE 3 – Mailstore CLI Wrapper (optional) ────────────────────────
        if ($dienstLaeuft -and $passwort -ne "") {
            $wrapperResult = Invoke-Command -Session $session -ArgumentList $User, $passwort -ErrorAction SilentlyContinue -ScriptBlock {
                param($msUser, $msPass)

                # Wrapper-Pfad suchen
                $suchPfade = @(
                    "C:\Program Files (x86)\deepinvent\MailStore Server\administration\MS.PS.Lib.psd1",
                    "C:\Program Files\deepinvent\MailStore Server\administration\MS.PS.Lib.psd1",
                    "C:\MailStore Server Scripting Tutorial\MS.PS.Lib.psd1"
                )
                $wrapperPfad = $null
                foreach ($p in $suchPfade) {
                    if (Test-Path $p) { $wrapperPfad = $p; break }
                }
                if (-not $wrapperPfad) {
                    $gefunden = Get-ChildItem "C:\Program Files*" -Recurse -Filter "MS.PS.Lib.psd1" `
                        -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($gefunden) { $wrapperPfad = $gefunden.FullName }
                }

                if (-not $wrapperPfad) {
                    return @{ apiVerfuegbar = $false; hinweis = "Mailstore PS-Wrapper nicht gefunden" }
                }

                try {
                    Import-Module $wrapperPfad -ErrorAction Stop
                    Connect-MSApiSession -ServerName "localhost" -UserName $msUser -Password $msPass -ErrorAction Stop | Out-Null

                    # Server-Info
                    $serverInfo = Invoke-MSApiCall "GetServerInfo" -ErrorAction SilentlyContinue

                    # Job-Ergebnisse der letzten 24 Stunden
                    $seit = (Get-Date).AddDours(-24).ToString("o")
                    $jobErgebnisse = Invoke-MSApiCall "GetJobResults" `
                        -Arguments @{ fromIncluding = $seit } -ErrorAction SilentlyContinue

                    return @{
                        apiVerfuegbar  = $true
                        serverInfo     = $serverInfo
                        jobErgebnisse  = $jobErgebnisse
                    }
                }
                catch {
                    return @{ apiVerfuegbar = $false; hinweis = "API-Aufruf fehlgeschlagen: $($_.Exception.Message)" }
                }
            }

            if ($wrapperResult -and $wrapperResult.apiVerfuegbar) {
                $apiVerfuegbar = $true

                # Archiv-Größe aus ServerInfo
                if ($wrapperResult.serverInfo -and $wrapperResult.serverInfo.result) {
                    $si = $wrapperResult.serverInfo.result
                    if ($si.numMessages -ne $null) { $archivGesamt = [int]$si.numMessages }
                }

                # ── STUFE 4 – Bekannte Fehler-Jobs auswerten ─────────────────
                $bekannteProbleme = @(
                    "andrearosbach27@gmail",   # Gmail OAuth2
                    "Andrea_IMAP_IONOS",       # unverschlüsselt
                    "Armin_FEP_Exchange"       # unverschlüsselt
                )

                if ($wrapperResult.jobErgebnisse -and $wrapperResult.jobErgebnisse.result) {
                    foreach ($job in $wrapperResult.jobErgebnisse.result) {
                        $jobName   = if ($job.name)        { $job.name }        else { "Unbekannt" }
                        $jobStatus = if ($job.result)      { $job.result }      else { "n/a" }
                        $fehler    = if ($job.numErrors    -ne $null) { [int]$job.numErrors    } else { 0 }
                        $warnungen = if ($job.numWarnings  -ne $null) { [int]$job.numWarnings  } else { 0 }

                        $istBekannt = $bekannteProbleme | Where-Object { $jobName -match $_ }

                        $jobObj = [PSCustomObject]@{
                            Name      = $jobName
                            Status    = $jobStatus
                            Fehler    = $fehler
                            Warnungen = $warnungen
                            Bekannt   = ($null -ne $istBekannt)
                        }
                        $jobs += $jobObj

                        if ($fehler -gt 0 -or $jobStatus -eq "failed") {
                            $kritischeJobs += $jobObj
                        }
                    }
                }
            }
        }

        Remove-PSSession $session -ErrorAction SilentlyContinue
    }
    catch {
        $remotingFehler = $_.Exception.Message
        # PowerShell Remoting nicht verfügbar – das ist akzeptabel
    }
    finally {
        $passwort = $null
    }

    # ── Gesamtstatus ermitteln ────────────────────────────────────────────────
    $gesamtStatus = if (-not $vmErreichbar)   { "FEHLER"  }
                    elseif (-not $dienstLaeuft -and $remotingOK) { "FEHLER"  }
                    elseif ($kritischeJobs.Count -gt 0) {
                        # Nur echte (unbekannte) Fehler → WARNUNG
                        $echte = $kritischeJobs | Where-Object { -not $_.Bekannt }
                        if ($echte.Count -gt 0) { "WARNUNG" } else { "OK" }
                    }
                    else { "OK" }

    # Info-Text aufbauen
    $infoTeile = @()
    $infoTeile += "VM: $(if ($vmErreichbar) { 'OK' } else { 'FEHLER' })"
    $infoTeile += "RDP: $(if ($rdpOffen) { 'OFFEN' } else { 'zu' })"
    if ($remotingOK) {
        $infoTeile += "Remoting: OK"
        $infoTeile += "Dienst: $(if ($dienstLaeuft) { 'Running' } else { 'GESTOPPT!' })"
    }
    else {
        $infoTeile += "Remoting: n.v.$(if ($remotingFehler) { " ($remotingFehler)" })"
    }
    if ($apiVerfuegbar) {
        $infoTeile += "API: OK"
        if ($archivGesamt -gt 0) { $infoTeile += "Archiv: $archivGesamt Nachrichten" }
        if ($kritischeJobs.Count -gt 0) {
            $echte = ($kritischeJobs | Where-Object { -not $_.Bekannt }).Count
            $bekannt = ($kritischeJobs | Where-Object { $_.Bekannt }).Count
            if ($echte -gt 0)   { $infoTeile += "$echte neue Fehler-Jobs!" }
            if ($bekannt -gt 0) { $infoTeile += "$bekannt bekannte Fehler (Gmail/IONOS)" }
        }
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
