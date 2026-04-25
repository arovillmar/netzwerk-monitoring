function Send-Alert {
    param(
        [Parameter(Mandatory)][ValidateSet("Alarm","Warnung","Tagesbericht","Entwarnung")]
        [string]$Typ,
        [array]$Ergebnisse    = @(),
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
            "ALARM - Heimnetz ALARM - $anzahl Fehler - [$jetztStr]"
        }
        "Warnung"      {
            $anzahl = ($Ergebnisse | Where-Object { $_.CheckStatus -eq "WARNUNG" }).Count
            "WARNUNG - Heimnetz Warnung - $anzahl Warnungen - [$jetztStr]"
        }
        "Tagesbericht" { "Tagesbericht - Heimnetz Tagesbericht - [$($jetzt.ToString('dd.MM.yyyy'))]" }
        "Entwarnung"   { "OK - Heimnetz OK - Problem behoben - [$($jetzt.ToString('HH:mm'))]" }
    }

    $body = New-AlertBody -Typ $Typ -Ergebnisse $Ergebnisse -Zeitstempel $jetztStr

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
        [string]$Zeitstempel
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
        $tabellenZeilen += @"
        <tr>
          <td style='padding:6px 10px;border-bottom:1px solid #30363d;'>$($e.Geraet)</td>
          <td style='padding:6px 10px;border-bottom:1px solid #30363d;font-family:monospace;'>$($e.IP)</td>
          <td style='padding:6px 10px;border-bottom:1px solid #30363d;color:$farbe;font-weight:bold;'>$symbol</td>
          <td style='padding:6px 10px;border-bottom:1px solid #30363d;font-size:0.9em;'>$($e.Info)</td>
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
    <p style='color:#8b949e;font-size:0.85em;margin-top:20px;'>
      Heimnetz Monitor v1.0 | Automatisch generiert am $Zeitstempel
    </p>
  </div>
</body>
</html>
"@
}
