#Requires -Version 5.1
param([switch]$Test)

Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$SkriptPfad = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPfad = Join-Path $SkriptPfad "config.json"
$CredPfad   = Join-Path $SkriptPfad "credentials.json"
$ModulPfad  = Join-Path $SkriptPfad "modules"

if (-not (Test-Path $ConfigPfad)) { Write-Host "FEHLER: config.json fehlt." -ForegroundColor Red; exit 1 }
$Config = Get-Content $ConfigPfad -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not (Test-Path $CredPfad)) { Write-Host "FEHLER: credentials.json fehlt. Bitte Setup-Credentials.ps1 ausfuehren." -ForegroundColor Red; exit 1 }
$credRaw = Get-Content $CredPfad -Raw -Encoding UTF8 | ConvertFrom-Json

function ConvertTo-SecureStringSafe {
    param([string]$Wert)
    if ($Wert -and $Wert.Length -gt 10) { return ($Wert | ConvertTo-SecureString) }
    return $null
}

$Creds = [PSCustomObject]@{
    SmtpPass = (ConvertTo-SecureStringSafe $credRaw.smtp_pass)
}

if (-not $Test -and -not $Creds.SmtpPass) {
    Write-Host "FEHLER: SMTP-Passwort fehlt." -ForegroundColor Red; exit 1
}

Get-ChildItem -Path $ModulPfad -Filter "*.ps1" | ForEach-Object { . $_.FullName }

$smtp        = $Config.einstellungen
$jetzt       = Get-Date
$zeitstempel = $jetzt.ToString("dd.MM.yyyy HH:mm")

Write-Host ""
Write-Host "  Port-Report | $zeitstempel" -ForegroundColor Cyan
Write-Host ""

# ── Bekannte Ports je Geraet (gruen markiert) ─────────────────────────────────
$bekannteRaspberry = @(22, 53, 80, 443, 3000, 4711, 8080, 8089, 8888, 9090)
$bekannteNAS       = @(22, 80, 443, 5000, 5001, 5006, 6690, 7000, 8080, 9091, 22028)

# ── SSH-Abfragen ──────────────────────────────────────────────────────────────
Write-Host "  Raspberry Pi 5 (192.168.80.20)..." -ForegroundColor Gray
$rPi = Check-ListeningPorts -IP "192.168.80.20" -SSHPort 22 -SSHUser "pi" -Hostname "Raspberry Pi 5"
Write-Host "  $($rPi.Info)" -ForegroundColor $(if ($rPi.Status -eq 'OK') { 'Green' } else { 'Red' })

Write-Host "  DS1525+ (192.168.80.206)..." -ForegroundColor Gray
$rNas1 = Check-ListeningPorts -IP "192.168.80.206" -SSHPort 822 -SSHUser "Armin" -Hostname "DS1525+"
Write-Host "  $($rNas1.Info)" -ForegroundColor $(if ($rNas1.Status -eq 'OK') { 'Green' } else { 'Red' })

Write-Host "  DS723+ (192.168.80.207)..." -ForegroundColor Gray
$rNas2 = Check-ListeningPorts -IP "192.168.80.207" -SSHPort 822 -SSHUser "Armin" -Hostname "DS723+"
Write-Host "  $($rNas2.Info)" -ForegroundColor $(if ($rNas2.Status -eq 'OK') { 'Green' } else { 'Red' })

# ── SASCHA_SERVER TCP-Probe ───────────────────────────────────────────────────
Write-Host "  SASCHA_SERVER (192.168.80.87) TCP-Probe..." -ForegroundColor Gray

$windowsPorts = @(
    @{ Port=135;  Beschreibung="RPC Endpoint Mapper" },
    @{ Port=139;  Beschreibung="NetBIOS Session" },
    @{ Port=445;  Beschreibung="SMB / Dateifreigabe" },
    @{ Port=3389; Beschreibung="Remote Desktop (RDP)" },
    @{ Port=5985; Beschreibung="WinRM HTTP" },
    @{ Port=5986; Beschreibung="WinRM HTTPS" },
    @{ Port=80;   Beschreibung="HTTP" },
    @{ Port=443;  Beschreibung="HTTPS" },
    @{ Port=8080; Beschreibung="HTTP alternativ" },
    @{ Port=1433; Beschreibung="SQL Server" }
)

$saschaPing = (New-Object System.Net.NetworkInformation.Ping).Send("192.168.80.87", 1500).Status -eq 'Success'
$saschaPortErgebnisse = @()

if ($saschaPing) {
    foreach ($wp in $windowsPorts) {
        $offen = $false
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $ar     = $client.BeginConnect("192.168.80.87", $wp.Port, $null, $null)
            $offen  = $ar.AsyncWaitHandle.WaitOne(2000, $false) -and $client.Connected
            $client.Close(); $client.Dispose()
        } catch {}
        $saschaPortErgebnisse += [PSCustomObject]@{
            Port         = $wp.Port
            Beschreibung = $wp.Beschreibung
            Offen        = $offen
        }
    }
    $offeneAnzahl = ($saschaPortErgebnisse | Where-Object { $_.Offen }).Count
    Write-Host "  SASCHA_SERVER: $offeneAnzahl / $($windowsPorts.Count) Ports offen" -ForegroundColor Green
} else {
    Write-Host "  SASCHA_SERVER: kein Ping" -ForegroundColor Red
}

Write-Host ""

# ── HTML-Hilfsfunktion ─────────────────────────────────────────────────────────
function New-GeraetSektion {
    param(
        [object]$Ergebnis,
        [int[]]$BekanntePortListe
    )

    $hostname = $Ergebnis.Hostname
    $statusFarbe = if ($Ergebnis.Status -eq 'OK') { '#3fb950' } else { '#f85149' }
    $info        = $Ergebnis.Info

    if ($Ergebnis.Status -ne 'OK' -or $Ergebnis.Ports.Count -eq 0) {
        $tabelleHtml = "<p style='color:#8b949e;font-size:0.85em;'>$(if ($Ergebnis.Status -ne 'OK') { $info } else { 'Keine lauschenden Ports gefunden.' })</p>"
    } else {
        $zeilen = ""
        foreach ($p in $Ergebnis.Ports) {
            $portFarbe = if ($BekanntePortListe -contains $p.Port) { '#3fb950' } else { '#d29922' }
            $portFarbeHG = if ($BekanntePortListe -contains $p.Port) { 'rgba(63,185,80,0.08)' } else { 'rgba(210,153,34,0.08)' }
            $prozAnzeige = if ($p.Prozess) { $p.Prozess } else { '<span style="color:#484f58;">n/a</span>' }
            $adrAnzeige  = if ($p.Adresse -eq '0.0.0.0' -or $p.Adresse -eq '*' -or $p.Adresse -eq '::') { 'alle' } else { $p.Adresse }
            $zeilen += "<tr style='background:$portFarbeHG;'><td style='padding:5px 10px;font-family:monospace;font-weight:bold;color:$portFarbe;border-bottom:1px solid #21262d;'>$($p.Port)</td><td style='padding:5px 10px;font-family:monospace;font-size:0.85em;color:#8b949e;border-bottom:1px solid #21262d;'>$adrAnzeige</td><td style='padding:5px 10px;font-size:0.85em;color:#c9d1d9;border-bottom:1px solid #21262d;'>$prozAnzeige</td></tr>"
        }
        $unbekannt = ($Ergebnis.Ports | Where-Object { $BekanntePortListe -notcontains $_.Port }).Count
        $hinweis   = if ($unbekannt -gt 0) { " | <span style='color:#d29922;'>$unbekannt unbekannt</span>" } else { "" }
        $tabelleHtml = @"
<p style='color:#8b949e;font-size:0.82em;margin:0 0 8px 0;'>$($Ergebnis.Ports.Count) Ports$hinweis &nbsp; <span style='color:#3fb950;'>&#9632;</span> bekannt &nbsp; <span style='color:#d29922;'>&#9632;</span> unbekannt</p>
<table style='width:100%;border-collapse:collapse;background:#161b22;border-radius:6px;overflow:hidden;'>
  <thead><tr style='background:#21262d;'>
    <th style='padding:6px 10px;text-align:left;color:#8b949e;font-size:0.85em;font-weight:600;'>Port</th>
    <th style='padding:6px 10px;text-align:left;color:#8b949e;font-size:0.85em;font-weight:600;'>Adresse</th>
    <th style='padding:6px 10px;text-align:left;color:#8b949e;font-size:0.85em;font-weight:600;'>Prozess</th>
  </tr></thead>
  <tbody>$zeilen</tbody>
</table>
"@
    }

    return @"
<div style='margin-bottom:20px;'>
  <h3 style='color:#e6edf3;margin:0 0 4px 0;font-size:1em;'>$hostname <span style='color:$statusFarbe;font-size:0.8em;font-weight:normal;'>$($Ergebnis.Status)</span></h3>
  $tabelleHtml
</div>
"@
}

# ── HTML-Sektionen ─────────────────────────────────────────────────────────────
$sektionPi   = New-GeraetSektion -Ergebnis $rPi   -BekanntePortListe $bekannteRaspberry
$sektionNas1 = New-GeraetSektion -Ergebnis $rNas1 -BekanntePortListe $bekannteNAS
$sektionNas2 = New-GeraetSektion -Ergebnis $rNas2 -BekanntePortListe $bekannteNAS

# SASCHA_SERVER-Sektion
if (-not $saschaPing) {
    $saschaHtml = "<p style='color:#f85149;font-size:0.85em;'>Kein Ping - Server nicht erreichbar.</p>"
} else {
    $saschaZeilen = ""
    foreach ($p in $saschaPortErgebnisse) {
        $statusF = if ($p.Offen) { '#3fb950' } else { '#484f58' }
        $statusT = if ($p.Offen) { 'OFFEN' } else { 'geschlossen' }
        $zeileBg = if ($p.Offen) { 'rgba(63,185,80,0.06)' } else { '' }
        $saschaZeilen += "<tr style='background:$zeileBg;'><td style='padding:5px 10px;font-family:monospace;font-weight:bold;color:$statusF;border-bottom:1px solid #21262d;'>$($p.Port)</td><td style='padding:5px 10px;font-size:0.85em;color:#c9d1d9;border-bottom:1px solid #21262d;'>$($p.Beschreibung)</td><td style='padding:5px 10px;font-family:monospace;font-size:0.85em;color:$statusF;border-bottom:1px solid #21262d;'>$statusT</td></tr>"
    }
    $saschaHtml = @"
<table style='width:100%;border-collapse:collapse;background:#161b22;border-radius:6px;overflow:hidden;'>
  <thead><tr style='background:#21262d;'>
    <th style='padding:6px 10px;text-align:left;color:#8b949e;font-size:0.85em;font-weight:600;'>Port</th>
    <th style='padding:6px 10px;text-align:left;color:#8b949e;font-size:0.85em;font-weight:600;'>Dienst</th>
    <th style='padding:6px 10px;text-align:left;color:#8b949e;font-size:0.85em;font-weight:600;'>Status</th>
  </tr></thead>
  <tbody>$saschaZeilen</tbody>
</table>
"@
}

# ── HTML-Body ─────────────────────────────────────────────────────────────────
$body = @"
<!DOCTYPE html>
<html>
<head><meta charset='UTF-8'></head>
<body style='background:#0d1117;color:#e6edf3;font-family:Segoe UI,Arial,sans-serif;margin:0;padding:20px;'>
  <div style='max-width:820px;margin:0 auto;'>
    <div style='background:#1f6feb;color:#fff;padding:12px 16px;border-radius:6px;font-size:1.1em;font-weight:bold;margin-bottom:20px;'>
      Port-Report &ndash; $zeitstempel
    </div>

    <p style='color:#8b949e;font-size:0.85em;margin:0 0 18px 0;'>
      SSH-Abfrage (ss / netstat) auf Linux-Hosts &middot; TCP-Probe auf Windows-Host
    </p>

    <h2 style='color:#58a6ff;margin-bottom:14px;font-size:1.05em;border-bottom:1px solid #21262d;padding-bottom:6px;'>Linux / SSH</h2>
    $sektionPi
    $sektionNas1
    $sektionNas2

    <h2 style='color:#58a6ff;margin-top:24px;margin-bottom:14px;font-size:1.05em;border-bottom:1px solid #21262d;padding-bottom:6px;'>Windows &ndash; SASCHA_SERVER (192.168.80.87)</h2>
    <div style='margin-bottom:12px;'>
      <h3 style='color:#e6edf3;margin:0 0 8px 0;font-size:1em;'>TCP-Probe von aussen (kein SSH)</h3>
      $saschaHtml
    </div>

    <p style='color:#8b949e;font-size:0.8em;margin-top:20px;'>
      Heimnetz Monitor v2.0 | Port-Report | $zeitstempel
    </p>
  </div>
</body>
</html>
"@

# ── Ausgabe ────────────────────────────────────────────────────────────────────
if ($Test) {
    $tmpPfad = Join-Path $env:TEMP "PortReport_Test.html"
    $body | Out-File -FilePath $tmpPfad -Encoding UTF8
    Write-Host "  Test-Modus: HTML gespeichert unter $tmpPfad" -ForegroundColor Green
    Start-Process $tmpPfad
} else {
    Write-Host "  Sende Port-Report per E-Mail..." -ForegroundColor Cyan
    try {
        $bstr     = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Creds.SmtpPass)
        $passKlar = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        $cred = New-Object System.Net.NetworkCredential($smtp.smtp_von, $passKlar)
        $passKlar = $null

        $smtpClient                = New-Object System.Net.Mail.SmtpClient($smtp.smtp_host, $smtp.smtp_port)
        $smtpClient.EnableSsl      = $true
        $smtpClient.Credentials    = $cred
        $smtpClient.DeliveryMethod = [System.Net.Mail.SmtpDeliveryMethod]::Network
        $smtpClient.Timeout        = 15000

        $mail                 = New-Object System.Net.Mail.MailMessage
        $mail.From            = $smtp.smtp_von
        $mail.To.Add($smtp.smtp_an)
        $mail.Subject         = "[Heimnetz] Port-Report - $zeitstempel"
        $mail.Body            = $body
        $mail.IsBodyHtml      = $true
        $mail.SubjectEncoding = [System.Text.Encoding]::UTF8
        $mail.BodyEncoding    = [System.Text.Encoding]::UTF8

        $smtpClient.Send($mail)
        $mail.Dispose()
        $smtpClient.Dispose()

        Write-Host "  E-Mail gesendet an: $($smtp.smtp_an)" -ForegroundColor Green
        Write-Host "  Betreff: [Heimnetz] Port-Report - $zeitstempel" -ForegroundColor Gray
    }
    catch {
        Write-Host "  FEHLER beim E-Mail-Versand: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
