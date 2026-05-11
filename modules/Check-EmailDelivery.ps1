function Check-EmailDelivery {
    param(
        [Parameter(Mandatory)][string]$SmtpHost,
        [Parameter(Mandatory)][int]$SmtpPort,
        [Parameter(Mandatory)][string]$Von,
        [Parameter(Mandatory)][string]$An,
        [Parameter(Mandatory)][System.Security.SecureString]$PassSecure
    )

    $zeitstempel = (Get-Date).ToString("dd.MM.yyyy HH:mm:ss")
    $testId      = (Get-Date).ToString("yyyyMMddHHmmss")

    # Schritt 1: TCP-Verbindung testen
    $tcpOK = $false
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar  = $tcp.BeginConnect($SmtpHost, $SmtpPort, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne(5000, $false)
        if ($ok -and $tcp.Connected) { $tcpOK = $true }
        $tcp.Close()
    }
    catch {}

    if (-not $tcpOK) {
        return [PSCustomObject]@{
            Status      = "FEHLER"
            TCP_OK      = $false
            Auth_OK     = $false
            Gesendet_OK = $false
            Test_ID     = $testId
            Info        = "SMTP-Server $SmtpHost`:$SmtpPort nicht erreichbar (TCP)"
        }
    }

    # Schritt 2: Auth + Senden
    $authOK  = $false
    $sendOK  = $false
    $fehler  = ""

    try {
        $bstr     = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PassSecure)
        $passKlar = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        $cred = New-Object System.Net.NetworkCredential($Von, $passKlar)
        $passKlar = $null

        $smtp                   = New-Object System.Net.Mail.SmtpClient($SmtpHost, $SmtpPort)
        $smtp.EnableSsl         = $true
        $smtp.Credentials       = $cred
        $smtp.DeliveryMethod    = [System.Net.Mail.SmtpDeliveryMethod]::Network
        $smtp.Timeout           = 15000

        $mail                   = New-Object System.Net.Mail.MailMessage
        $mail.From              = $Von
        $mail.To.Add($An)
        $mail.Subject           = "[Heimnetz Monitor] E-Mail Test $zeitstempel (ID: $testId)"
        $mail.IsBodyHtml        = $true
        $mail.SubjectEncoding   = [System.Text.Encoding]::UTF8
        $mail.BodyEncoding      = [System.Text.Encoding]::UTF8
        $mail.Body = @"
<!DOCTYPE html>
<html>
<head><meta charset='UTF-8'></head>
<body style='background:#0d1117;color:#e6edf3;font-family:Segoe UI,Arial,sans-serif;padding:20px;'>
  <div style='max-width:600px;margin:0 auto;'>
    <h2 style='color:#3fb950;'>E-Mail Zustellung erfolgreich</h2>
    <p>Diese Test-E-Mail wurde automatisch vom Heimnetz Monitor versendet.</p>
    <table style='border-collapse:collapse;width:100%;'>
      <tr><td style='padding:4px 8px;color:#8b949e;'>Zeitstempel:</td><td style='padding:4px 8px;'>$zeitstempel</td></tr>
      <tr><td style='padding:4px 8px;color:#8b949e;'>Test-ID:</td><td style='padding:4px 8px;font-family:monospace;'>$testId</td></tr>
      <tr><td style='padding:4px 8px;color:#8b949e;'>SMTP-Server:</td><td style='padding:4px 8px;'>${SmtpHost}:${SmtpPort}</td></tr>
      <tr><td style='padding:4px 8px;color:#8b949e;'>Von:</td><td style='padding:4px 8px;'>$Von</td></tr>
      <tr><td style='padding:4px 8px;color:#8b949e;'>An:</td><td style='padding:4px 8px;'>$An</td></tr>
    </table>
    <p style='color:#8b949e;font-size:0.85em;margin-top:20px;'>
      Wenn diese E-Mail ankam, funktioniert der gesamte E-Mail-Versand korrekt.
    </p>
  </div>
</body>
</html>
"@

        $authOK = $true
        $smtp.Send($mail)
        $mail.Dispose()
        $smtp.Dispose()
        $sendOK = $true
    }
    catch {
        $fehler = $_.Exception.Message
        if ($fehler -match "authenticat|credentials|password|535") {
            $fehler = "Authentifizierung fehlgeschlagen – Passwort pruefen"
        }
    }

    $status = if ($sendOK) { "OK" } elseif ($authOK) { "FEHLER" } else { "FEHLER" }
    $info   = if ($sendOK) {
        "Test-E-Mail gesendet an $An (ID: $testId) – bitte Posteingang pruefen"
    } elseif ($authOK) {
        "Auth OK, Senden fehlgeschlagen: $fehler"
    } else {
        "SMTP-Fehler: $fehler"
    }

    return [PSCustomObject]@{
        Status      = $status
        TCP_OK      = $tcpOK
        Auth_OK     = $authOK
        Gesendet_OK = $sendOK
        Test_ID     = $testId
        Info        = $info
    }
}
