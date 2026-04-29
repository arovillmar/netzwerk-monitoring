#Requires -Version 5.1
Set-StrictMode -Off
$ErrorActionPreference = "Continue"

Clear-Host
Write-Host ""
Write-Host "  Reolink Login-Test" -ForegroundColor Cyan
Write-Host "  ==================" -ForegroundColor Cyan
Write-Host ""

$ip   = Read-Host "  Kamera-IP (Enter = 192.168.80.76)"
if (-not $ip) { $ip = "192.168.80.76" }

$user = Read-Host "  Benutzername (Enter = admin)"
if (-not $user) { $user = "admin" }

$secPass = Read-Host "  Passwort" -AsSecureString
$bstr    = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
$pass    = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

Write-Host ""
Write-Host "  Passwort-Laenge: $($pass.Length) Zeichen" -ForegroundColor Gray

# Variante A: Array mit ConvertTo-Json
$loginObj  = @([PSCustomObject]@{
    cmd    = "Login"
    action = 0
    param  = @{ User = @{ userName = $user; password = $pass } }
})
$bodyA = $loginObj | ConvertTo-Json -Depth 6 -Compress
if (-not $bodyA.StartsWith('[')) { $bodyA = "[$bodyA]" }

# Variante B: String-Konkatenation (umgeht ConvertTo-Json)
$passEsc = $pass -replace '\\','\\' -replace '"','\"'
$bodyB = "[{`"cmd`":`"Login`",`"action`":0,`"param`":{`"User`":{`"userName`":`"$user`",`"password`":`"$passEsc`"}}}]"

# Variante C: ohne Array-Wrapper
$bodyC = "{`"cmd`":`"Login`",`"action`":0,`"param`":{`"User`":{`"userName`":`"$user`",`"password`":`"$passEsc`"}}}"

Write-Host "  Body A (ConvertTo-Json): $($bodyA -replace '"password":"[^"]*"','"password":"***"')" -ForegroundColor DarkGray
Write-Host "  Body B (String-Build):   $($bodyB -replace '"password":"[^"]*"','"password":"***"')" -ForegroundColor DarkGray
Write-Host ""

$ssl = @{ SkipCertificateCheck = $true }

foreach ($endpoint in @("https://$ip/cgi-bin/api.cgi", "https://$ip/api.cgi")) {
    Write-Host "  ── Endpoint: $endpoint ──" -ForegroundColor Cyan

    foreach ($variant in @(
        @{ Name = "A (ConvertTo-Json, Array)"; Body = $bodyA },
        @{ Name = "B (String-Build, Array)";   Body = $bodyB },
        @{ Name = "C (String-Build, kein Array)"; Body = $bodyC }
    )) {
        Write-Host "     Variante $($variant.Name) ..." -ForegroundColor Gray -NoNewline
        try {
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($variant.Body)
            $r = Invoke-RestMethod -Uri $endpoint -Method Post @ssl `
                -Body $bodyBytes -ContentType "application/json" -TimeoutSec 8 -ErrorAction Stop
            $code = if ($r -is [array]) { $r[0].code } else { $r.code }
            if ($code -eq 0) {
                $token = if ($r -is [array]) { $r[0].value.Token.name } else { $r.value.Token.name }
                Write-Host " CODE 0 - LOGIN ERFOLGREICH! Token: $($token.Substring(0,8))..." -ForegroundColor Green
                $pass = $null
                exit 0
            } else {
                $detail = if ($r -is [array]) { $r[0].error.detail } else { $r.error.detail }
                Write-Host " Code $code ($detail)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host ""
}

$pass = $null
Write-Host "  Kein Login erfolgreich." -ForegroundColor Red
Write-Host ""
