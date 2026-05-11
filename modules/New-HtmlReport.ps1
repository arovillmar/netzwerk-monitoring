function New-HtmlReport {
    param(
        [array]$Ergebnisse,
        $LoginResult,
        $NtopngResult,
        [int]$AnzahlOK,
        [int]$AnzahlWarn,
        [int]$AnzahlFehler,
        [double]$LaufzeitSek,
        $Config
    )

    $jetzt          = Get-Date
    $naechsteCheck  = $jetzt.AddMinutes($Config.einstellungen.check_intervall_minuten).ToString("HH:mm")
    $gesamtGeraete  = $Ergebnisse.Count
    $bannerFarbe    = if ($AnzahlFehler -gt 0) { "#f85149" } elseif ($AnzahlWarn -gt 0) { "#d29922" } else { "#3fb950" }
    $bannerText     = if ($AnzahlFehler -gt 0) { "ALARM – $AnzahlFehler FEHLER ERKANNT" } `
                      elseif ($AnzahlWarn -gt 0) { "ACHTUNG – $AnzahlWarn WARNUNGEN" } `
                      else { "ALLE $gesamtGeraete SYSTEME OK" }

    # Geräte-Config als Lookup-Tabelle (IP → Gerät)
    $geraeteLookup = @{}
    foreach ($g in $Config.geraete) { $geraeteLookup[$g.ip] = $g }

    # ── Hilfsfunktionen ──────────────────────────────────────────────────────

    function Get-GeraetIcon { param([string]$Typ)
        switch ($Typ) {
            "router"             { "&#x1F4E1;" }  # 📡
            "raspberry"          { "&#x1F967;" }  # 🥧
            "nas_synology"       { "&#x1F5C4;"  }  # 🗄
            "windows_host"       { "&#x1F4BB;" }  # 💻
            "mailstore"          { "&#x2709;"   }  # ✉
            "sma_homemanager"    { "&#x2600;"   }  # ☀
            "elwa_heizstab"      { "&#x1F321;" }  # 🌡
            "powerline_fritzbox" { "&#x1F50C;" }  # 🔌
            "kamera_reolink"     { "&#x1F4F9;" }  # 📹
            "kamera_instar"      { "&#x1F4F9;" }  # 📹
            default              { "&#x1F4BB;" }  # 💻
        }
    }

    function Get-StatusFarbe { param([string]$Status)
        switch ($Status) {
            "OK"      { "#3fb950" }
            "WARNUNG" { "#d29922" }
            "FEHLER"  { "#f85149" }
            default   { "#6e7681" }
        }
    }

    function Get-StatusHintergrund { param([string]$Status)
        switch ($Status) {
            "OK"      { "rgba(63,185,80,0.06)"   }
            "WARNUNG" { "rgba(210,153,34,0.10)"  }
            "FEHLER"  { "rgba(248,81,73,0.10)"   }
            default   { "rgba(110,118,129,0.06)" }
        }
    }

    function Get-PortString { param($GeraetCfg, [string]$Typ)
        $teile = @("Ping")
        if (-not $GeraetCfg) { return $teile -join " / " }
        switch ($Typ) {
            "router"             { $teile += "HTTP:80" }
            "raspberry"          { $teile += "SSH:22"; $teile += "HTTP:80"; $teile += "TCP:3000" }
            "nas_synology"       {
                $sshP = if ($GeraetCfg.ssh_port) { $GeraetCfg.ssh_port } else { 822 }
                $dsmP = if ($GeraetCfg.dsm_port) { $GeraetCfg.dsm_port } else { 5000 }
                $teile += "SSH:$sshP"; $teile += "HTTP:$dsmP"
            }
            "windows_host"       { $teile += "RDP:3389" }
            "mailstore"          { $teile += "RDP:3389"; $teile += "WinRM" }
            "sma_homemanager"    { $teile += "HTTP:80"; $teile += "UDP:9522" }
            "elwa_heizstab"      { $teile += "HTTP:80/data.jsn" }
            "powerline_fritzbox" { $teile += "HTTP:80" }
            { $_ -in @("kamera_reolink","kamera_instar") } {
                $httpP = if ($GeraetCfg.http_port) { $GeraetCfg.http_port } else { if ($Typ -eq "kamera_reolink") { 80 } else { 8080 } }
                $teile += "RTSP:554"; $teile += "HTTP:$httpP"
            }
        }
        return $teile -join " / "
    }

    function Get-PingPerformance { param([string]$Latenz)
        if (-not $Latenz -or $Latenz -eq "n/a" -or $Latenz -eq "9999ms") {
            return "<span style='color:#f85149;'>&#10060; Timeout</span>"
        }
        $ms = 0
        [int]::TryParse(($Latenz -replace 'ms','').Trim(), [ref]$ms) | Out-Null
        if ($ms -le 1)  { return "<span style='color:#3fb950;'><b>$Latenz</b> <small>LAN-Speed</small></span>" }
        if ($ms -le 5)  { return "<span style='color:#3fb950;'><b>$Latenz</b> <small>Gut</small></span>" }
        if ($ms -le 20) { return "<span style='color:#d29922;'><b>$Latenz</b> <small>Akzeptabel</small></span>" }
        return "<span style='color:#f85149;'><b>$Latenz</b> <small>LANGSAM!</small></span>"
    }

    # ── Geräte-Tabelle ───────────────────────────────────────────────────────
    $tabelleZeilen = ""
    foreach ($e in $Ergebnisse) {
        $icon    = Get-GeraetIcon -Typ $e.Typ
        $farbe   = Get-StatusFarbe -Status $e.CheckStatus
        $hgFarbe = Get-StatusHintergrund -Status $e.CheckStatus
        $gCfg    = $geraeteLookup[$e.IP]
        $portStr = Get-PortString -GeraetCfg $gCfg -Typ $e.Typ
        $perfHtml = Get-PingPerformance -Latenz $e.Latenz

        # Detail-Block aufbauen
        $detailHtml = ""
        if ($e.Details) {
            $d = $e.Details
            switch ($e.Typ) {
                "nas_synology" {
                    if ($d.Volumes -and $d.Volumes.Count -gt 0) {
                        $volZeilen = ""
                        foreach ($vol in $d.Volumes) {
                            $bFarbe = if ($vol.Prozent -gt 85) { "#f85149" } elseif ($vol.Prozent -gt 70) { "#d29922" } else { "#3fb950" }
                            $volZeilen += "<tr><td style='padding:4px 8px;'>$($vol.Name)</td><td style='padding:4px 8px;'>$($vol.Groesse_GB)</td><td style='padding:4px 8px;'>$($vol.Frei_GB) frei</td><td style='padding:4px 8px;width:130px;'><div style='background:#30363d;border-radius:3px;height:8px;'><div style='background:$bFarbe;width:$($vol.Prozent)%;height:8px;border-radius:3px;'></div></div><small>$($vol.Prozent)%</small></td></tr>"
                        }
                        $detailHtml += "<table style='width:100%;border-collapse:collapse;font-size:0.88em;margin-top:8px;'><tr style='color:#8b949e;'><th style='text-align:left;padding:4px 8px;'>Volume</th><th style='text-align:left;padding:4px 8px;'>Größe</th><th style='text-align:left;padding:4px 8px;'>Frei</th><th style='text-align:left;padding:4px 8px;'>Belegung</th></tr>$volZeilen</table>"
                    }
                    if ($d.Uptime -and $d.Uptime -ne "n/a") {
                        $detailHtml += "<p style='color:#8b949e;font-size:0.85em;margin:6px 0;'>Uptime: <span style='color:#e6edf3;'>$($d.Uptime)</span></p>"
                    }
                    if ($d.Docker) {
                        $dok = $d.Docker
                        $dGesamtFarbe = switch ($dok.Status) { "OK" { "#3fb950" } "WARNUNG" { "#d29922" } default { "#f85149" } }
                        $kacheln = ""
                        if ($dok.Ergebnisse -and $dok.Ergebnisse.Count -gt 0) {
                            foreach ($c in $dok.Ergebnisse) {
                                $cFarbe  = if ($c.Status -eq "OK") { "#3fb950" } else { "#f85149" }
                                $cSymbol = if ($c.Status -eq "OK") { "&#x2705;" } else { "&#x274C;" }
                                $kacheln += "<div style='display:inline-block;background:#161b22;border:1px solid $cFarbe;border-radius:5px;padding:5px 10px;margin:3px;font-size:0.85em;'><span>$cSymbol</span> <span style='color:#e6edf3;font-weight:bold;'>$($c.Name)</span> <span style='color:#6e7681;'>:$($c.Port)</span></div>"
                            }
                        }
                        $detailHtml += "<div style='margin-top:10px;padding:8px 10px;background:#21262d;border-radius:6px;border-left:3px solid $dGesamtFarbe;'><div style='color:#8b949e;font-size:0.8em;margin-bottom:5px;'>&#x1F433; Docker-Container</div><div>$kacheln</div></div>"
                    }
                }
                "mailstore" {
                    $detailHtml += "<div style='display:flex;gap:12px;flex-wrap:wrap;margin-top:8px;font-size:0.88em;'>"
                    $detailHtml += "<div style='background:#21262d;padding:8px 12px;border-radius:6px;'><div style='color:#8b949e;font-size:0.8em;'>VM</div><div style='color:$(if ($d.VM_Erreichbar) { "#3fb950" } else { "#f85149" });font-weight:bold;'>$(if ($d.VM_Erreichbar) { "OK" } else { "FEHLER" })</div></div>"
                    $detailHtml += "<div style='background:#21262d;padding:8px 12px;border-radius:6px;'><div style='color:#8b949e;font-size:0.8em;'>Dienst</div><div style='color:$(if ($d.Dienst_Laeuft) { "#3fb950" } else { "#f85149" });font-weight:bold;'>$(if ($d.Dienst_Laeuft) { "Running" } else { "GESTOPPT" })</div></div>"
                    $detailHtml += "<div style='background:#21262d;padding:8px 12px;border-radius:6px;'><div style='color:#8b949e;font-size:0.8em;'>Remoting</div><div style='color:$(if ($d.Remoting_OK) { "#3fb950" } else { "#6e7681" });'>$(if ($d.Remoting_OK) { "OK" } else { "n.v." })</div></div>"
                    if ($d.Archiv_Gesamt -gt 0) {
                        $detailHtml += "<div style='background:#21262d;padding:8px 12px;border-radius:6px;'><div style='color:#8b949e;font-size:0.8em;'>Archiv</div><div style='color:#e6edf3;'>$($d.Archiv_Gesamt.ToString("N0")) Nachr.</div></div>"
                    }
                    $detailHtml += "</div>"
                    if ($d.Kritische_Jobs -and $d.Kritische_Jobs.Count -gt 0) {
                        $jobZeilen = ""
                        foreach ($job in $d.Kritische_Jobs) {
                            $jFarbe   = if ($job.Bekannt) { "#d29922" } else { "#f85149" }
                            $bekannt  = if ($job.Bekannt) { " <small style='color:#6e7681;'>(bekannt)</small>" } else { "" }
                            $jobZeilen += "<tr><td style='padding:4px 8px;font-size:0.85em;'>$($job.Name)$bekannt</td><td style='padding:4px 8px;color:$jFarbe;'>$($job.Fehler) Fehler</td></tr>"
                        }
                        $detailHtml += "<table style='width:100%;border-collapse:collapse;margin-top:8px;'><tr style='color:#8b949e;'><th style='text-align:left;padding:4px 8px;font-size:0.85em;'>Fehler-Job</th><th style='text-align:left;padding:4px 8px;font-size:0.85em;'>Fehler</th></tr>$jobZeilen</table>"
                    }
                }
                "elwa_heizstab" {
                    $tFarbe = if ($d.Warnung) { "#f85149" } else {
                        $tWert = 0
                        if ($d.Temperatur -and [double]::TryParse(($d.Temperatur -replace '°C',''), [ref]$tWert) -and $tWert -gt 60) { "#d29922" } else { "#3fb950" }
                    }
                    $detailHtml += "<div style='display:flex;gap:16px;flex-wrap:wrap;margin-top:8px;'>"
                    $detailHtml += "<div style='background:#21262d;padding:10px 16px;border-radius:6px;text-align:center;'><div style='color:#8b949e;font-size:0.8em;'>Temperatur</div><div style='font-size:1.5em;color:$tFarbe;font-weight:bold;'>$($d.Temperatur)</div></div>"
                    $detailHtml += "<div style='background:#21262d;padding:10px 16px;border-radius:6px;text-align:center;'><div style='color:#8b949e;font-size:0.8em;'>Heizleistung</div><div style='font-size:1.5em;color:#58a6ff;font-weight:bold;'>$($d.Leistung_W)</div></div>"
                    $detailHtml += "<div style='background:#21262d;padding:10px 16px;border-radius:6px;text-align:center;'><div style='color:#8b949e;font-size:0.8em;'>PV-Überschuss</div><div style='font-size:1.1em;color:$(if ($d.BlockActive) { "#d29922" } else { "#3fb950" });'>$(if ($d.BlockActive) { "Blockiert" } else { "Aktiv" })</div></div>"
                    $detailHtml += "<div style='background:#21262d;padding:10px 16px;border-radius:6px;text-align:center;'><div style='color:#8b949e;font-size:0.8em;'>Ctrl-State</div><div style='font-size:0.95em;color:#e6edf3;'>$($d.CtrlState)</div></div>"
                    $detailHtml += "</div>"
                    if ($d.FwVersion -and $d.FwVersion -ne "n/a") {
                        $detailHtml += "<p style='color:#8b949e;font-size:0.8em;margin:6px 0;'>Firmware: $($d.FwVersion)</p>"
                    }
                }
                "sma_homemanager" {
                    $swFarbe = if ($d.Speedwire_Aktiv) { "#3fb950" } else { "#f85149" }
                    $detailHtml += "<div style='margin-top:8px;font-size:0.9em;'><span style='color:#8b949e;'>Speedwire UDP 9522: </span><span style='color:$swFarbe;font-weight:bold;'>$(if ($d.Speedwire_Aktiv) { "AKTIV" } else { "INAKTIV – PV-Anlage ausgefallen?" })</span></div>"
                }
                "raspberry" {
                    if ($d.Queries_Heute -ne $null) {
                        $bFarbe = if ([double]($d.Blockierrate -replace '%','') -lt 5) { "#f85149" } else { "#3fb950" }
                        $detailHtml += "<div style='display:flex;gap:12px;flex-wrap:wrap;margin-top:8px;'>"
                        $detailHtml += "<div style='background:#21262d;padding:8px 12px;border-radius:6px;'><div style='color:#8b949e;font-size:0.8em;'>Blockierrate</div><div style='font-size:1.3em;color:$bFarbe;font-weight:bold;'>$($d.Blockierrate)</div></div>"
                        $detailHtml += "<div style='background:#21262d;padding:8px 12px;border-radius:6px;'><div style='color:#8b949e;font-size:0.8em;'>Queries heute</div><div style='font-size:1.3em;color:#e6edf3;'>$($d.Queries_Heute)</div></div>"
                        $detailHtml += "<div style='background:#21262d;padding:8px 12px;border-radius:6px;'><div style='color:#8b949e;font-size:0.8em;'>Aktive Clients</div><div style='font-size:1.3em;color:#e6edf3;'>$($d.Aktive_Clients)</div></div>"
                        $detailHtml += "<div style='background:#21262d;padding:8px 12px;border-radius:6px;'><div style='color:#8b949e;font-size:0.8em;'>Gravity-Domains</div><div style='font-size:1.3em;color:#8b949e;'>$($d.Gravity_Liste)</div></div>"
                        $detailHtml += "</div>"
                    }
                }
                { $_ -in @("kamera_reolink","kamera_instar") } {
                    $rtspF = if ($d.RTSP_Port -eq "OFFEN") { "#3fb950" } else { "#f85149" }
                    $httpF = if ($d.HTTP_Port -eq "OFFEN") { "#3fb950" } else { "#f85149" }
                    $httpPortNr = if ($d.HTTP_PortNr) { $d.HTTP_PortNr } else { "?" }
                    $detailHtml += "<div style='margin-top:8px;font-size:0.9em;display:flex;gap:16px;flex-wrap:wrap;'>"
                    $detailHtml += "<span><span style='color:#8b949e;'>RTSP 554: </span><span style='color:$rtspF;font-weight:bold;'>$($d.RTSP_Port)</span></span>"
                    $detailHtml += "<span><span style='color:#8b949e;'>HTTP $httpPortNr`: </span><span style='color:$httpF;font-weight:bold;'>$($d.HTTP_Port)</span></span>"
                    if ($d.Stream_Aktiv -eq $true) {
                        $detailHtml += "<span style='color:#3fb950;'>Stream OK – $($d.Aufloesung) $($d.Codec)</span>"
                    }
                    if ($d.Lockout_Aktiv) {
                        $detailHtml += "<span style='color:#d29922;'>&#x26A0; Lockout-Schutz aktiv</span>"
                    }
                    $detailHtml += "</div>"
                    if ($d.Snapshot_B64) {
                        $detailHtml += "<div style='margin-top:8px;'><img src='data:image/jpeg;base64,$($d.Snapshot_B64)' style='max-width:320px;border-radius:4px;border:1px solid #30363d;' /></div>"
                    }
                }
            }
        }

        $detailBlock = if ($detailHtml) {
            "<div id='det_$($e.IP -replace '[\.:]','_')' style='display:none;padding:12px 14px;background:#0d1117;border-top:1px solid #30363d;'>$detailHtml</div>"
        } else { "" }
        $onclick = if ($detailHtml) {
            "onclick=""var d=document.getElementById('det_$($e.IP -replace '[\.:]','_')');d.style.display=d.style.display=='none'?'block':'none'"" style='cursor:pointer;'"
        } else { "" }

        $tabelleZeilen += @"
<tr $onclick style='background:$hgFarbe;border-bottom:1px solid #21262d;'>
  <td style='padding:8px 10px;font-size:1.2em;text-align:center;'>$icon</td>
  <td style='padding:8px 10px;font-weight:500;'>$($e.Geraet)</td>
  <td style='padding:8px 10px;font-family:monospace;color:#8b949e;font-size:0.9em;'>$($e.IP)</td>
  <td style='padding:8px 10px;font-size:0.82em;color:#6e7681;'>$portStr</td>
  <td style='padding:8px 10px;'>$perfHtml</td>
  <td style='padding:8px 10px;'><span style='color:$(Get-StatusFarbe -Status $e.CheckStatus);font-weight:bold;'>$($e.CheckStatus)</span></td>
  <td style='padding:8px 10px;font-size:0.85em;color:#8b949e;'>$($e.Info)</td>
</tr>
$(if ($detailBlock) { "<tr><td colspan='7' style='padding:0;'>$detailBlock</td></tr>" })
"@
    }

    # ── Externe Logins Sektion ────────────────────────────────────────────────
    $loginHtml = ""
    if ($LoginResult -and $LoginResult.Eintraege) {
        $loginZeilen = ""
        foreach ($eintrag in $LoginResult.Eintraege) {
            $eFarbe = switch -Regex ($eintrag.Ergebnis) {
                "Fehlversuch" { "#f85149" }
                "Erfolg"      { "#3fb950" }
                "VPN"         { "#d29922" }
                default       { "#8b949e" }
            }
            $loginZeilen += "<tr><td style='padding:5px 10px;font-size:0.83em;color:#8b949e;'>$($eintrag.Zeitstempel)</td><td style='padding:5px 10px;font-family:monospace;font-size:0.83em;'>$($eintrag.QuellIP)</td><td style='padding:5px 10px;font-size:0.83em;'>$($eintrag.Zielgeraet)</td><td style='padding:5px 10px;font-size:0.83em;'>$($eintrag.Typ)</td><td style='padding:5px 10px;font-size:0.83em;color:$eFarbe;'>$($eintrag.Ergebnis)</td></tr>"
        }
        $warnBanner = if ($LoginResult.Warnung) {
            "<div style='background:#f85149;color:#fff;padding:10px 14px;border-radius:6px;margin-bottom:10px;font-weight:bold;'>WARNUNG: $($LoginResult.Verdaechtige) Fehlversuche in den letzten 24 Stunden!</div>"
        } else { "" }
        $loginHtml = @"
<div style='margin-top:32px;'>
  <h2 style='color:#58a6ff;font-size:1.05em;margin-bottom:10px;'>Externe Zugriffe – Letzte 24 Stunden</h2>
  $warnBanner
  <table style='width:100%;border-collapse:collapse;background:#161b22;border-radius:8px;overflow:hidden;'>
    <thead><tr style='background:#21262d;'><th style='padding:8px 10px;text-align:left;color:#8b949e;font-size:0.83em;'>Zeit</th><th style='padding:8px 10px;text-align:left;color:#8b949e;font-size:0.83em;'>Von IP</th><th style='padding:8px 10px;text-align:left;color:#8b949e;font-size:0.83em;'>Zielgerät</th><th style='padding:8px 10px;text-align:left;color:#8b949e;font-size:0.83em;'>Typ</th><th style='padding:8px 10px;text-align:left;color:#8b949e;font-size:0.83em;'>Ergebnis</th></tr></thead>
    <tbody>$loginZeilen</tbody>
  </table>
</div>
"@
    }

    # ── ntopng Sektion ───────────────────────────────────────────────────────
    $ntopngHtml = ""
    if ($NtopngResult) {
        $ntopFarbe    = if ($NtopngResult.Status -eq "FEHLER") { "#f85149" } else { "#3fb950" }
        $ntopngZeilen = ""
        if ($NtopngResult.ExterneFlows -and $NtopngResult.ExterneFlows.Count -gt 0) {
            foreach ($flow in $NtopngResult.ExterneFlows) {
                $appText   = if ($flow.App) { $flow.App } else { $flow.Protokoll }
                $bytesText = if ($flow.Bytes -gt 1MB)  { "$([math]::Round($flow.Bytes/1MB,1)) MB" }
                             elseif ($flow.Bytes -gt 1KB) { "$([math]::Round($flow.Bytes/1KB,1)) KB" }
                             else { "$($flow.Bytes) B" }
                $ntopngZeilen += "<tr><td style='padding:5px 10px;font-family:monospace;font-size:0.83em;'>$($flow.ExterneIP)</td><td style='padding:5px 10px;font-family:monospace;font-size:0.83em;'>$($flow.InternIP)</td><td style='padding:5px 10px;font-size:0.83em;'>$appText :$($flow.Port)</td><td style='padding:5px 10px;font-size:0.83em;color:#8b949e;'>$bytesText</td></tr>"
            }
        }
        $ntopngTabelle = if ($ntopngZeilen) { @"
  <table style='width:100%;border-collapse:collapse;background:#161b22;border-radius:8px;overflow:hidden;'>
    <thead><tr style='background:#21262d;'><th style='padding:8px 10px;text-align:left;color:#8b949e;font-size:0.83em;'>Externe IP</th><th style='padding:8px 10px;text-align:left;color:#8b949e;font-size:0.83em;'>Interne IP</th><th style='padding:8px 10px;text-align:left;color:#8b949e;font-size:0.83em;'>App / Port</th><th style='padding:8px 10px;text-align:left;color:#8b949e;font-size:0.83em;'>Daten</th></tr></thead>
    <tbody>$ntopngZeilen</tbody>
  </table>
"@ } else { "<p style='color:#8b949e;font-size:0.85em;padding:8px 0;'>Keine aktiven externen Verbindungen.</p>" }

        $ntopngHtml = @"
<div style='margin-top:32px;'>
  <h2 style='color:#58a6ff;font-size:1.05em;margin-bottom:6px;'>ntopng – Aktive externe Verbindungen</h2>
  <p style='color:$ntopFarbe;font-size:0.88em;margin-bottom:10px;'>$($NtopngResult.Info)</p>
  $ntopngTabelle
</div>
"@
    }

    # ── Vollständiger HTML-Report ────────────────────────────────────────────
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
.container{max-width:1300px;margin:0 auto;}
h1{color:#58a6ff;font-size:1.4em;margin-bottom:2px;}
.sub{color:#8b949e;font-size:0.88em;margin-bottom:14px;}
.banner{background:$bannerFarbe;color:#fff;padding:12px 18px;border-radius:8px;font-size:1.15em;font-weight:bold;margin-bottom:14px;text-align:center;}
.stats{display:flex;gap:10px;margin-bottom:18px;flex-wrap:wrap;}
.stat{background:#161b22;border-radius:8px;padding:10px 16px;flex:1;min-width:90px;text-align:center;}
.stat-zahl{font-size:1.8em;font-weight:bold;}
.stat-label{font-size:0.78em;color:#8b949e;margin-top:2px;}
table{width:100%;border-collapse:collapse;background:#161b22;border-radius:8px;overflow:hidden;}
thead tr{background:#21262d;}
th{padding:9px 10px;text-align:left;color:#8b949e;font-weight:500;font-size:0.85em;}
tr:hover{filter:brightness(1.07);}
.footer{margin-top:24px;color:#6e7681;font-size:0.78em;text-align:center;padding-top:14px;border-top:1px solid #21262d;}
@media(max-width:700px){.stats{flex-direction:column;}td,th{padding:5px 6px;font-size:0.8em;}}
</style>
</head>
<body>
<div class="container">
  <h1>&#x1F3E0; Heimnetz Monitor</h1>
  <div class="sub">$($jetzt.ToString('dd.MM.yyyy HH:mm:ss')) Uhr &nbsp;|&nbsp; Laufzeit: $($LaufzeitSek)s &nbsp;|&nbsp; Nächste Prüfung: $naechsteCheck Uhr</div>
  <div class="banner">$bannerText</div>
  <div class="stats">
    <div class="stat"><div class="stat-zahl" style="color:#3fb950;">$AnzahlOK</div><div class="stat-label">OK</div></div>
    <div class="stat"><div class="stat-zahl" style="color:#d29922;">$AnzahlWarn</div><div class="stat-label">Warnungen</div></div>
    <div class="stat"><div class="stat-zahl" style="color:#f85149;">$AnzahlFehler</div><div class="stat-label">Fehler</div></div>
    <div class="stat"><div class="stat-zahl" style="color:#58a6ff;">$gesamtGeraete</div><div class="stat-label">Geräte</div></div>
    <div class="stat"><div class="stat-zahl" style="color:#8b949e;">$($LaufzeitSek)s</div><div class="stat-label">Laufzeit</div></div>
  </div>
  <table>
    <thead>
      <tr>
        <th style="width:40px;"></th>
        <th>Gerät</th>
        <th>IP-Adresse</th>
        <th>Port(s)</th>
        <th>Antwortzeit</th>
        <th>Status</th>
        <th>Details</th>
      </tr>
    </thead>
    <tbody>
      $tabelleZeilen
    </tbody>
  </table>
  $loginHtml
  $ntopngHtml
  <div class="footer">
    $gesamtGeraete Geräte &nbsp;|&nbsp; $AnzahlOK OK &nbsp;|&nbsp; $AnzahlWarn Warnungen &nbsp;|&nbsp; $AnzahlFehler Fehler &nbsp;|&nbsp;
    Laufzeit: $($LaufzeitSek)s &nbsp;|&nbsp; Nächste Prüfung: $naechsteCheck Uhr &nbsp;|&nbsp;
    Heimnetz Monitor v2.0 | $(Get-Date -Format 'MMMM yyyy')
  </div>
</div>
</body>
</html>
"@
}
