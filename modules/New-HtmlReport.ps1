# HTML-REPORT GENERATOR
# ════════════════════════════════════════════════════════════════════════════
function New-HtmlReport {
    param(
        [array]$Ergebnisse,
        $LoginResult,
        [int]$AnzahlOK,
        [int]$AnzahlWarn,
        [int]$AnzahlFehler,
        [double]$LaufzeitSek,
        $Config
    )

    $jetzt         = Get-Date
    $naechsteCheck = $jetzt.AddMinutes($Config.einstellungen.check_intervall_minuten).ToString("HH:mm")
    $gesamtGeraete = $Ergebnisse.Count

    $bannerFarbe = if ($AnzahlFehler -gt 0) { "#f85149" } elseif ($AnzahlWarn -gt 0) { "#d29922" } else { "#3fb950" }
    $bannerText  = if ($AnzahlFehler -gt 0) { "ALARM – $AnzahlFehler FEHLER ERKANNT" } `
                   elseif ($AnzahlWarn -gt 0) { "ACHTUNG – $AnzahlWarn WARNUNGEN" } `
                   else { "ALLE $gesamtGeraete SYSTEME OK" }

    function Get-GeraetIcon { param([string]$Typ)
        switch ($Typ) {
            "router"             { "Netz" }
            "raspberry"          { "Pi"   }
            "nas_synology"       { "NAS"  }
            "windows_host"       { "Win"  }
            "mailstore"          { "Mail" }
            "sma_homemanager"    { "PV"   }
            "elwa_heizstab"      { "Heiz" }
            "powerline_fritzbox" { "Plne" }
            "kamera_reolink"     { "Cam"  }
            "kamera_instar"      { "iCam" }
            default              { "Sys"  }
        }
    }

    function Get-StatusFarbe { param([string]$Status)
        switch ($Status) {
            "OK"      { "#3fb950" }
            "WARNUNG" { "#d29922" }
            "FEHLER"  { "#f85149" }
            "INAKTIV" { "#6e7681" }
            default   { "#6e7681" }
        }
    }

    function Get-StatusHintergrund { param([string]$Status)
        switch ($Status) {
            "OK"      { "rgba(63,185,80,0.08)"   }
            "WARNUNG" { "rgba(210,153,34,0.12)"  }
            "FEHLER"  { "rgba(248,81,73,0.12)"   }
            default   { "rgba(110,118,129,0.08)" }
        }
    }

    # Zusammenfassungs-Tabellenzeilen
    $tabelleZeilen = ""
    foreach ($e in $Ergebnisse) {
        $icon    = Get-GeraetIcon -Typ $e.Typ
        $farbe   = Get-StatusFarbe -Typ $e.CheckStatus
        $hgFarbe = Get-StatusHintergrund -Typ $e.CheckStatus

        # Detail-Bereich aufbauen
        $detailHtml = ""
        if ($e.Details) {
            $d = $e.Details
            switch ($e.Typ) {
                "nas_synology" {
                    if ($d.Volumes -and $d.Volumes.Count -gt 0) {
                        $volZeilen = ""
                        foreach ($vol in $d.Volumes) {
                            $balkenFarbe = if ($vol.Prozent -gt 85) { "#f85149" } elseif ($vol.Prozent -gt 70) { "#d29922" } else { "#3fb950" }
                            $volZeilen += "<tr><td style='padding:4px 8px;'>$($vol.Name)</td><td style='padding:4px 8px;'>$($vol.Groesse_GB) GB</td><td style='padding:4px 8px;'>$($vol.Frei_GB) GB frei</td><td style='padding:4px 8px;width:120px;'><div style='background:#30363d;border-radius:3px;height:10px;'><div style='background:$balkenFarbe;width:$($vol.Prozent)%;height:10px;border-radius:3px;'></div></div><span style='font-size:0.8em;'>$($vol.Prozent)%</span></td><td style='padding:4px 8px;'>$($vol.RAID_Status)</td></tr>"
                        }
                        $detailHtml += "<table style='width:100%;border-collapse:collapse;font-size:0.9em;margin-top:8px;'><tr style='color:#8b949e;'><th style='text-align:left;padding:4px 8px;'>Volume</th><th style='text-align:left;padding:4px 8px;'>Groesse</th><th style='text-align:left;padding:4px 8px;'>Frei</th><th style='text-align:left;padding:4px 8px;'>Fuellstand</th><th style='text-align:left;padding:4px 8px;'>RAID</th></tr>$volZeilen</table>"
                    }
                    if ($d.SMART_Status -and $d.SMART_Status.Count -gt 0) {
                        $smartZeilen = ""
                        foreach ($s in $d.SMART_Status) {
                            $smartFarbe = if ($s.Status -eq "Normal") { "#3fb950" } else { "#f85149" }
                            $smartZeilen += "<tr><td style='padding:4px 8px;'>$($s.Disk)</td><td style='padding:4px 8px;color:$smartFarbe;'>$($s.Status)</td><td style='padding:4px 8px;'>$($s.Temp_C)°C</td></tr>"
                        }
                        $detailHtml += "<p style='color:#8b949e;margin:8px 0 4px;font-size:0.85em;'>SMART Status:</p><table style='width:100%;border-collapse:collapse;font-size:0.9em;'><tr style='color:#8b949e;'><th style='text-align:left;padding:4px 8px;'>Disk</th><th style='text-align:left;padding:4px 8px;'>Status</th><th style='text-align:left;padding:4px 8px;'>Temp</th></tr>$smartZeilen</table>"
                    }
                    if ($d.CPU_Temp -and $d.CPU_Temp -ne "n/a") {
                        $detailHtml += "<p style='color:#8b949e;font-size:0.85em;margin:6px 0;'>CPU Temp: <span style='color:#e6edf3;'>$($d.CPU_Temp)</span> | Uptime: <span style='color:#e6edf3;'>$($d.Uptime)</span></p>"
                    }
                }
                "mailstore" {
                    if ($d.Jobs -and $d.Jobs.Count -gt 0) {
                        $jobZeilen = ""
                        foreach ($job in $d.Jobs) {
                            $jobFarbe = if ($job.Fehler -gt 0) { "#f85149" } elseif ($job.Warnungen -gt 0) { "#d29922" } else { "#3fb950" }
                            $bekannt  = if ($job.Name -match "andrearosbach27@gmail") { " (bekanntes Problem)" } else { "" }
                            $jobZeilen += "<tr style='$(if ($job.Fehler -gt 0) { "background:rgba(248,81,73,0.08);" })'><td style='padding:4px 8px;font-size:0.85em;'>$($job.Name)$bekannt</td><td style='padding:4px 8px;color:$jobFarbe;'>$($job.Status)</td><td style='padding:4px 8px;color:#f85149;'>$($job.Fehler)</td><td style='padding:4px 8px;color:#d29922;'>$($job.Warnungen)</td></tr>"
                        }
                        $detailHtml += "<table style='width:100%;border-collapse:collapse;font-size:0.85em;margin-top:8px;'><tr style='color:#8b949e;'><th style='text-align:left;padding:4px 8px;'>Job</th><th style='text-align:left;padding:4px 8px;'>Status</th><th style='text-align:left;padding:4px 8px;'>Fehler</th><th style='text-align:left;padding:4px 8px;'>Warnungen</th></tr>$jobZeilen</table>"
                    }
                    if ($d.Archiv_Gesamt -gt 0) {
                        $detailHtml += "<p style='color:#8b949e;font-size:0.85em;margin:6px 0;'>Archiv gesamt: <span style='color:#e6edf3;'>$($d.Archiv_Gesamt)</span> Nachrichten</p>"
                    }
                }
                "elwa_heizstab" {
                    $tempFarbe = if ($d.Warnung) { "#f85149" } elseif ([double]$d.Temperatur.Replace("°C","") -gt 60) { "#d29922" } else { "#3fb950" }
                    $detailHtml += "<div style='display:flex;gap:20px;flex-wrap:wrap;margin-top:8px;'><div style='background:#21262d;padding:12px 16px;border-radius:6px;'><div style='color:#8b949e;font-size:0.8em;'>Temperatur</div><div style='font-size:1.4em;color:$tempFarbe;font-weight:bold;'>$($d.Temperatur)</div></div><div style='background:#21262d;padding:12px 16px;border-radius:6px;'><div style='color:#8b949e;font-size:0.8em;'>Leistung</div><div style='font-size:1.4em;color:#58a6ff;font-weight:bold;'>$($d.Leistung_W)</div></div><div style='background:#21262d;padding:12px 16px;border-radius:6px;'><div style='color:#8b949e;font-size:0.8em;'>Status</div><div style='font-size:1.2em;color:#e6edf3;'>$($d.Geraet_Status)</div></div></div>"
                }
                "sma_homemanager" {
                    $swFarbe = if ($d.Speedwire_Aktiv) { "#3fb950" } else { "#f85149" }
                    $detailHtml += "<div style='margin-top:8px;'><span style='color:#8b949e;'>Speedwire Port 9522: </span><span style='color:$swFarbe;font-weight:bold;'>$(if ($d.Speedwire_Aktiv) { 'AKTIV' } else { 'INAKTIV' })</span></div>"
                }
                { $_ -in @("kamera_reolink","kamera_instar") } {
                    $rtspF   = if ($d.RTSP_Port -eq "OFFEN")    { "#3fb950" } else { "#f85149" }
                    $httpF   = if ($d.HTTP_Port -eq "OFFEN")    { "#3fb950" } else { "#f85149" }
                    $streamF = if ($d.Stream_Aktiv -eq $true)   { "#3fb950" } elseif ($d.Stream_Aktiv -eq "ffprobe nicht verfuegbar") { "#8b949e" } else { "#f85149" }
                    $detailHtml += "<div style='margin-top:8px;font-size:0.9em;'><span style='color:#8b949e;'>RTSP 554: </span><span style='color:$rtspF;'>$($d.RTSP_Port)</span> &nbsp;|&nbsp; <span style='color:#8b949e;'>HTTP: </span><span style='color:$httpF;'>$($d.HTTP_Port)</span> &nbsp;|&nbsp; <span style='color:#8b949e;'>Stream: </span><span style='color:$streamF;'>$($d.Stream_Aktiv)</span>"
                    if ($d.Aufloesung -ne "n/a") { $detailHtml += " &nbsp;|&nbsp; <span style='color:#8b949e;'>$($d.Aufloesung) $($d.Codec)</span>" }
                    $detailHtml += "</div>"
                }
            }
        }

        $detailBlock = if ($detailHtml -ne "") {
            "<div id='detail_$($e.IP -replace '\.','_')' style='display:none;padding:10px 12px;background:#0d1117;border-top:1px solid #30363d;'>$detailHtml</div>"
        } else { "" }

        $onklick = if ($detailHtml -ne "") { "onclick=""var d=document.getElementById('detail_$($e.IP -replace '\.','_')');d.style.display=d.style.display=='none'?'block':'none'"" style='cursor:pointer;'" } else { "" }

        $tabelleZeilen += @"
<tr $onklick style='background:$hgFarbe;border-bottom:1px solid #21262d;'>
  <td style='padding:8px 10px;font-size:1.1em;'>$icon</td>
  <td style='padding:8px 10px;font-weight:500;'>$($e.Geraet)</td>
  <td style='padding:8px 10px;font-family:monospace;color:#8b949e;'>$($e.IP)</td>
  <td style='padding:8px 10px;color:#8b949e;'>$($e.Latenz)</td>
  <td style='padding:8px 10px;'><span style='color:$farbe;font-weight:bold;'>$($e.CheckStatus)</span></td>
  <td style='padding:8px 10px;font-size:0.9em;color:#8b949e;'>$($e.Info)</td>
</tr>
$(if ($detailBlock -ne "") { "<tr><td colspan='6' style='padding:0;'>$detailBlock</td></tr>" })
"@
    }

    # Externe Logins Sektion
    $loginHtml = ""
    if ($LoginResult) {
        $loginZeilen = ""
        foreach ($eintrag in $LoginResult.Eintraege) {
            $eFarbe = switch -Regex ($eintrag.Ergebnis) {
                "Fehlversuch" { "#f85149" }
                "Erfolg"      { "#3fb950" }
                "VPN"         { "#d29922" }
                default       { "#8b949e" }
            }
            $loginZeilen += "<tr><td style='padding:6px 10px;font-size:0.85em;color:#8b949e;'>$($eintrag.Zeitstempel)</td><td style='padding:6px 10px;font-family:monospace;font-size:0.85em;'>$($eintrag.QuellIP)</td><td style='padding:6px 10px;font-size:0.85em;'>$($eintrag.Zielgeraet)</td><td style='padding:6px 10px;font-size:0.85em;'>$($eintrag.Typ)</td><td style='padding:6px 10px;font-size:0.85em;color:$eFarbe;'>$($eintrag.Ergebnis)</td></tr>"
        }
        $warnBanner = if ($LoginResult.Warnung) { "<div style='background:#f85149;color:#fff;padding:10px 14px;border-radius:6px;margin-bottom:12px;font-weight:bold;'>WARNUNG: $($LoginResult.Verdaechtige) Fehlversuche in den letzten 24 Stunden!</div>" } else { "" }
        $loginHtml = @"
<div style='margin-top:32px;'>
  <h2 style='color:#58a6ff;font-size:1.1em;margin-bottom:12px;'>Externe Zugriffe – Letzte 24 Stunden</h2>
  $warnBanner
  <table style='width:100%;border-collapse:collapse;background:#161b22;border-radius:8px;overflow:hidden;'>
    <thead><tr style='background:#21262d;'><th style='padding:8px 10px;text-align:left;color:#8b949e;font-size:0.85em;'>Zeit</th><th style='padding:8px 10px;text-align:left;color:#8b949e;font-size:0.85em;'>Von IP</th><th style='padding:8px 10px;text-align:left;color:#8b949e;font-size:0.85em;'>Zielgeraet</th><th style='padding:8px 10px;text-align:left;color:#8b949e;font-size:0.85em;'>Typ</th><th style='padding:8px 10px;text-align:left;color:#8b949e;font-size:0.85em;'>Ergebnis</th></tr></thead>
    <tbody>$loginZeilen</tbody>
  </table>
</div>
"@
    }

    return @"
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Heimnetz Monitor – $($jetzt.ToString('dd.MM.yyyy HH:mm'))</title>
<style>
*{box-sizing:border-box;margin:0;padding:0;}
body{background:#0d1117;color:#e6edf3;font-family:'Segoe UI',Arial,sans-serif;padding:16px;}
.container{max-width:1100px;margin:0 auto;}
h1{color:#58a6ff;font-size:1.5em;margin-bottom:2px;}
.sub{color:#8b949e;font-size:0.9em;margin-bottom:16px;}
.banner{background:$bannerFarbe;color:#fff;padding:14px 18px;border-radius:8px;font-size:1.2em;font-weight:bold;margin-bottom:16px;text-align:center;letter-spacing:0.5px;}
.stats{display:flex;gap:12px;margin-bottom:20px;flex-wrap:wrap;}
.stat{background:#161b22;border-radius:8px;padding:10px 18px;flex:1;min-width:100px;text-align:center;}
.stat-zahl{font-size:1.8em;font-weight:bold;}
.stat-label{font-size:0.8em;color:#8b949e;margin-top:2px;}
table{width:100%;border-collapse:collapse;background:#161b22;border-radius:8px;overflow:hidden;}
thead tr{background:#21262d;}
th{padding:10px;text-align:left;color:#8b949e;font-weight:500;font-size:0.9em;}
tr:hover{filter:brightness(1.08);}
.footer{margin-top:24px;color:#8b949e;font-size:0.8em;text-align:center;padding-top:16px;border-top:1px solid #21262d;}
@media(max-width:600px){.stats{flex-direction:column;} td,th{padding:6px 6px;font-size:0.85em;}}
</style>
</head>
<body>
<div class="container">
  <h1>Heimnetz Monitor</h1>
  <div class="sub">$($jetzt.ToString('dd.MM.yyyy HH:mm:ss')) Uhr</div>
  <div class="banner">$bannerText</div>
  <div class="stats">
    <div class="stat"><div class="stat-zahl" style="color:#3fb950;">$AnzahlOK</div><div class="stat-label">OK</div></div>
    <div class="stat"><div class="stat-zahl" style="color:#d29922;">$AnzahlWarn</div><div class="stat-label">Warnungen</div></div>
    <div class="stat"><div class="stat-zahl" style="color:#f85149;">$AnzahlFehler</div><div class="stat-label">Fehler</div></div>
    <div class="stat"><div class="stat-zahl" style="color:#58a6ff;">$gesamtGeraete</div><div class="stat-label">Geraete</div></div>
  </div>
  <table>
    <thead>
      <tr>
        <th></th>
        <th>Geraet</th>
        <th>IP-Adresse</th>
        <th>Latenz</th>
        <th>Status</th>
        <th>Info</th>
      </tr>
    </thead>
    <tbody>
      $tabelleZeilen
    </tbody>
  </table>
  $loginHtml
  <div class="footer">
    $gesamtGeraete Geraete geprueft &nbsp;|&nbsp; $AnzahlOK OK &nbsp;|&nbsp; $AnzahlWarn Warnungen &nbsp;|&nbsp; $AnzahlFehler Fehler &nbsp;|&nbsp;
    Laufzeit: $($LaufzeitSek)s &nbsp;|&nbsp; Naechste Pruefung: $naechsteCheck Uhr &nbsp;|&nbsp;
    Heimnetz Monitor v$VersionInfo | Stand: April 2026
  </div>
</div>
</body>
</html>
"@
}

