function Send-Alert {
    param(
        [Parameter(Mandatory)][ValidateSet("Alarm","Warnung","Tagesbericht","Entwarnung")]
        [string]$Typ,
        [array]$Ergebnisse           = @(),
        [PSCustomObject]$LoginResult  = $null,
        [PSCustomObject]$NtopngResult = $null,
        [PSCustomObject]$SmtpConfig,
        [System.Security.SecureString]$SmtpPass
    )

    $statusPfad  = Join-Path $PSScriptRoot "..\last_status.json"
    $jetzt       = Get-Date
    $jetztStr    = $jetzt.ToString("dd.MM.yyyy HH:mm")

    # last_status.json laden
    $letzterStatus = $null
    if (Test-Path $statusPfad) {
        try { $letzterStatus = Get-Content $statusPfad -Raw | ConvertFrom-Json } catch {}
    }

    # Anti-Spam: gleicher Fehlertyp innerhalb Sperrzeit?
    $sperrzeitMin = if ($SmtpConfig.max_alarm_wiederholung_minuten) { $SmtpConfig.max_alarm_wiederholung_minuten } else { 30 }

    if ($letzterStatus -and $Typ -in @("Alarm","Warnung")) {
        $letzterZeitpunkt = $null
        try { $letzterZeitpunkt = [DateTime]::Parse($letzterStatus.letzter_alert_zeitpunkt) } catch {}
        if ($letzterZeitpunkt -and ($jetzt - $letzterZeitpunkt).TotalMinutes -lt $sperrzeitMin) {
            if ($letzterStatus.letzter_alert_typ -eq $Typ) {
                Write-Host "  [Send-Alert] Anti-Spam: $Typ bereits um $($letzterStatus.letzter_alert_zeitpunkt) gesendet – übersprungen." -ForegroundColor DarkGray
                return
            }
        }
    }

    # Entwarnung nur wenn vorheriger Status Fehler/Warnung war
    if ($Typ -eq "Entwarnung") {
        if (-not $letzterStatus -or $letzterStatus.letzter_alert_typ -notin @("Alarm","Warnung")) {
            Write-Host "  [Send-Alert] Entwarnung übersprungen – kein vorheriger Alarm." -ForegroundColor DarkGray
            return
        }
    }

    # E-Mail Betreff + Body aufbauen
    $betreff = switch ($Typ) {
        "Alarm"        {
            $anzahl = ($Ergebnisse | Where-Object { $_.CheckStatus -eq "FEHLER" }).Count
            "⚠️ Heimnetz Alert – $anzahl Probleme – [$jetztStr]"
        }
        "Warnung"      {
            $anzahl = ($Ergebnisse | Where-Object { $_.CheckStatus -in @("WARNUNG","FEHLER") }).Count
            "⚠️ Heimnetz Alert – $anzahl Probleme – [$jetztStr]"
        }
        "Tagesbericht" { "✅ Heimnetz OK – Tagesbericht $($jetzt.ToString('dd.MM.yyyy'))" }
        "Entwarnung"   { "✅ Heimnetz OK – Problem behoben [$($jetzt.ToString('HH:mm'))]" }
    }

    $body = New-AlertBody -Typ $Typ -Ergebnisse $Ergebnisse -Zeitstempel $jetztStr -LoginResult $LoginResult -NtopngResult $NtopngResult

    # SMTP senden
    try {
        $bstr     = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SmtpPass)
        $passKlar = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        $smtpCred = New-Object System.Net.NetworkCredential($SmtpConfig.smtp_von, $passKlar)
        $passKlar = $null

        $smtp = New-Object System.Net.Mail.SmtpClient($SmtpConfig.smtp_host, $SmtpConfig.smtp_port)
        $smtp.EnableSsl             = $true
        $smtp.Credentials           = $smtpCred
        $smtp.DeliveryMethod        = [System.Net.Mail.SmtpDeliveryMethod]::Network
        $smtp.Timeout               = 15000

        $mail            = New-Object System.Net.Mail.MailMessage
        $mail.From       = $SmtpConfig.smtp_von
        $mail.To.Add($SmtpConfig.smtp_an)
        $mail.Subject    = $betreff
        $mail.Body       = $body
        $mail.IsBodyHtml = $true
        $mail.SubjectEncoding = [System.Text.Encoding]::UTF8
        $mail.BodyEncoding    = [System.Text.Encoding]::UTF8

        $smtp.Send($mail)
        $mail.Dispose()
        $smtp.Dispose()

        Write-Host "  [Send-Alert] E-Mail gesendet: $betreff" -ForegroundColor Green

        # last_status.json aktualisieren
        $neuerStatus = [PSCustomObject]@{
            letzter_alert_zeitpunkt = $jetzt.ToString("yyyy-MM-dd HH:mm:ss")
            letzter_alert_typ       = $Typ
            letzter_alert_betreff   = $betreff
        }
        $neuerStatus | ConvertTo-Json | Set-Content $statusPfad -Encoding UTF8
    }
    catch {
        Write-Host "  [Send-Alert] FEHLER beim Senden: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function New-AlertBody {
    param(
        [string]$Typ,
        [array]$Ergebnisse,
        [string]$Zeitstempel,
        [PSCustomObject]$LoginResult  = $null,
        [PSCustomObject]$NtopngResult = $null
    )

    $relevante = switch ($Typ) {
        "Alarm"   { $Ergebnisse | Where-Object { $_.CheckStatus -eq "FEHLER"  } }
        "Warnung" { $Ergebnisse | Where-Object { $_.CheckStatus -in @("WARNUNG","FEHLER") } }
        default   { $Ergebnisse }
    }

    $tabellenZeilen = ""
    foreach ($e in $relevante) {
        $farbe = switch ($e.CheckStatus) {
            "FEHLER"  { "#f85149" }
            "WARNUNG" { "#d29922" }
            default   { "#3fb950" }
        }
        $symbol = switch ($e.CheckStatus) {
            "FEHLER"  { "FEHLER" }
            "WARNUNG" { "WARNUNG" }
            default   { "OK" }
        }
        $infoHauptteil  = $e.Info -replace '\s*\|\s*Docker:.*$', ''
        $infoDockerHtml = ""
        if ($e.Info -match '\|\s*(Docker:.+)$') {
            $dockerTeile = $Matches[1] -split '\s{2,}'
            $dockerBausteine = ($dockerTeile | ForEach-Object {
                if ($_ -match ':OK$')         { "<span style='color:#3fb950;'>$_</span>" }
                elseif ($_ -match ':FEHLER$') { "<span style='color:#f85149;font-weight:bold;'>$_</span>" }
                else                          { "<span style='color:#8b949e;'>$_</span>" }
            }) -join " &nbsp; "
            $infoDockerHtml = "<br><span style='color:#58a6ff;font-size:0.82em;'>&#x1F433; $dockerBausteine</span>"
        }
        $tabellenZeilen += @"
        <tr>
          <td style='padding:6px 10px;border-bottom:1px solid #30363d;'>$($e.Geraet)</td>
          <td style='padding:6px 10px;border-bottom:1px solid #30363d;font-family:monospace;'>$($e.IP)</td>
          <td style='padding:6px 10px;border-bottom:1px solid #30363d;color:$farbe;font-weight:bold;'>$symbol</td>
          <td style='padding:6px 10px;border-bottom:1px solid #30363d;font-size:0.9em;'>$infoHauptteil$infoDockerHtml</td>
        </tr>
"@
    }

    $bannerFarbe = switch ($Typ) {
        "Alarm"        { "#f85149" }
        "Warnung"      { "#d29922" }
        "Entwarnung"   { "#3fb950" }
        default        { "#58a6ff" }
    }

    $bannerText = switch ($Typ) {
        "Alarm"        { "ALARM – Fehler erkannt!" }
        "Warnung"      { "ACHTUNG – Warnungen vorhanden" }
        "Tagesbericht" { "Tagesbericht – Alle Systeme" }
        "Entwarnung"   { "Problem behoben – Alles OK" }
    }

    # Snapshot-Sektion aufbauen
    $snapshotSektionHtml = ""
    $alleKameras  = $Ergebnisse | Where-Object { $_.Typ -in @("kamera_reolink","kamera_instar") }
    $kamsWithSnap = $alleKameras | Where-Object { $_.Details -and $_.Details.Snapshot_B64 }
    if ($kamsWithSnap.Count -gt 0) {
        $snapBlocks = ""
        foreach ($k in $kamsWithSnap) {
            $statusFarbe = switch ($k.CheckStatus) { "FEHLER" { "#f85149" } "WARNUNG" { "#d29922" } default { "#3fb950" } }
            $snapBlocks += @"
      <div style='display:inline-block;vertical-align:top;margin:6px;background:#161b22;border:1px solid #30363d;border-radius:6px;padding:8px;width:260px;'>
        <div style='font-size:0.85em;font-weight:600;margin-bottom:4px;color:#e6edf3;'>$($k.Geraet)</div>
        <div style='font-size:0.78em;color:#8b949e;margin-bottom:6px;font-family:monospace;'>$($k.IP) &nbsp;<span style='color:$statusFarbe;'>$($k.CheckStatus)</span></div>
        <img src='data:image/jpeg;base64,$($k.Details.Snapshot_B64)' style='width:100%;border-radius:4px;display:block;' alt='$($k.Geraet)'>
      </div>
"@
        }
        $snapshotSektionHtml = @"
    <h2 style='color:#58a6ff;font-size:1em;margin:24px 0 8px;'>Kamera-Snapshots ($($kamsWithSnap.Count)/$($alleKameras.Count))</h2>
    <div style='background:#0d1117;border:1px solid #30363d;border-radius:6px;padding:10px;'>
      $snapBlocks
    </div>
"@
    }

    # Login-Sektion aufbauen
    $loginSektionHtml = ""
    if ($LoginResult) {
        $loginStatusFarbe = if ($LoginResult.Warnung) { "#f85149" } else { "#3fb950" }
        $loginSummary = "$($LoginResult.Info)"
        $loginZeilenHtml = ""
        if ($LoginResult.Eintraege -and $LoginResult.Eintraege.Count -gt 0) {
            foreach ($eintrag in $LoginResult.Eintraege) {
                $eFarbe = switch -Regex ($eintrag.Ergebnis) {
                    "Fehlversuch" { "#f85149" }
                    "Erfolg"      { "#3fb950" }
                    default       { "#8b949e" }
                }
                $loginZeilenHtml += "<tr><td style='padding:5px 8px;font-size:0.82em;color:#8b949e;border-bottom:1px solid #21262d;'>$($eintrag.Zeitstempel)</td><td style='padding:5px 8px;font-size:0.82em;font-family:monospace;border-bottom:1px solid #21262d;'>$($eintrag.QuellIP)</td><td style='padding:5px 8px;font-size:0.82em;border-bottom:1px solid #21262d;'>$($eintrag.Zielgeraet)</td><td style='padding:5px 8px;font-size:0.82em;color:$eFarbe;border-bottom:1px solid #21262d;'>$($eintrag.Ergebnis)</td></tr>"
            }
        }
        $loginSektionHtml = @"
    <h2 style='color:#58a6ff;font-size:1em;margin:24px 0 8px;'>Externe Zugriffe – Letzte 24h</h2>
    <p style='color:$loginStatusFarbe;font-size:0.9em;margin-bottom:8px;'>$loginSummary</p>
    $(if ($loginZeilenHtml) { @"
    <table style='width:100%;border-collapse:collapse;background:#161b22;border-radius:6px;overflow:hidden;font-size:0.85em;'>
      <thead><tr style='background:#21262d;'><th style='padding:6px 8px;text-align:left;color:#8b949e;'>Zeit</th><th style='padding:6px 8px;text-align:left;color:#8b949e;'>Von IP</th><th style='padding:6px 8px;text-align:left;color:#8b949e;'>Zielgerät</th><th style='padding:6px 8px;text-align:left;color:#8b949e;'>Ergebnis</th></tr></thead>
      <tbody>$loginZeilenHtml</tbody>
    </table>
"@ })
"@
    }

    # ntopng Sektion – aktive externe Verbindungen
    $ntopngSektionHtml = ""
    if ($NtopngResult) {
        $ntopStatusFarbe = if ($NtopngResult.Status -eq "FEHLER") { "#f85149" } else { "#3fb950" }
        $ntopngZeilenHtml = ""
        if ($NtopngResult.ExterneFlows -and $NtopngResult.ExterneFlows.Count -gt 0) {
            foreach ($flow in $NtopngResult.ExterneFlows) {
                $appText  = if ($flow.App) { $flow.App } else { $flow.Protokoll }
                $bytesText = if ($flow.Bytes -gt 1MB) { "$([math]::Round($flow.Bytes/1MB,1)) MB" }
                             elseif ($flow.Bytes -gt 1KB) { "$([math]::Round($flow.Bytes/1KB,1)) KB" }
                             else { "$($flow.Bytes) B" }
                $ntopngZeilenHtml += "<tr><td style='padding:5px 8px;font-size:0.82em;font-family:monospace;border-bottom:1px solid #21262d;'>$($flow.ExterneIP)</td><td style='padding:5px 8px;font-size:0.82em;font-family:monospace;border-bottom:1px solid #21262d;'>$($flow.InternIP)</td><td style='padding:5px 8px;font-size:0.82em;border-bottom:1px solid #21262d;'>$appText :$($flow.Port)</td><td style='padding:5px 8px;font-size:0.82em;color:#8b949e;border-bottom:1px solid #21262d;'>$bytesText</td></tr>"
            }
        }
        $ntopngTabelleHtml = if ($ntopngZeilenHtml) { @"
    <table style='width:100%;border-collapse:collapse;background:#161b22;border-radius:6px;overflow:hidden;font-size:0.85em;'>
      <thead><tr style='background:#21262d;'><th style='padding:6px 8px;text-align:left;color:#8b949e;'>Externe IP</th><th style='padding:6px 8px;text-align:left;color:#8b949e;'>Interne IP</th><th style='padding:6px 8px;text-align:left;color:#8b949e;'>App / Port</th><th style='padding:6px 8px;text-align:left;color:#8b949e;'>Daten</th></tr></thead>
      <tbody>$ntopngZeilenHtml</tbody>
    </table>
"@ } else { "<p style='color:#8b949e;font-size:0.85em;'>Keine aktiven externen Verbindungen.</p>" }

        $ntopngSektionHtml = @"
    <h2 style='color:#58a6ff;font-size:1em;margin:24px 0 8px;'>ntopng – Aktive externe Verbindungen</h2>
    <p style='color:$ntopStatusFarbe;font-size:0.9em;margin-bottom:8px;'>$($NtopngResult.Info)</p>
    $ntopngTabelleHtml
"@
    }

    return @"
<!DOCTYPE html>
<html>
<head><meta charset='UTF-8'></head>
<body style='background:#0d1117;color:#e6edf3;font-family:Segoe UI,Arial,sans-serif;margin:0;padding:20px;'>
  <div style='max-width:700px;margin:0 auto;'>
    <h1 style='color:#58a6ff;margin-bottom:4px;'>Heimnetz Monitor</h1>
    <p style='color:#8b949e;margin-top:0;'>$Zeitstempel</p>
    <div style='background:$bannerFarbe;color:#fff;padding:12px 16px;border-radius:6px;font-size:1.1em;font-weight:bold;margin-bottom:20px;'>
      $bannerText
    </div>
    <table style='width:100%;border-collapse:collapse;background:#161b22;border-radius:6px;overflow:hidden;'>
      <thead>
        <tr style='background:#21262d;'>
          <th style='padding:8px 10px;text-align:left;color:#8b949e;'>Gerät</th>
          <th style='padding:8px 10px;text-align:left;color:#8b949e;'>IP</th>
          <th style='padding:8px 10px;text-align:left;color:#8b949e;'>Status</th>
          <th style='padding:8px 10px;text-align:left;color:#8b949e;'>Info</th>
        </tr>
      </thead>
      <tbody>
        $tabellenZeilen
      </tbody>
    </table>
    $loginSektionHtml
    $ntopngSektionHtml
    $snapshotSektionHtml
    <p style='color:#8b949e;font-size:0.85em;margin-top:20px;'>
      Heimnetz Monitor v2.0 | Automatisch generiert am $Zeitstempel
    </p>
  </div>
</body>
</html>
"@
}
