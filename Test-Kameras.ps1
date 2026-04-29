#Requires -Version 5.1
Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$SkriptPfad = Split-Path -Parent $MyInvocation.MyCommand.Path
$CredPfad   = Join-Path $SkriptPfad "credentials.json"
$ConfigPfad = Join-Path $SkriptPfad "config.json"
$ModulPfad  = Join-Path $SkriptPfad "modules"

. (Join-Path $ModulPfad "Check-Camera.ps1")

# Config + Credentials laden
$Config  = Get-Content $ConfigPfad -Raw -Encoding UTF8 | ConvertFrom-Json
$credRaw = Get-Content $CredPfad   -Raw -Encoding UTF8 | ConvertFrom-Json

function ConvertTo-SecureStringSafe {
    param([string]$Wert)
    if ($Wert -and $Wert.Length -gt 10) { return ($Wert | ConvertTo-SecureString) }
    return $null
}

$ReolinkPass = ConvertTo-SecureStringSafe $credRaw.reolink_pass
$InstarPass  = ConvertTo-SecureStringSafe $credRaw.instar_pass

# Nur Kamera-Geraete
$Kameras = $Config.geraete | Where-Object { $_.aktiv -eq $true -and $_.typ -in @("kamera_reolink","kamera_instar") }

Clear-Host
Write-Host ""
Write-Host "  +==================================================+" -ForegroundColor Cyan
Write-Host "  |   Heimnetz Monitor - Kamera Test                |" -ForegroundColor Cyan
Write-Host "  +==================================================+" -ForegroundColor Cyan
Write-Host "  $($Kameras.Count) Kameras werden geprueft..." -ForegroundColor Gray
Write-Host ""

$Ergebnisse = @()

foreach ($K in $Kameras) {
    Write-Host "  Pruefe: $($K.name) ($($K.ip))..." -ForegroundColor Gray -NoNewline

    $kamTyp  = if ($K.typ -eq "kamera_reolink") { "reolink" } else { "instar" }
    $kamPass = if ($K.typ -eq "kamera_reolink") { $ReolinkPass } else { $InstarPass }
    $kamUser = if ($K.cam_user) { $K.cam_user } else { "admin" }

    $result = Check-Camera -IP $K.ip -Typ $kamTyp -Name $K.name `
        -ReolinkUser $kamUser -ReolinkPassSecure $kamPass

    $farbe = switch ($result.Status) { "OK" { "Green" } "WARNUNG" { "Yellow" } default { "Red" } }

    Write-Host "  $($result.Status)" -ForegroundColor $farbe
    Write-Host "    HTTP       : $(if ($result.HTTP_OK) { 'OFFEN' } else { 'GESCHLOSSEN' })" -ForegroundColor $(if ($result.HTTP_OK) { "Green" } else { "Red" })
    Write-Host "    API        : $($result.API_Status)" -ForegroundColor $(if ($result.API_Status -eq "OK") { "Green" } else { "Yellow" })
    Write-Host "    Stream     : $($result.Stream_Info)"
    Write-Host "    Snapshot   : $(if ($result.Snapshot_B64) { "OK ($([Math]::Round($result.Snapshot_B64.Length * 0.75 / 1024))KB)" } else { "n/a" })" `
        -ForegroundColor $(if ($result.Snapshot_B64) { "Green" } else { "Yellow" })
    Write-Host ""

    $Ergebnisse += [PSCustomObject]@{
        Name         = $K.name
        IP           = $K.ip
        Typ          = $kamTyp
        Status       = $result.Status
        HTTP_OK      = $result.HTTP_OK
        API_Status   = $result.API_Status
        Stream_Info  = $result.Stream_Info
        Snapshot_B64 = $result.Snapshot_B64
    }
}

# Zusammenfassung
$mitSnapshot = ($Ergebnisse | Where-Object { $_.Snapshot_B64 }).Count
$ohneAPI     = ($Ergebnisse | Where-Object { $_.API_Status -ne "OK" }).Count
Write-Host "  Ergebnis: $($Ergebnisse.Count) Kameras | $mitSnapshot Snapshots | $ohneAPI ohne API-Zugriff" -ForegroundColor Cyan
Write-Host ""

# HTML-Vorschau mit Snapshots erstellen und oeffnen
if ($mitSnapshot -gt 0) {
    Write-Host "  Erstelle HTML-Vorschau mit Snapshots..." -ForegroundColor Gray

    $cards = ""
    foreach ($e in $Ergebnisse) {
        $statusFarbe = switch ($e.Status) { "OK" { "#3fb950" } "WARNUNG" { "#d29922" } default { "#f85149" } }
        $imgBlock = if ($e.Snapshot_B64) {
            "<img src='data:image/jpeg;base64,$($e.Snapshot_B64)' style='width:100%;border-radius:4px;margin-top:8px;display:block;'>"
        } else {
            "<div style='width:100%;height:120px;background:#21262d;border-radius:4px;margin-top:8px;display:flex;align-items:center;justify-content:center;color:#8b949e;font-size:0.85em;'>Kein Snapshot verfuegbar</div>"
        }
        $cards += @"
    <div style='background:#161b22;border:1px solid #30363d;border-radius:8px;padding:12px;'>
      <div style='font-weight:600;font-size:1em;'>$($e.Name)</div>
      <div style='font-family:monospace;font-size:0.82em;color:#8b949e;margin:2px 0;'>$($e.IP)</div>
      <div style='font-size:0.82em;margin:2px 0;'>
        <span style='color:$statusFarbe;font-weight:bold;'>$($e.Status)</span>
        &nbsp;|&nbsp; API: $($e.API_Status)
        &nbsp;|&nbsp; $($e.Stream_Info)
      </div>
      $imgBlock
    </div>
"@
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
  <meta charset='UTF-8'>
  <title>Kamera Test – $((Get-Date).ToString('dd.MM.yyyy HH:mm'))</title>
  <style>
    body { background:#0d1117; color:#e6edf3; font-family:Segoe UI,Arial,sans-serif; margin:0; padding:20px; }
    h1   { color:#58a6ff; }
    .grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(320px,1fr)); gap:16px; max-width:1200px; }
  </style>
</head>
<body>
  <h1>Kamera Snapshots</h1>
  <p style='color:#8b949e;'>$((Get-Date).ToString('dd.MM.yyyy HH:mm:ss')) &nbsp;|&nbsp; $($Ergebnisse.Count) Kameras &nbsp;|&nbsp; $mitSnapshot Snapshots</p>
  <div class='grid'>
    $cards
  </div>
</body>
</html>
"@

    $vorschauPfad = Join-Path $SkriptPfad "reports\Kamera_Test_$((Get-Date).ToString('yyyyMMdd_HHmm')).html"
    $html | Set-Content $vorschauPfad -Encoding UTF8

    $browser = @("msedge","chrome","firefox") | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    if ($browser) { Start-Process $browser $vorschauPfad } else { Start-Process $vorschauPfad }

    Write-Host "  Vorschau geoeffnet: $vorschauPfad" -ForegroundColor Green
}
Write-Host ""
