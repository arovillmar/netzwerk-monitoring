#Requires -Version 5.1
Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$SkriptPfad = Split-Path -Parent $MyInvocation.MyCommand.Path
$CredPfad   = Join-Path $SkriptPfad "credentials.json"
$ConfigPfad = Join-Path $SkriptPfad "config.json"

. (Join-Path $SkriptPfad "modules\Check-EmailDelivery.ps1")

Clear-Host
Write-Host ""
Write-Host "  +==================================================+" -ForegroundColor Cyan
Write-Host "  |   Heimnetz Monitor - E-Mail Zustellungstest     |" -ForegroundColor Cyan
Write-Host "  +==================================================+" -ForegroundColor Cyan
Write-Host ""

# Config laden
if (-not (Test-Path $ConfigPfad)) {
    Write-Host "  FEHLER: config.json nicht gefunden." -ForegroundColor Red
    exit 1
}
$Config = Get-Content $ConfigPfad -Raw -Encoding UTF8 | ConvertFrom-Json
$smtp   = $Config.einstellungen

# Credentials laden
if (-not (Test-Path $CredPfad)) {
    Write-Host "  FEHLER: credentials.json nicht gefunden." -ForegroundColor Red
    Write-Host "  Bitte zuerst: .\Setup-Credentials.ps1" -ForegroundColor Yellow
    exit 1
}

$credRaw = Get-Content $CredPfad -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $credRaw.smtp_pass -or $credRaw.smtp_pass.Length -lt 10) {
    Write-Host "  FEHLER: SMTP-Passwort nicht gesetzt." -ForegroundColor Red
    Write-Host "  Bitte: .\Setup-Credentials.ps1 (Punkt 1 - SMTP)" -ForegroundColor Yellow
    exit 1
}

$smtpPassSecure = $credRaw.smtp_pass | ConvertTo-SecureString

Write-Host "  SMTP-Server : $($smtp.smtp_host):$($smtp.smtp_port)" -ForegroundColor Gray
Write-Host "  Von         : $($smtp.smtp_von)" -ForegroundColor Gray
Write-Host "  An          : $($smtp.smtp_an)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Sende Test-E-Mail..." -ForegroundColor Cyan

$result = Check-EmailDelivery `
    -SmtpHost   $smtp.smtp_host `
    -SmtpPort   $smtp.smtp_port `
    -Von        $smtp.smtp_von `
    -An         $smtp.smtp_an `
    -PassSecure $smtpPassSecure

Write-Host ""
$farbe = if ($result.Status -eq "OK") { "Green" } else { "Red" }
Write-Host "  Status      : $($result.Status)" -ForegroundColor $farbe
Write-Host "  TCP         : $(if ($result.TCP_OK) { 'OK' } else { 'FEHLER' })" -ForegroundColor $(if ($result.TCP_OK) { "Green" } else { "Red" })
Write-Host "  Auth        : $(if ($result.Auth_OK) { 'OK' } else { 'FEHLER' })" -ForegroundColor $(if ($result.Auth_OK) { "Green" } else { "Red" })
Write-Host "  Gesendet    : $(if ($result.Gesendet_OK) { 'OK' } else { 'FEHLER' })" -ForegroundColor $(if ($result.Gesendet_OK) { "Green" } else { "Red" })
Write-Host "  Test-ID     : $($result.Test_ID)" -ForegroundColor Gray
Write-Host ""
Write-Host "  $($result.Info)" -ForegroundColor $(if ($result.Status -eq "OK") { "Green" } else { "Yellow" })
Write-Host ""

if ($result.Status -eq "OK") {
    Write-Host "  Bitte Posteingang von $($smtp.smtp_an) pruefen." -ForegroundColor Cyan
    Write-Host "  Betreff: [Heimnetz Monitor] E-Mail Test ... (ID: $($result.Test_ID))" -ForegroundColor Gray
}
Write-Host ""
