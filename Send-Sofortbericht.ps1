#Requires -Version 5.1
Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$StartZeit  = Get-Date
$SkriptPfad = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPfad = Join-Path $SkriptPfad "config.json"
$CredPfad   = Join-Path $SkriptPfad "credentials.json"
$ModulPfad  = Join-Path $SkriptPfad "modules"

# ── Config ───────────────────────────────────────────────────────────────────
if (-not (Test-Path $ConfigPfad)) { Write-Host "FEHLER: config.json fehlt." -ForegroundColor Red; exit 1 }
$Config = Get-Content $ConfigPfad -Raw -Encoding UTF8 | ConvertFrom-Json

# ── Credentials ──────────────────────────────────────────────────────────────
if (-not (Test-Path $CredPfad)) { Write-Host "FEHLER: credentials.json fehlt. Bitte Setup-Credentials.ps1 ausfuehren." -ForegroundColor Red; exit 1 }
$credRaw = Get-Content $CredPfad -Raw -Encoding UTF8 | ConvertFrom-Json

function ConvertTo-SecureStringSafe {
    param([string]$Wert)
    if ($Wert -and $Wert.Length -gt 10) { return ($Wert | ConvertTo-SecureString) }
    return $null
}

$Creds = [PSCustomObject]@{
    SmtpPass         = (ConvertTo-SecureStringSafe $credRaw.smtp_pass)
    PiholePass       = (ConvertTo-SecureStringSafe $credRaw.pihole_pass)
    NAS1Pass         = (ConvertTo-SecureStringSafe $credRaw.nas1_pass)
    NAS2Pass         = (ConvertTo-SecureStringSafe $credRaw.nas2_pass)
    MailstorePass    = (ConvertTo-SecureStringSafe $credRaw.mailstore_pass)
    MailstoreWinPass = (ConvertTo-SecureStringSafe $credRaw.mailstore_win_pass)
    ReolinkPass      = (ConvertTo-SecureStringSafe $credRaw.reolink_pass)
    InstarPass       = (ConvertTo-SecureStringSafe $credRaw.instar_pass)
}

if (-not $Creds.SmtpPass) {
    Write-Host "FEHLER: SMTP-Passwort fehlt – E-Mail kann nicht versendet werden." -ForegroundColor Red
    exit 1
}

# ── Module laden ─────────────────────────────────────────────────────────────
Get-ChildItem -Path $ModulPfad -Filter "*.ps1" | ForEach-Object { . $_.FullName }

$FfprobePfad       = $Config.einstellungen.ffprobe_pfad
$FfprobeVerfuegbar = Test-Path $FfprobePfad

# ── Checks ───────────────────────────────────────────────────────────────────
$GeraeteListe = $Config.geraete | Where-Object { $_.aktiv -eq $true }
$AlleErgebnisse = @()

Clear-Host
Write-Host ""
Write-Host "  Sofortbericht – $($StartZeit.ToString('dd.MM.yyyy HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "  $($GeraeteListe.Count) Geraete werden geprueft..." -ForegroundColor Gray
Write-Host ""

foreach ($G in $GeraeteListe) {
    $zeitNow     = (Get-Date).ToString("HH:mm:ss")
    $checkStatus = "OK"
    $checkInfo   = ""
    $details     = $null

    try {
        $pingResult = $null
        if ($G.checks -contains "ping" -and $G.ip -ne "SPAETER_NACHTRAGEN" -and $G.ip -ne "SPAETER_NACHTRAGEN") {
            $pingResult = Check-Ping -IP $G.ip -TimeoutMs $Config.einstellungen.ping_timeout_ms
            if ($pingResult.Status -eq "FEHLER") { $checkStatus = "FEHLER"; $checkInfo = "Kein Ping" }
        }
        $latenz = if ($pingResult) { "$($pingResult.Latenz_ms)ms" } else { "n/a" }

        switch ($G.typ) {
            "router" {
                $portCheck = Check-Port -IP $G.ip -Port 80 -TimeoutMs $Config.einstellungen.port_timeout_ms
                $checkInfo = "HTTP/:80 $($portCheck.Status)"
            }
            "raspberry" {
                if ($G.checks -contains "ssh" -and $checkStatus -ne "FEHLER") {
                    $sshResult = Check-SSH -IP $G.ip -Port $G.ssh_port -User $G.ssh_user
                    $details   = $sshResult
                    if ($sshResult.Status -eq "FEHLER") { $checkStatus = "WARNUNG" }
                }
                $checkInfo = "SSH/:$($G.ssh_port) $(if ($sshResult -and $sshResult.Status -eq 'OK') { 'OK' } else { 'FEHLER' })"
                if ($G.checks -contains "pihole_api") {
                    $piholeResult = Check-PiholeAPI -IP $G.ip -PassSecure $Creds.PiholePass
                    if ($piholeResult.Status -eq "FEHLER" -and $checkStatus -eq "OK") { $checkStatus = "WARNUNG" }
                    $checkInfo += " | Pi-hole/:80 $($piholeResult.Status) ($($piholeResult.Blockierrate))"
                    $details = $piholeResult
                }
                if ($G.checks -contains "ntopng_api") {
                    $ntopResult = Check-NtopngAPI -IP $G.ip
                    if ($ntopResult.Status -eq "FEHLER" -and $checkStatus -eq "OK") { $checkStatus = "WARNUNG" }
                    $checkInfo += " | ntopng/:3000 $($ntopResult.Status)"
                }
            }
            "nas_synology" {
                if ($checkStatus -ne "FEHLER") {
                    $nasResult = Check-SynologyAPI -IP $G.ip -Port $G.ssh_port -User $G.ssh_user
                    $details   = $nasResult
                    if ($nasResult.Status -eq "FEHLER")  { $checkStatus = "FEHLER"  }
                    if ($nasResult.Status -eq "WARNUNG") { $checkStatus = "WARNUNG" }
                    $checkInfo = "SSH/:$($G.ssh_port) | $($nasResult.Info)"
                }
                if ($G.docker -eq $true -and $checkStatus -ne "FEHLER") {
                    $dContainers = if ($G.docker_containers) { $G.docker_containers } else { @() }
                    $dPort       = if ($G.docker_port)       { [int]$G.docker_port }  else { 3000 }
                    $dApp        = if ($G.docker_pfad)       { Split-Path $G.docker_pfad -Leaf } else { "docker" }
                    $dockerResult = Check-Docker -IP $G.ip -SSHPort $G.ssh_port -SSHUser $G.ssh_user -Containers $dContainers -DockerPort $dPort -AppName $dApp
                    if ($dockerResult.Status -ne "OK" -and $checkStatus -eq "OK") { $checkStatus = "WARNUNG" }
                    $checkInfo += " | $($dockerResult.Info)"
                    if ($details) { Add-Member -InputObject $details -MemberType NoteProperty -Name "Docker" -Value $dockerResult -Force }
                }
            }
            "windows_host" {
                $rdpResult = Check-Port -IP $G.ip -Port 3389 -TimeoutMs $Config.einstellungen.port_timeout_ms
                $checkInfo = "RDP/:3389 $($rdpResult.Status)"
                if ($rdpResult.Status -eq "GESCHLOSSEN" -and $checkStatus -eq "OK") { $checkStatus = "WARNUNG" }
            }
            "mailstore" {
                $msResult  = Check-MailstoreAPI -IP $G.ip -User "admin" -PassSecure $Creds.MailstorePass -WinPassSecure $Creds.MailstoreWinPass
                $details   = $msResult
                if ($msResult.Status -ne "OK") { $checkStatus = $msResult.Status }
                $checkInfo = $msResult.Info
            }
            "sma_homemanager" {
                $smaResult = Check-SMA -IP $G.ip -SpeedwirePort $G.speedwire_port
                $details   = $smaResult
                if ($smaResult.Status -eq "FEHLER") { $checkStatus = "FEHLER" }
                $checkInfo = "HTTP/:80 $(if ($smaResult.Status -eq 'OK') { 'OK' } else { 'FEHLER' }) | Speedwire/UDP:$($G.speedwire_port)"
            }
            "elwa_heizstab" {
                $elwaResult = Check-ELWA -IP $G.ip -TempMax $G.temp_max
                $details    = $elwaResult
                if ($elwaResult.Status -eq "WARNUNG") { $checkStatus = "WARNUNG" }
                if ($elwaResult.Status -eq "FEHLER")  { $checkStatus = "FEHLER"  }
                $checkInfo  = "HTTP/:80 | Temp: $($elwaResult.Temperatur) | Leistung: $($elwaResult.Leistung_W)"
            }
            "powerline_fritzbox" {
                $plResult  = Check-Powerline -IP $G.ip
                $details   = $plResult
                if ($plResult.Status -ne "OK") { $checkStatus = $plResult.Status }
                $checkInfo = "HTTP/:80 $(if ($plResult.HTTP_Erreichbar) { 'OK' } else { 'FEHLER' })"
            }
            { $_ -in @("kamera_reolink","kamera_instar") } {
                $kamTyp  = if ($G.typ -eq "kamera_reolink") { "reolink" } else { "instar" }
                $kamPass = if ($G.typ -eq "kamera_reolink") { $Creds.ReolinkPass } else { $Creds.InstarPass }
                $httpP   = if ($G.http_port) { [int]$G.http_port } else { if ($kamTyp -eq "reolink") { 80 } else { 8080 } }
                $kamResult = Check-Camera -IP $G.ip -Typ $kamTyp -HttpPort $httpP `
                    -RtspUrl $G.rtsp_url -FfprobePfad $FfprobePfad -Name $G.name `
                    -ReolinkPassSecure $kamPass
                $details   = $kamResult
                if ($kamResult.Status -ne "OK") { $checkStatus = $kamResult.Status }
                $checkInfo = $kamResult.Info
            }
        }
    }
    catch {
        $checkStatus = "FEHLER"
        $checkInfo   = "Ausnahme: $($_.Exception.Message)"
    }

    # Latenz farblich bewerten
    $latFarbe = "Gray"
    $latLabel = "n/a    "
    if ($latenz -ne "n/a") {
        $ms = 0
        [int]::TryParse(($latenz -replace 'ms','').Trim(), [ref]$ms) | Out-Null
        if     ($ms -le 2)  { $latFarbe = "Green";  $latLabel = "$($latenz.PadLeft(5)) LAN    " }
        elseif ($ms -le 10) { $latFarbe = "Green";  $latLabel = "$($latenz.PadLeft(5)) gut    " }
        elseif ($ms -le 30) { $latFarbe = "Yellow"; $latLabel = "$($latenz.PadLeft(5)) traege " }
        else                { $latFarbe = "Red";    $latLabel = "$($latenz.PadLeft(5)) LANGSAM" }
    }

    $statusFarbe = switch ($checkStatus) { "OK" { "Green" } "WARNUNG" { "Yellow" } default { "Red" } }
    $statusPad   = $checkStatus.PadRight(7)
    Write-Host "  $($G.name.PadRight(26)) $($G.ip.PadRight(16))" -NoNewline
    Write-Host $latLabel -ForegroundColor $latFarbe -NoNewline
    Write-Host "  $statusPad  " -ForegroundColor $statusFarbe -NoNewline
    Write-Host $checkInfo

    $AlleErgebnisse += [PSCustomObject]@{
        Geraet      = $G.name
        IP          = $G.ip
        Typ         = $G.typ
        CheckStatus = $checkStatus
        Latenz      = $latenz
        Info        = $checkInfo
        Details     = $details
        Zeitstempel = $zeitNow
    }
}

# ── Externe Logins ───────────────────────────────────────────────────────────
Write-Host "  Pruefe externe Zugriffe..." -ForegroundColor Gray
$LoginResult = $null
try { $LoginResult = Check-ExternalLogins } catch {}

$AnzahlOK     = ($AlleErgebnisse | Where-Object { $_.CheckStatus -eq "OK"      }).Count
$AnzahlWarn   = ($AlleErgebnisse | Where-Object { $_.CheckStatus -eq "WARNUNG" }).Count
$AnzahlFehler = ($AlleErgebnisse | Where-Object { $_.CheckStatus -eq "FEHLER"  }).Count
$LaufzeitSek  = [Math]::Round(((Get-Date) - $StartZeit).TotalSeconds, 1)

Write-Host ""
Write-Host "  OK: $AnzahlOK  |  Warnungen: $AnzahlWarn  |  Fehler: $AnzahlFehler  |  Laufzeit: $($LaufzeitSek)s" -ForegroundColor Cyan
Write-Host ""

# ── E-Mail senden ─────────────────────────────────────────────────────────────
Write-Host "  Sende Sofortbericht per E-Mail..." -ForegroundColor Cyan

$zeitstempel = $StartZeit.ToString("dd.MM.yyyy HH:mm:ss")
$smtp        = $Config.einstellungen

$gesamtStatus = if ($AnzahlFehler -gt 0) { "FEHLER" } elseif ($AnzahlWarn -gt 0) { "WARNUNG" } else { "OK" }
$bannerFarbe  = switch ($gesamtStatus) { "FEHLER" { "#f85149" } "WARNUNG" { "#d29922" } default { "#3fb950" } }
$bannerText   = switch ($gesamtStatus) {
    "FEHLER"  { "ALARM – $AnzahlFehler Fehler erkannt!" }
    "WARNUNG" { "ACHTUNG – $AnzahlWarn Warnungen" }
    default   { "Alles OK – Alle $AnzahlOK Geraete erreichbar" }
}

# Kamera-Snapshots sammeln
$snapshotHtml = ""
$kameras = $AlleErgebnisse | Where-Object { $_.Typ -in @("kamera_reolink","kamera_instar") }
$kamsWithSnap = $kameras | Where-Object { $_.Details -and $_.Details.Snapshot_B64 }
if ($kamsWithSnap.Count -gt 0) {
    $snapBlocks = ""
    foreach ($k in $kamsWithSnap) {
        $statusFarbe = switch ($k.CheckStatus) { "FEHLER" { "#f85149" } "WARNUNG" { "#d29922" } default { "#3fb950" } }
        $streamText  = if ($k.Details.Stream_Info) { $k.Details.Stream_Info } else { "" }
        $snapBlocks += @"
      <div style='display:inline-block;vertical-align:top;margin:6px;background:#161b22;border:1px solid #30363d;border-radius:6px;padding:8px;width:260px;'>
        <div style='font-size:0.85em;font-weight:600;margin-bottom:4px;color:#e6edf3;'>$($k.Geraet)</div>
        <div style='font-size:0.78em;color:#8b949e;margin-bottom:6px;font-family:monospace;'>$($k.IP) &nbsp;<span style='color:$statusFarbe;'>$($k.CheckStatus)</span></div>
        <img src='data:image/jpeg;base64,$($k.Details.Snapshot_B64)' style='width:100%;border-radius:4px;display:block;' alt='$($k.Geraet)'>
        <div style='font-size:0.78em;color:#8b949e;margin-top:4px;'>$streamText</div>
      </div>
"@
    }
    $snapshotHtml = @"
    <h3 style='color:#58a6ff;margin-top:24px;margin-bottom:8px;font-size:1em;'>Kamera-Snapshots ($($kamsWithSnap.Count)/$($kameras.Count))</h3>
    <div style='background:#0d1117;border:1px solid #30363d;border-radius:6px;padding:10px;'>
      $snapBlocks
    </div>
"@
}

$tabellenZeilen = ""
foreach ($e in $AlleErgebnisse) {
    $statusFarbe = switch ($e.CheckStatus) { "FEHLER" { "#f85149" } "WARNUNG" { "#d29922" } default { "#3fb950" } }
    $zeileBg     = switch ($e.CheckStatus) { "FEHLER" { "#1a0a0a" } "WARNUNG" { "#1a1400" } default { "" } }
    $bgStyle     = if ($zeileBg) { "background:$zeileBg;" } else { "" }

    # Latenz Farbe + Bewertung
    $latFarbe = "#8b949e"
    $latText  = if ($e.Latenz -and $e.Latenz -ne "n/a") { $e.Latenz } else { "n/a" }
    $latLabel = ""
    if ($e.Latenz -and $e.Latenz -ne "n/a") {
        $ms = 0
        [int]::TryParse(($e.Latenz -replace 'ms','').Trim(), [ref]$ms) | Out-Null
        if     ($ms -le 2)  { $latFarbe = "#3fb950"; $latLabel = "LAN"     }
        elseif ($ms -le 10) { $latFarbe = "#3fb950"; $latLabel = "gut"     }
        elseif ($ms -le 30) { $latFarbe = "#d29922"; $latLabel = "traege"  }
        else                { $latFarbe = "#f85149"; $latLabel = "LANGSAM" }
    }
    $latAnzeige = if ($latLabel) { "$latText <span style='font-size:0.8em;'>$latLabel</span>" } else { $latText }

    $tabellenZeilen += @"
        <tr style='${bgStyle}border-bottom:1px solid #21262d;'>
          <td style='padding:7px 10px;font-weight:500;'>$($e.Geraet)</td>
          <td style='padding:7px 10px;font-family:monospace;font-size:0.88em;color:#8b949e;'>$($e.IP)</td>
          <td style='padding:7px 10px;font-family:monospace;font-size:0.88em;color:$latFarbe;white-space:nowrap;'>$latAnzeige</td>
          <td style='padding:7px 10px;color:$statusFarbe;font-weight:bold;'>$($e.CheckStatus)</td>
          <td style='padding:7px 10px;font-size:0.88em;color:#c9d1d9;font-family:monospace;'>$($e.Info)</td>
        </tr>
"@
}

# Login-Sektion aufbauen
$loginSektionHtml = ""
if ($LoginResult) {
    $loginStatusFarbe = if ($LoginResult.Warnung) { "#f85149" } else { "#3fb950" }
    $loginZeilenHtml  = ""
    foreach ($eintrag in $LoginResult.Eintraege) {
        $eFarbe = switch -Regex ($eintrag.Ergebnis) {
            "Fehlversuch" { "#f85149" }
            "Erfolg"      { "#3fb950" }
            default       { "#8b949e" }
        }
        $loginZeilenHtml += "<tr><td style='padding:5px 8px;font-size:0.82em;color:#8b949e;border-bottom:1px solid #21262d;'>$($eintrag.Zeitstempel)</td><td style='padding:5px 8px;font-size:0.82em;font-family:monospace;border-bottom:1px solid #21262d;'>$($eintrag.QuellIP)</td><td style='padding:5px 8px;font-size:0.82em;border-bottom:1px solid #21262d;'>$($eintrag.Zielgeraet)</td><td style='padding:5px 8px;font-size:0.82em;color:$eFarbe;border-bottom:1px solid #21262d;'>$($eintrag.Ergebnis)</td></tr>"
    }
    $loginSektionHtml = @"
    <h3 style='color:#58a6ff;margin-top:24px;margin-bottom:8px;font-size:1em;'>Externe Zugriffe – Letzte 24h</h3>
    <p style='color:$loginStatusFarbe;font-size:0.88em;margin-bottom:8px;'>$($LoginResult.Info)</p>
    <table style='width:100%;border-collapse:collapse;background:#161b22;border-radius:6px;overflow:hidden;font-size:0.85em;'>
      <thead><tr style='background:#21262d;'><th style='padding:6px 8px;text-align:left;color:#8b949e;'>Zeit</th><th style='padding:6px 8px;text-align:left;color:#8b949e;'>Von IP</th><th style='padding:6px 8px;text-align:left;color:#8b949e;'>Zielgeraet</th><th style='padding:6px 8px;text-align:left;color:#8b949e;'>Ergebnis</th></tr></thead>
      <tbody>$loginZeilenHtml</tbody>
    </table>
"@
}

$body = @"
<!DOCTYPE html>
<html>
<head><meta charset='UTF-8'></head>
<body style='background:#0d1117;color:#e6edf3;font-family:Segoe UI,Arial,sans-serif;margin:0;padding:20px;'>
  <div style='max-width:820px;margin:0 auto;'>
    <h1 style='color:#58a6ff;margin-bottom:2px;font-size:1.4em;'>Heimnetz Monitor</h1>
    <p style='color:#8b949e;margin-top:0;font-size:0.9em;'>Sofortbericht – $zeitstempel | Laufzeit: $($LaufzeitSek)s</p>

    <div style='background:$bannerFarbe;color:#fff;padding:10px 16px;border-radius:6px;font-size:1.05em;font-weight:bold;margin-bottom:14px;'>
      $bannerText
    </div>

    <div style='display:flex;gap:16px;margin-bottom:18px;'>
      <div style='background:#161b22;border:1px solid #3fb950;border-radius:6px;padding:10px 18px;text-align:center;'>
        <div style='color:#3fb950;font-size:1.6em;font-weight:bold;'>$AnzahlOK</div>
        <div style='color:#8b949e;font-size:0.8em;'>OK</div>
      </div>
      <div style='background:#161b22;border:1px solid #d29922;border-radius:6px;padding:10px 18px;text-align:center;'>
        <div style='color:#d29922;font-size:1.6em;font-weight:bold;'>$AnzahlWarn</div>
        <div style='color:#8b949e;font-size:0.8em;'>Warnungen</div>
      </div>
      <div style='background:#161b22;border:1px solid #f85149;border-radius:6px;padding:10px 18px;text-align:center;'>
        <div style='color:#f85149;font-size:1.6em;font-weight:bold;'>$AnzahlFehler</div>
        <div style='color:#8b949e;font-size:0.8em;'>Fehler</div>
      </div>
    </div>

    <table style='width:100%;border-collapse:collapse;background:#161b22;border-radius:6px;overflow:hidden;font-size:0.92em;'>
      <thead>
        <tr style='background:#21262d;'>
          <th style='padding:8px 10px;text-align:left;color:#8b949e;font-weight:600;'>Geraet</th>
          <th style='padding:8px 10px;text-align:left;color:#8b949e;font-weight:600;'>IP</th>
          <th style='padding:8px 10px;text-align:left;color:#8b949e;font-weight:600;'>Ping</th>
          <th style='padding:8px 10px;text-align:left;color:#8b949e;font-weight:600;'>Status</th>
          <th style='padding:8px 10px;text-align:left;color:#8b949e;font-weight:600;'>Gepruefter Port / Info</th>
        </tr>
      </thead>
      <tbody>
        $tabellenZeilen
      </tbody>
    </table>

    $snapshotHtml
    $loginSektionHtml
    <p style='color:#8b949e;font-size:0.8em;margin-top:16px;'>
      Heimnetz Monitor v2.0 | $zeitstempel<br>
      Ping-Bewertung: <span style='color:#3fb950;'>LAN &le;2ms / gut &le;10ms</span> &nbsp;
      <span style='color:#d29922;'>traege &le;30ms</span> &nbsp;
      <span style='color:#f85149;'>LANGSAM &gt;30ms</span>
    </p>
  </div>
</body>
</html>
"@

try {
    $bstr     = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Creds.SmtpPass)
    $passKlar = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    $cred = New-Object System.Net.NetworkCredential($smtp.smtp_von, $passKlar)
    $passKlar = $null

    $smtpClient                   = New-Object System.Net.Mail.SmtpClient($smtp.smtp_host, $smtp.smtp_port)
    $smtpClient.EnableSsl         = $true
    $smtpClient.Credentials       = $cred
    $smtpClient.DeliveryMethod    = [System.Net.Mail.SmtpDeliveryMethod]::Network
    $smtpClient.Timeout           = 15000

    $mail                   = New-Object System.Net.Mail.MailMessage
    $mail.From              = $smtp.smtp_von
    $mail.To.Add($smtp.smtp_an)
    $mail.Subject           = "[Heimnetz Monitor] Sofortbericht $gesamtStatus – $zeitstempel"
    $mail.Body              = $body
    $mail.IsBodyHtml        = $true
    $mail.SubjectEncoding   = [System.Text.Encoding]::UTF8
    $mail.BodyEncoding      = [System.Text.Encoding]::UTF8

    $smtpClient.Send($mail)
    $mail.Dispose()
    $smtpClient.Dispose()

    Write-Host "  E-Mail gesendet an: $($smtp.smtp_an)" -ForegroundColor Green
    Write-Host "  Betreff: [Heimnetz Monitor] Sofortbericht $gesamtStatus – $zeitstempel" -ForegroundColor Gray
}
catch {
    Write-Host "  FEHLER beim E-Mail-Versand: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
