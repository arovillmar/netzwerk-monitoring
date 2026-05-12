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
    SmtpPass   = (ConvertTo-SecureStringSafe $credRaw.smtp_pass)
    PiholePass = (ConvertTo-SecureStringSafe $credRaw.pihole_pass)
    NtopngPass = (ConvertTo-SecureStringSafe $credRaw.ntopng_pass)
}

if (-not $Test -and -not $Creds.SmtpPass) {
    Write-Host "FEHLER: SMTP-Passwort fehlt." -ForegroundColor Red; exit 1
}

Get-ChildItem -Path $ModulPfad -Filter "*.ps1" | ForEach-Object { . $_.FullName }

$smtp = $Config.einstellungen

Write-Host ""
Write-Host "  Netzwerk-Analyse | $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')" -ForegroundColor Cyan
Write-Host ""

Write-Host "  Rufe Pi-hole Daten ab..." -ForegroundColor Gray
$piholeResult = Check-PiholeAPI -IP "192.168.80.20" -PassSecure $Creds.PiholePass -DetailModus
$phFarbe = if ($piholeResult.Status -eq 'OK') { 'Green' } elseif ($piholeResult.Status -eq 'WARNUNG') { 'Yellow' } else { 'Red' }
Write-Host "  Pi-hole: $($piholeResult.Status) | $($piholeResult.Blockierrate) blockiert | Domains: $($piholeResult.TopDomains.Count) | Clients: $($piholeResult.TopClients.Count)" -ForegroundColor $phFarbe

Write-Host "  Rufe ntopng Daten ab..." -ForegroundColor Gray
$ntopResult = Check-NtopngAPI -IP "192.168.80.20" -PassSecure $Creds.NtopngPass -DetailModus
$ntFarbe = if ($ntopResult.Status -eq 'OK') { 'Green' } elseif ($ntopResult.Status -eq 'WARNUNG') { 'Yellow' } else { 'Red' }
Write-Host "  ntopng: $($ntopResult.Status) | $($ntopResult.AnzahlExtern) externe Flows | Talker: $($ntopResult.TopTalkers.Count)" -ForegroundColor $ntFarbe
Write-Host ""

$jetzt       = Get-Date
$zeitstempel = $jetzt.ToString("dd.MM.yyyy HH:mm")

# ── HTML-Hilfsfunktion ─────────────────────────────────────────────────────────
function New-Balken {
    param([double]$Wert, [double]$Max, [string]$Farbe = "#58a6ff")
    $pct = if ($Max -gt 0) { [Math]::Round(($Wert / $Max) * 100) } else { 0 }
    if ($pct -gt 100) { $pct = 100 }
    return "<div style='height:6px;background:#21262d;border-radius:3px;min-width:80px;'><div style='height:6px;background:$Farbe;border-radius:3px;width:${pct}%;'></div></div>"
}

# ── Pi-hole Kacheln ────────────────────────────────────────────────────────────
$piRate    = $piholeResult.Blockierrate
$piQ       = $piholeResult.Queries_Heute
$piCl      = $piholeResult.Aktive_Clients
$piGrav    = $piholeResult.Gravity_Liste

$piholeKachelnHtml = @"
<div style='display:flex;gap:12px;flex-wrap:wrap;margin-bottom:16px;'>
  <div style='background:#161b22;border:1px solid #30363d;border-radius:6px;padding:14px 20px;text-align:center;min-width:110px;'>
    <div style='color:#58a6ff;font-size:1.8em;font-weight:bold;'>$piRate</div>
    <div style='color:#8b949e;font-size:0.8em;margin-top:4px;'>Blockierrate</div>
  </div>
  <div style='background:#161b22;border:1px solid #30363d;border-radius:6px;padding:14px 20px;text-align:center;min-width:110px;'>
    <div style='color:#e6edf3;font-size:1.8em;font-weight:bold;'>$piQ</div>
    <div style='color:#8b949e;font-size:0.8em;margin-top:4px;'>Queries heute</div>
  </div>
  <div style='background:#161b22;border:1px solid #30363d;border-radius:6px;padding:14px 20px;text-align:center;min-width:110px;'>
    <div style='color:#e6edf3;font-size:1.8em;font-weight:bold;'>$piCl</div>
    <div style='color:#8b949e;font-size:0.8em;margin-top:4px;'>Aktive Clients</div>
  </div>
  <div style='background:#161b22;border:1px solid #30363d;border-radius:6px;padding:14px 20px;text-align:center;min-width:110px;'>
    <div style='color:#e6edf3;font-size:1.8em;font-weight:bold;'>$piGrav</div>
    <div style='color:#8b949e;font-size:0.8em;margin-top:4px;'>Gravity-Domains</div>
  </div>
</div>
"@

# ── Upstream DNS ───────────────────────────────────────────────────────────────
$upstreamHtml = ""
if ($piholeResult.Upstreams.Count -gt 0) {
    $tags = ""
    foreach ($u in $piholeResult.Upstreams) {
        $res = $u.Resolver; $pct = $u.Prozent
        $tags += "<span style='display:inline-block;background:#21262d;border:1px solid #30363d;border-radius:12px;padding:4px 10px;margin:3px;font-size:0.85em;'><span style='color:#58a6ff;font-family:monospace;'>$res</span> <span style='color:#8b949e;'>${pct}%</span></span>"
    }
    $upstreamHtml = @"
<h3 style='color:#58a6ff;margin-top:18px;margin-bottom:8px;font-size:0.95em;'>Upstream DNS-Resolver</h3>
<div style='background:#0d1117;border:1px solid #21262d;border-radius:6px;padding:10px;'>$tags</div>
"@
}

# ── Top geblockte Domains ──────────────────────────────────────────────────────
$topDomainsHtml = ""
if ($piholeResult.TopDomains.Count -gt 0) {
    $maxD = ($piholeResult.TopDomains | Measure-Object -Property Anzahl -Maximum).Maximum
    $dz = ""
    foreach ($d in $piholeResult.TopDomains) {
        $balken = New-Balken -Wert $d.Anzahl -Max $maxD -Farbe "#f85149"
        $dom = $d.Domain; $anz = $d.Anzahl
        $dz += "<tr><td style='padding:6px 10px;font-family:monospace;font-size:0.85em;color:#c9d1d9;border-bottom:1px solid #21262d;'>$dom</td><td style='padding:6px 10px;font-family:monospace;color:#8b949e;border-bottom:1px solid #21262d;text-align:right;'>$anz</td><td style='padding:6px 10px;border-bottom:1px solid #21262d;min-width:120px;'>$balken</td></tr>"
    }
    $topDomainsHtml = @"
<h3 style='color:#58a6ff;margin-top:18px;margin-bottom:8px;font-size:0.95em;'>Top geblockte Domains</h3>
<table style='width:100%;border-collapse:collapse;background:#161b22;border-radius:6px;overflow:hidden;'>
  <thead><tr style='background:#21262d;'>
    <th style='padding:7px 10px;text-align:left;color:#8b949e;font-size:0.85em;font-weight:600;'>Domain</th>
    <th style='padding:7px 10px;text-align:right;color:#8b949e;font-size:0.85em;font-weight:600;'>Geblockt</th>
    <th style='padding:7px 10px;color:#8b949e;font-size:0.85em;'></th>
  </tr></thead>
  <tbody>$dz</tbody>
</table>
"@
}

# ── Top DNS-Clients ────────────────────────────────────────────────────────────
$topClientsHtml = ""
if ($piholeResult.TopClients.Count -gt 0) {
    $maxC = ($piholeResult.TopClients | Measure-Object -Property Anzahl -Maximum).Maximum
    $cz = ""
    foreach ($c in $piholeResult.TopClients) {
        $balken  = New-Balken -Wert $c.Anzahl -Max $maxC -Farbe "#3fb950"
        $cName   = $c.Client; $cIP = $c.IP; $cAnz = $c.Anzahl
        $cAnzeige = if ($cName -ne $cIP) { "$cName<br><span style='color:#8b949e;font-size:0.82em;font-family:monospace;'>$cIP</span>" } else { $cIP }
        $cz += "<tr><td style='padding:6px 10px;font-size:0.85em;color:#c9d1d9;border-bottom:1px solid #21262d;'>$cAnzeige</td><td style='padding:6px 10px;font-family:monospace;color:#8b949e;border-bottom:1px solid #21262d;text-align:right;'>$cAnz</td><td style='padding:6px 10px;border-bottom:1px solid #21262d;min-width:120px;'>$balken</td></tr>"
    }
    $topClientsHtml = @"
<h3 style='color:#58a6ff;margin-top:18px;margin-bottom:8px;font-size:0.95em;'>Top DNS-Clients</h3>
<table style='width:100%;border-collapse:collapse;background:#161b22;border-radius:6px;overflow:hidden;'>
  <thead><tr style='background:#21262d;'>
    <th style='padding:7px 10px;text-align:left;color:#8b949e;font-size:0.85em;font-weight:600;'>Client</th>
    <th style='padding:7px 10px;text-align:right;color:#8b949e;font-size:0.85em;font-weight:600;'>Anfragen</th>
    <th style='padding:7px 10px;color:#8b949e;font-size:0.85em;'></th>
  </tr></thead>
  <tbody>$cz</tbody>
</table>
"@
}

# ── ntopng externe Verbindungen ────────────────────────────────────────────────
$ntopFlowsHtml = "<p style='color:#8b949e;font-size:0.85em;'>Keine aktiven externen Verbindungen.</p>"
if ($ntopResult.ExterneFlows.Count -gt 0) {
    $fz = ""
    foreach ($flow in $ntopResult.ExterneFlows) {
        $appText = if ($flow.App) { $flow.App } else { $flow.Protokoll }
        $bytesText = if ($flow.Bytes -gt 1MB) { "$([math]::Round($flow.Bytes/1MB,1)) MB" } elseif ($flow.Bytes -gt 1KB) { "$([math]::Round($flow.Bytes/1KB,1)) KB" } else { "$($flow.Bytes) B" }
        $eIP = $flow.ExterneIP; $iIP = $flow.InternIP; $fPort = $flow.Port
        $fz += "<tr><td style='padding:5px 10px;font-family:monospace;font-size:0.85em;color:#c9d1d9;border-bottom:1px solid #21262d;'>$eIP</td><td style='padding:5px 10px;font-family:monospace;font-size:0.85em;color:#8b949e;border-bottom:1px solid #21262d;'>$iIP</td><td style='padding:5px 10px;font-size:0.85em;border-bottom:1px solid #21262d;'>$appText :$fPort</td><td style='padding:5px 10px;font-size:0.85em;color:#8b949e;border-bottom:1px solid #21262d;'>$bytesText</td></tr>"
    }
    $ntopFlowsHtml = @"
<table style='width:100%;border-collapse:collapse;background:#161b22;border-radius:6px;overflow:hidden;'>
  <thead><tr style='background:#21262d;'>
    <th style='padding:7px 10px;text-align:left;color:#8b949e;font-size:0.85em;font-weight:600;'>Externe IP</th>
    <th style='padding:7px 10px;text-align:left;color:#8b949e;font-size:0.85em;font-weight:600;'>Interne IP</th>
    <th style='padding:7px 10px;text-align:left;color:#8b949e;font-size:0.85em;font-weight:600;'>App / Port</th>
    <th style='padding:7px 10px;text-align:left;color:#8b949e;font-size:0.85em;font-weight:600;'>Daten</th>
  </tr></thead>
  <tbody>$fz</tbody>
</table>
"@
}

# ── Top Talkers ────────────────────────────────────────────────────────────────
$topTalkersHtml = ""
if ($ntopResult.TopTalkers.Count -gt 0) {
    $maxT = ($ntopResult.TopTalkers | Measure-Object -Property GesamtMB -Maximum).Maximum
    $tz = ""
    foreach ($t in $ntopResult.TopTalkers) {
        $balken   = New-Balken -Wert $t.GesamtMB -Max $maxT -Farbe "#d29922"
        $tHost    = $t.Host; $tIP = $t.IP; $tMB = $t.GesamtMB
        $tAnzeige = if ($tHost -ne $tIP) { "$tHost<br><span style='color:#8b949e;font-size:0.82em;font-family:monospace;'>$tIP</span>" } else { $tIP }
        $sentMB   = [Math]::Round($t.BytesSent / 1MB, 1)
        $recvMB   = [Math]::Round($t.BytesRecv / 1MB, 1)
        $tz += "<tr><td style='padding:6px 10px;font-size:0.85em;color:#c9d1d9;border-bottom:1px solid #21262d;'>$tAnzeige</td><td style='padding:6px 10px;font-family:monospace;font-size:0.85em;color:#e6edf3;border-bottom:1px solid #21262d;text-align:right;'>$tMB MB</td><td style='padding:6px 10px;font-family:monospace;font-size:0.82em;border-bottom:1px solid #21262d;'><span style='color:#3fb950;'>&#x2191;$sentMB</span> / <span style='color:#58a6ff;'>&#x2193;$recvMB</span> MB</td><td style='padding:6px 10px;border-bottom:1px solid #21262d;min-width:120px;'>$balken</td></tr>"
    }
    $topTalkersHtml = @"
<h3 style='color:#58a6ff;margin-top:18px;margin-bottom:8px;font-size:0.95em;'>Top Talkers</h3>
<table style='width:100%;border-collapse:collapse;background:#161b22;border-radius:6px;overflow:hidden;'>
  <thead><tr style='background:#21262d;'>
    <th style='padding:7px 10px;text-align:left;color:#8b949e;font-size:0.85em;font-weight:600;'>Host / IP</th>
    <th style='padding:7px 10px;text-align:right;color:#8b949e;font-size:0.85em;font-weight:600;'>Gesamt</th>
    <th style='padding:7px 10px;text-align:left;color:#8b949e;font-size:0.85em;font-weight:600;'>Gesendet / Empfangen</th>
    <th style='padding:7px 10px;color:#8b949e;font-size:0.85em;'></th>
  </tr></thead>
  <tbody>$tz</tbody>
</table>
"@
}

# ── Statusfarben & Info ────────────────────────────────────────────────────────
$piholeStatusFarbe = if ($piholeResult.Status -eq "FEHLER") { "#f85149" } elseif ($piholeResult.Status -eq "WARNUNG") { "#d29922" } else { "#3fb950" }
$ntopStatusFarbe   = if ($ntopResult.Status -eq "FEHLER")   { "#f85149" } else { "#3fb950" }
$piholeInfo        = $piholeResult.Info
$ntopInfo          = $ntopResult.Info

# ── HTML-Body ─────────────────────────────────────────────────────────────────
$body = @"
<!DOCTYPE html>
<html>
<head><meta charset='UTF-8'></head>
<body style='background:#0d1117;color:#e6edf3;font-family:Segoe UI,Arial,sans-serif;margin:0;padding:20px;'>
  <div style='max-width:820px;margin:0 auto;'>
    <div style='background:#1f6feb;color:#fff;padding:12px 16px;border-radius:6px;font-size:1.1em;font-weight:bold;margin-bottom:20px;'>
      Heimnetz Netzwerk-Analyse &ndash; $zeitstempel
    </div>

    <h2 style='color:#58a6ff;margin-bottom:12px;font-size:1.1em;border-bottom:1px solid #21262d;padding-bottom:6px;'>Pi-hole DNS-Analyse</h2>
    <p style='color:$piholeStatusFarbe;font-size:0.88em;margin:0 0 14px 0;'>$piholeInfo</p>

    $piholeKachelnHtml
    $upstreamHtml
    $topDomainsHtml
    $topClientsHtml

    <h2 style='color:#58a6ff;margin-top:28px;margin-bottom:12px;font-size:1.1em;border-bottom:1px solid #21262d;padding-bottom:6px;'>ntopng Netzwerk-Traffic</h2>
    <p style='color:$ntopStatusFarbe;font-size:0.88em;margin:0 0 12px 0;'>$ntopInfo</p>

    <h3 style='color:#58a6ff;margin-top:0;margin-bottom:8px;font-size:0.95em;'>Aktive externe Verbindungen</h3>
    $ntopFlowsHtml
    $topTalkersHtml

    <p style='color:#8b949e;font-size:0.8em;margin-top:20px;'>
      Heimnetz Monitor v2.0 | Netzwerk-Analyse | $zeitstempel
    </p>
  </div>
</body>
</html>
"@

# ── Ausgabe ────────────────────────────────────────────────────────────────────
if ($Test) {
    $tmpPfad = Join-Path $env:TEMP "NetzwerkAnalyse_Test.html"
    $body | Out-File -FilePath $tmpPfad -Encoding UTF8
    Write-Host "  Test-Modus: HTML gespeichert unter $tmpPfad" -ForegroundColor Green
    Start-Process $tmpPfad
} else {
    Write-Host "  Sende Netzwerk-Analyse per E-Mail..." -ForegroundColor Cyan
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
        $mail.Subject         = "[Heimnetz] Netzwerk-Analyse - $zeitstempel"
        $mail.Body            = $body
        $mail.IsBodyHtml      = $true
        $mail.SubjectEncoding = [System.Text.Encoding]::UTF8
        $mail.BodyEncoding    = [System.Text.Encoding]::UTF8

        $smtpClient.Send($mail)
        $mail.Dispose()
        $smtpClient.Dispose()

        Write-Host "  E-Mail gesendet an: $($smtp.smtp_an)" -ForegroundColor Green
        Write-Host "  Betreff: [Heimnetz] Netzwerk-Analyse - $zeitstempel" -ForegroundColor Gray
    }
    catch {
        Write-Host "  FEHLER beim E-Mail-Versand: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
