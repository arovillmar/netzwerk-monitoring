#Requires -Version 5.1
Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$SkriptPfad = Split-Path -Parent $MyInvocation.MyCommand.Path
$CredPfad   = Join-Path $SkriptPfad "credentials.json"

Clear-Host
Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor Cyan
Write-Host "  |   Heimnetz Monitor - Zugangsdaten einrichten         |" -ForegroundColor Cyan
Write-Host "  +======================================================+" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Passwoerter werden mit Windows DPAPI verschluesselt." -ForegroundColor Gray
Write-Host "  Nur auf DIESEM PC ($env:COMPUTERNAME) entschluesselbar!" -ForegroundColor Yellow
Write-Host ""
Write-Host "  HINWEIS: Einfach ENTER druecken um einen Wert zu" -ForegroundColor Cyan
Write-Host "           behalten oder spaeter einzutragen." -ForegroundColor Cyan
Write-Host ""

# Bestehende Credentials laden (falls vorhanden)
$bestehend = $null
if (Test-Path $CredPfad) {
    try {
        $bestehend = Get-Content $CredPfad -Raw | ConvertFrom-Json
        Write-Host "  Bestehende credentials.json gefunden (erstellt: $($bestehend.erstellt_am))" -ForegroundColor Green
        Write-Host "  Bereits gesetzte Felder werden mit [GESETZT] angezeigt." -ForegroundColor Gray
        Write-Host ""
    }
    catch {
        Write-Host "  Bestehende credentials.json ist beschaedigt - wird neu erstellt." -ForegroundColor Yellow
        Write-Host ""
        $bestehend = $null
    }
}
else {
    Write-Host "  Noch keine credentials.json vorhanden - wird neu erstellt." -ForegroundColor Gray
    Write-Host ""
}

function Get-Status {
    param([string]$Wert)
    if ($Wert -and $Wert.Length -gt 10) { return "[GESETZT]" } else { return "[FEHLT]  " }
}

function Read-Passwort {
    param([string]$Bezeichnung, [string]$Hinweis, [string]$BestehenderWert)

    $status = Get-Status -Wert $BestehenderWert
    $farbe  = if ($status -eq "[GESETZT]") { "Green" } else { "Yellow" }

    Write-Host "  $status " -ForegroundColor $farbe -NoNewline
    Write-Host $Bezeichnung -ForegroundColor White
    Write-Host "           $Hinweis" -ForegroundColor Gray
    Write-Host "           (Enter = unveraendert lassen)" -ForegroundColor DarkGray

    $eingabe = Read-Host "           Passwort"

    Write-Host ""

    if ($eingabe -eq "" -or $eingabe.Length -eq 0) {
        if ($BestehenderWert -and $BestehenderWert.Length -gt 0) {
            Write-Host "           -> Bestehender Wert behalten." -ForegroundColor DarkGray
            Write-Host ""
            return $BestehenderWert
        }
        else {
            Write-Host "           -> Leer gelassen (spaeter eintragen!)." -ForegroundColor Yellow
            Write-Host ""
            return ""
        }
    }
    else {
        $secure  = $eingabe | ConvertTo-SecureString -AsPlainText -Force
        $verschl = $secure | ConvertFrom-SecureString
        $secure  = $null
        $eingabe = $null
        Write-Host "           -> Neu gesetzt und verschluesselt." -ForegroundColor Green
        Write-Host ""
        return $verschl
    }
}

# Bestehende Werte auslesen
$alt_smtp      = if ($bestehend) { $bestehend.smtp_pass      } else { "" }
$alt_nas1      = if ($bestehend) { $bestehend.nas1_pass      } else { "" }
$alt_nas2      = if ($bestehend) { $bestehend.nas2_pass      } else { "" }
$alt_mailstore = if ($bestehend) { $bestehend.mailstore_pass } else { "" }

# Status-Uebersicht anzeigen
Write-Host "  Aktueller Status:" -ForegroundColor White
Write-Host "  $(Get-Status $alt_smtp)      [1] IONOS SMTP Passwort" -ForegroundColor $(if ((Get-Status $alt_smtp) -eq "[GESETZT]") { "Green" } else { "Yellow" })
Write-Host "  $(Get-Status $alt_nas1)      [2] Synology DS1525+ Passwort" -ForegroundColor $(if ((Get-Status $alt_nas1) -eq "[GESETZT]") { "Green" } else { "Yellow" })
Write-Host "  $(Get-Status $alt_nas2)      [3] Synology DS723+ Passwort" -ForegroundColor $(if ((Get-Status $alt_nas2) -eq "[GESETZT]") { "Green" } else { "Yellow" })
Write-Host "  $(Get-Status $alt_mailstore) [4] Mailstore API Passwort" -ForegroundColor $(if ((Get-Status $alt_mailstore) -eq "[GESETZT]") { "Green" } else { "Yellow" })
Write-Host ""
Write-Host "  Jetzt Passwoerter eingeben (Enter = unveraendert):" -ForegroundColor Cyan
Write-Host ""

# Passwort-Eingaben
try {
    $smtpVon = ""
    try { $smtpVon = ((Get-Content (Join-Path $SkriptPfad "config.json") -Raw) | ConvertFrom-Json).einstellungen.smtp_von } catch {}

    $neu_smtp = Read-Passwort `
        -Bezeichnung "[1/4] IONOS SMTP Passwort" `
        -Hinweis     "E-Mail: $smtpVon | Server: smtp.ionos.de:587" `
        -BestehenderWert $alt_smtp

    $neu_nas1 = Read-Passwort `
        -Bezeichnung "[2/4] Synology DS1525+ DSM Passwort" `
        -Hinweis     "Benutzer: Armin | IP: 192.168.80.206 | Port: 5000" `
        -BestehenderWert $alt_nas1

    $neu_nas2 = Read-Passwort `
        -Bezeichnung "[3/4] Synology DS723+ DSM Passwort" `
        -Hinweis     "Benutzer: Armin | IP: 192.168.80.207 | Port: 5000" `
        -BestehenderWert $alt_nas2

    $neu_mailstore = Read-Passwort `
        -Bezeichnung "[4/4] Mailstore API Passwort" `
        -Hinweis     "IP: 192.168.80.120 | Port: 8474 | Benutzer: admin" `
        -BestehenderWert $alt_mailstore

    # Speichern
    $credentials = [PSCustomObject]@{
        smtp_pass      = $neu_smtp
        nas1_pass      = $neu_nas1
        nas2_pass      = $neu_nas2
        mailstore_pass = $neu_mailstore
        erstellt_am    = (Get-Date).ToString("dd.MM.yyyy HH:mm:ss")
        erstellt_auf   = $env:COMPUTERNAME
    }

    $credentials | ConvertTo-Json | Set-Content $CredPfad -Encoding UTF8

    # Abschlusstatus
    Write-Host "  +------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  Gespeichert! Aktueller Status:" -ForegroundColor Green
    Write-Host ""
    Write-Host "  $(Get-Status $neu_smtp)      [1] IONOS SMTP Passwort" -ForegroundColor $(if ((Get-Status $neu_smtp) -eq "[GESETZT]") { "Green" } else { "Yellow" })
    Write-Host "  $(Get-Status $neu_nas1)      [2] Synology DS1525+ Passwort" -ForegroundColor $(if ((Get-Status $neu_nas1) -eq "[GESETZT]") { "Green" } else { "Yellow" })
    Write-Host "  $(Get-Status $neu_nas2)      [3] Synology DS723+ Passwort" -ForegroundColor $(if ((Get-Status $neu_nas2) -eq "[GESETZT]") { "Green" } else { "Yellow" })
    Write-Host "  $(Get-Status $neu_mailstore) [4] Mailstore API Passwort" -ForegroundColor $(if ((Get-Status $neu_mailstore) -eq "[GESETZT]") { "Green" } else { "Yellow" })
    Write-Host ""

    $fehlend = @()
    if ((Get-Status $neu_smtp)      -ne "[GESETZT]") { $fehlend += "SMTP" }
    if ((Get-Status $neu_nas1)      -ne "[GESETZT]") { $fehlend += "DS1525+" }
    if ((Get-Status $neu_nas2)      -ne "[GESETZT]") { $fehlend += "DS723+" }
    if ((Get-Status $neu_mailstore) -ne "[GESETZT]") { $fehlend += "Mailstore" }

    if ($fehlend.Count -gt 0) {
        Write-Host "  Noch fehlend: $($fehlend -join ', ')" -ForegroundColor Yellow
        Write-Host "  Skript erneut ausfuehren wenn Passwoerter bereit sind." -ForegroundColor Gray
    }
    else {
        Write-Host "  Alle 4 Passwoerter gesetzt!" -ForegroundColor Green
        Write-Host "  Naechster Schritt: .\Setup-Task.ps1 (als Administrator)" -ForegroundColor Cyan
    }
    Write-Host ""
}
catch {
    Write-Host "  FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
