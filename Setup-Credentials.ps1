#Requires -Version 5.1
Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$SkriptPfad = Split-Path -Parent $MyInvocation.MyCommand.Path
$CredPfad   = Join-Path $SkriptPfad "credentials.json"

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║     Heimnetz Monitor – Zugangsdaten einrichten       ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Alle Passwörter werden mit Windows DPAPI verschlüsselt." -ForegroundColor Gray
Write-Host "  Nur auf DIESEM PC entschlüsselbar!" -ForegroundColor Yellow
Write-Host "  Computername: $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host ""

# Prüfen ob bereits vorhanden
if (Test-Path $CredPfad) {
    try {
        $vorhandene = Get-Content $CredPfad -Raw | ConvertFrom-Json
        Write-Host "  Vorhandene credentials.json gefunden:" -ForegroundColor Yellow
        Write-Host "  Erstellt am:  $($vorhandene.erstellt_am)" -ForegroundColor Gray
        Write-Host "  Erstellt auf: $($vorhandene.erstellt_auf)" -ForegroundColor Gray
        Write-Host ""
        $ueberschreiben = Read-Host "  Überschreiben? (j/n)"
        if ($ueberschreiben -ne "j") {
            Write-Host ""
            Write-Host "  Abgebrochen – bestehende Credentials bleiben erhalten." -ForegroundColor Gray
            Write-Host ""
            exit 0
        }
        Write-Host ""
    }
    catch {
        Write-Host "  Vorhandene credentials.json ist beschädigt – wird neu erstellt." -ForegroundColor Yellow
        Write-Host ""
    }
}

Write-Host "  Bitte die Zugangsdaten eingeben:" -ForegroundColor Cyan
Write-Host "  (Eingabe wird nicht angezeigt)" -ForegroundColor Gray
Write-Host ""

# 1. IONOS SMTP Passwort
Write-Host "  [1/4] IONOS SMTP Passwort" -ForegroundColor White
Write-Host "        E-Mail-Konto: $((Get-Content (Join-Path $SkriptPfad 'config.json') -Raw | ConvertFrom-Json).einstellungen.smtp_von)" -ForegroundColor Gray
$smtpPass = Read-Host "        Passwort" -AsSecureString
Write-Host ""

# 2. Synology DS1525+ Passwort
Write-Host "  [2/4] Synology DS1525+ DSM Passwort" -ForegroundColor White
Write-Host "        Benutzer: Armin | IP: 192.168.80.206 | Port: 5000" -ForegroundColor Gray
$nas1Pass = Read-Host "        Passwort" -AsSecureString
Write-Host ""

# 3. Synology DS723+ Passwort
Write-Host "  [3/4] Synology DS723+ DSM Passwort" -ForegroundColor White
Write-Host "        Benutzer: Armin | IP: 192.168.80.207 | Port: 5000" -ForegroundColor Gray
$nas2Pass = Read-Host "        Passwort" -AsSecureString
Write-Host ""

# 4. Mailstore API Passwort
Write-Host "  [4/4] Mailstore API Passwort" -ForegroundColor White
Write-Host "        IP: 192.168.80.120 | Port: 8474 | Benutzer: admin" -ForegroundColor Gray
$mailstorePass = Read-Host "        Passwort" -AsSecureString
Write-Host ""

# Verschlüsseln und speichern
Write-Host "  Verschlüssele und speichere..." -ForegroundColor Gray

try {
    $credentials = [PSCustomObject]@{
        smtp_pass      = ($smtpPass     | ConvertFrom-SecureString)
        nas1_pass      = ($nas1Pass     | ConvertFrom-SecureString)
        nas2_pass      = ($nas2Pass     | ConvertFrom-SecureString)
        mailstore_pass = ($mailstorePass | ConvertFrom-SecureString)
        erstellt_am    = (Get-Date).ToString("dd.MM.yyyy HH:mm:ss")
        erstellt_auf   = $env:COMPUTERNAME
    }

    $credentials | ConvertTo-Json | Set-Content $CredPfad -Encoding UTF8

    Write-Host ""
    Write-Host "  ✓ credentials.json erfolgreich gespeichert!" -ForegroundColor Green
    Write-Host "    Pfad: $CredPfad" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Sicherheitshinweise:" -ForegroundColor Yellow
    Write-Host "  • credentials.json ist in .gitignore – wird NIEMALS auf GitHub gepusht" -ForegroundColor Gray
    Write-Host "  • Nur auf diesem PC ($env:COMPUTERNAME) entschlüsselbar (Windows DPAPI)" -ForegroundColor Gray
    Write-Host "  • SSH läuft über Key-Authentifizierung – kein Passwort in dieser Datei nötig" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Nächster Schritt: .\Setup-Task.ps1 (als Administrator ausführen)" -ForegroundColor Cyan
    Write-Host ""

    # Kurzer Entschlüsselungstest
    Write-Host "  Teste Entschlüsselung..." -ForegroundColor Gray
    try {
        $testRaw  = Get-Content $CredPfad -Raw | ConvertFrom-Json
        $testPass = $testRaw.smtp_pass | ConvertTo-SecureString
        $bstr     = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($testPass)
        $klartext = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        if ($klartext.Length -gt 0) {
            Write-Host "  ✓ Entschlüsselung erfolgreich – Credentials funktionieren." -ForegroundColor Green
        }
        $klartext = $null
    }
    catch {
        Write-Host "  ⚠ Entschlüsselungstest fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "  FEHLER beim Speichern: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}
finally {
    # SecureStrings aus dem Speicher entfernen
    $smtpPass      = $null
    $nas1Pass      = $null
    $nas2Pass      = $null
    $mailstorePass = $null
}
