#Requires -Version 5.1
Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$SkriptPfad = Split-Path -Parent $MyInvocation.MyCommand.Path
$CredPfad   = Join-Path $SkriptPfad "credentials.json"
$ConfigPfad = Join-Path $SkriptPfad "config.json"

# Config + Credentials
$Config  = Get-Content $ConfigPfad -Raw -Encoding UTF8 | ConvertFrom-Json
$credRaw = Get-Content $CredPfad   -Raw -Encoding UTF8 | ConvertFrom-Json

function ConvertTo-SecureStringSafe {
    param([string]$Wert)
    if ($Wert -and $Wert.Length -gt 10) { return ($Wert | ConvertTo-SecureString) }
    return $null
}

$ReolinkPassSecure = ConvertTo-SecureStringSafe $credRaw.reolink_pass
$InstarPassSecure  = ConvertTo-SecureStringSafe $credRaw.instar_pass

# Passwort entschlüsseln
$reolinkPass = ""
if ($ReolinkPassSecure) {
    $bstr        = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ReolinkPassSecure)
    $reolinkPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

$Kameras = $Config.geraete | Where-Object { $_.aktiv -eq $true -and $_.typ -in @("kamera_reolink","kamera_instar") }

Clear-Host
Write-Host ""
Write-Host "  Kamera-Snapshot-Test – $((Get-Date).ToString('dd.MM.yyyy HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "  $($Kameras.Count) Kameras werden geprueft" -ForegroundColor Gray
Write-Host ""

$Ergebnisse = @()

foreach ($K in $Kameras) {
    $httpPort = if ($K.http_port) { [int]$K.http_port } else { if ($K.typ -eq "kamera_reolink") { 80 } else { 8080 } }
    $kamUser  = if ($K.cam_user)  { $K.cam_user }  else { "admin" }

    Write-Host "  [$($K.typ.Replace('kamera_','').ToUpper())]  $($K.name)  $($K.ip)  Port:$httpPort" -ForegroundColor White

    # ── Ping ──────────────────────────────────────────────────────────────────
    $pingOK = $false
    try {
        Test-Connection -ComputerName $K.ip -Count 1 -TimeoutSeconds 2 -ErrorAction Stop | Out-Null
        $pingOK = $true
        Write-Host "    Ping        : OK" -ForegroundColor Green
    }
    catch { Write-Host "    Ping        : FEHLER" -ForegroundColor Red }

    # ── RTSP Port ─────────────────────────────────────────────────────────────
    $rtspOK = $false
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $rtspOK = $c.BeginConnect($K.ip, 554, $null, $null).AsyncWaitHandle.WaitOne(2000) -and $c.Connected
        $c.Close(); $c.Dispose()
    } catch {}
    Write-Host "    RTSP/554    : $(if ($rtspOK) { 'OFFEN' } else { 'GESCHLOSSEN' })" -ForegroundColor $(if ($rtspOK) { "Green" } else { "Yellow" })

    # ── HTTP Port ─────────────────────────────────────────────────────────────
    $httpOK = $false
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $httpOK = $c.BeginConnect($K.ip, $httpPort, $null, $null).AsyncWaitHandle.WaitOne(2000) -and $c.Connected
        $c.Close(); $c.Dispose()
    } catch {}
    Write-Host "    HTTP/$httpPort  : $(if ($httpOK) { 'OFFEN' } else { 'GESCHLOSSEN' })" -ForegroundColor $(if ($httpOK) { "Green" } else { "Yellow" })

    # ── Snapshot URLs testen (Reolink) ────────────────────────────────────────
    $snapshotB64  = $null
    $snapUrlOK    = ""
    $snapErgebnis = @()

    # TLS-Downgrade für alte Firmware (Reolink mit TLS 1.0/1.1)
    $tlsAlt = [Net.ServicePointManager]::SecurityProtocol
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12 } catch {}

    if ($K.typ -eq "kamera_reolink" -and $reolinkPass -and $httpOK) {
        $rs   = Get-Random -Maximum 9999
        $uEnc = [Uri]::EscapeDataString($kamUser)
        $pEnc = [Uri]::EscapeDataString($reolinkPass)

        $testUrls = @(
            "https://$($K.ip)/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=$rs&user=$uEnc&password=$pEnc",
            "https://$($K.ip):$httpPort/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=$rs&user=$uEnc&password=$pEnc",
            "http://$($K.ip):$httpPort/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=$rs&user=$uEnc&password=$pEnc",
            "https://$($K.ip)/api.cgi?cmd=Snap&channel=0&rs=$rs&user=$uEnc&password=$pEnc",
            "https://$($K.ip):$httpPort/api.cgi?cmd=Snap&channel=0&rs=$rs&user=$uEnc&password=$pEnc",
            "http://$($K.ip):$httpPort/api.cgi?cmd=Snap&channel=0&rs=$rs&user=$uEnc&password=$pEnc"
        )

        foreach ($url in $testUrls) {
            $urlAnzeige = $url -replace "password=[^&]+", "password=***"
            try {
                $r = Invoke-WebRequest -Uri $url -SkipCertificateCheck -TimeoutSec 8 -ErrorAction Stop
                if ($r.StatusCode -eq 200 -and $r.Headers['Content-Type'] -match 'image') {
                    $snapshotB64 = [Convert]::ToBase64String($r.Content)
                    $snapUrlOK   = $urlAnzeige
                    $snapErgebnis += "    " + $urlAnzeige.Substring(0, [Math]::Min(65,$urlAnzeige.Length)).PadRight(65) + " -> OK ($([Math]::Round($r.Content.Length/1024))KB)"
                    break
                }
                else {
                    $snapErgebnis += "    " + $urlAnzeige.Substring(0, [Math]::Min(65,$urlAnzeige.Length)).PadRight(65) + " -> HTTP $($r.StatusCode) / kein Image"
                }
            }
            catch {
                $kurzFehler = $_.Exception.Message -replace '\(.*?\)','.' -replace '\s{2,}',' '
                if ($kurzFehler.Length -gt 60) { $kurzFehler = $kurzFehler.Substring(0,60) + "..." }
                $snapErgebnis += "    " + $urlAnzeige.Substring(0, [Math]::Min(65,$urlAnzeige.Length)).PadRight(65) + " -> FEHLER: $kurzFehler"
            }
        }

        # curl.exe-Fallback wenn alle Invoke-WebRequest fehlschlugen
        if (-not $snapshotB64) {
            $curlExe = Get-Command "curl.exe" -ErrorAction SilentlyContinue
            if ($curlExe) {
                $tmpFile = [System.IO.Path]::GetTempFileName()
                foreach ($url in $testUrls) {
                    if ($snapshotB64) { break }
                    $urlAnzeige = $url -replace "password=[^&]+", "password=***"
                    try {
                        & curl.exe --silent --insecure --max-time 10 --output $tmpFile $url 2>$null
                        if (Test-Path $tmpFile) {
                            $bytes = [System.IO.File]::ReadAllBytes($tmpFile)
                            if ($bytes.Length -gt 1000 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) {
                                $snapshotB64 = [Convert]::ToBase64String($bytes)
                                $snapUrlOK   = "[curl] $urlAnzeige"
                                $snapErgebnis += "    [curl] " + $urlAnzeige.Substring(0,[Math]::Min(55,$urlAnzeige.Length)).PadRight(55) + " -> OK ($([Math]::Round($bytes.Length/1024))KB)"
                            } elseif ($bytes.Length -gt 20) {
                                # Antwort als Text zeigen (Diagnose), aber weitermachen
                                $antwortText = [System.Text.Encoding]::UTF8.GetString($bytes, 0, [Math]::Min(200, $bytes.Length)) -replace '\r?\n',' '
                                $snapErgebnis += "    [curl] " + $urlAnzeige.Substring(0,[Math]::Min(55,$urlAnzeige.Length)).PadRight(55) + " -> kein JPEG: $antwortText"
                            } else {
                                $snapErgebnis += "    [curl] " + $urlAnzeige.Substring(0,[Math]::Min(55,$urlAnzeige.Length)).PadRight(55) + " -> leer (Port geschlossen?)"
                            }
                        }
                    }
                    catch {}
                }
                try { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue } catch {}
            }
        }

        foreach ($zeile in $snapErgebnis) {
            $farbe = if ($zeile -match '-> OK') { "Green" } elseif ($zeile -match '-> FEHLER|kein JPEG') { "Red" } else { "Yellow" }
            Write-Host $zeile -ForegroundColor $farbe
        }
    }
    elseif ($K.typ -eq "kamera_instar" -and $httpOK) {
        $instarPass = ""
        if ($InstarPassSecure) {
            $b = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($InstarPassSecure)
            $instarPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($b)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
        }
        $b64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${kamUser}:${instarPass}"))
        $authHdr = @{ Authorization = "Basic $b64Auth" }

        $instarUrls = @(
            "http://$($K.ip):$httpPort/snap.cgi",
            "http://$($K.ip):$httpPort/tmpfs/snap.jpg",
            "http://$($K.ip):$httpPort/cgi-bin/hi3510/snap.cgi?&-getstream"
        )
        # Basic Auth Versuch
        foreach ($url in $instarUrls) {
            if ($snapshotB64) { break }
            try {
                $r = Invoke-WebRequest -Uri $url -Headers $authHdr -TimeoutSec 8 -ErrorAction Stop
                if ($r.StatusCode -eq 200 -and $r.Headers['Content-Type'] -match 'image') {
                    $snapshotB64 = [Convert]::ToBase64String($r.Content)
                    $snapUrlOK   = $url
                    $snapErgebnis += "    [Basic] $url -> OK ($([Math]::Round($r.Content.Length/1024))KB)"
                } else {
                    $snapErgebnis += "    [Basic] $url -> HTTP $($r.StatusCode)"
                }
            }
            catch {
                $statusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
                $snapErgebnis += "    [Basic] $url -> FEHLER HTTP $statusCode"
            }
        }
        # Digest Auth Fallback via curl.exe (viele INSTAR-Modelle nutzen Digest)
        if (-not $snapshotB64) {
            $curlExe = Get-Command "curl.exe" -ErrorAction SilentlyContinue
            if ($curlExe) {
                $tmpFile = [System.IO.Path]::GetTempFileName()
                $instarDigestUrls = @(
                    "http://$($K.ip):$httpPort/snap.cgi",
                    "http://$($K.ip):$httpPort/tmpfs/snap.jpg",
                    "http://$($K.ip):$httpPort/cgi-bin/hi3510/snap.cgi?&-getstream"
                )
                foreach ($url in $instarDigestUrls) {
                    if ($snapshotB64) { break }
                    try {
                        & curl.exe --silent --digest --user "${kamUser}:${instarPass}" --max-time 10 --output $tmpFile $url 2>$null
                        if (Test-Path $tmpFile) {
                            $bytes = [System.IO.File]::ReadAllBytes($tmpFile)
                            if ($bytes.Length -gt 500 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) {
                                $snapshotB64 = [Convert]::ToBase64String($bytes)
                                $snapUrlOK   = "[curl-digest] $url"
                                $snapErgebnis += "    [Digest] $url -> OK ($([Math]::Round($bytes.Length/1024))KB)"
                            } elseif ($bytes.Length -gt 20) {
                                $antwortText = [System.Text.Encoding]::UTF8.GetString($bytes,0,[Math]::Min(200,$bytes.Length)) -replace '\r?\n',' '
                                $snapErgebnis += "    [Digest] $url -> kein JPEG: $antwortText"
                            } else {
                                $snapErgebnis += "    [Digest] $url -> leer"
                            }
                        }
                    }
                    catch {}
                }
                try { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
        $instarPass = $null
        foreach ($zeile in $snapErgebnis) {
            $farbe = if ($zeile -match '-> OK') { "Green" } elseif ($zeile -match '-> FEHLER') { "Red" } else { "Yellow" }
            Write-Host $zeile -ForegroundColor $farbe
        }
    }
    elseif (-not $httpOK) {
        Write-Host "    Snapshot    : HTTP-Port nicht erreichbar – kein Test" -ForegroundColor Yellow
    }
    else {
        Write-Host "    Snapshot    : Passwort fehlt in credentials.json" -ForegroundColor Red
    }

    [Net.ServicePointManager]::SecurityProtocol = $tlsAlt

    if ($snapshotB64) {
        Write-Host "    SNAPSHOT    : OK  ($([Math]::Round($snapshotB64.Length * 0.75 / 1024)) KB)" -ForegroundColor Green
    }
    else {
        Write-Host "    SNAPSHOT    : KEIN Snapshot" -ForegroundColor Red
    }
    Write-Host ""

    $Ergebnisse += [PSCustomObject]@{
        Name        = $K.name
        IP          = $K.ip
        Typ         = $K.typ
        HttpPort    = $httpPort
        PingOK      = $pingOK
        RtspOK      = $rtspOK
        HttpOK      = $httpOK
        SnapUrlOK   = $snapUrlOK
        SnapshotB64 = $snapshotB64
    }
}

# ── Zusammenfassung ───────────────────────────────────────────────────────────
$mitSnap  = ($Ergebnisse | Where-Object { $_.SnapshotB64 }).Count
$ohneSnap = $Ergebnisse.Count - $mitSnap

Write-Host "  Ergebnis: $($Ergebnisse.Count) Kameras | " -NoNewline -ForegroundColor Cyan
Write-Host "$mitSnap Snapshots OK" -NoNewline -ForegroundColor Green
Write-Host " | " -NoNewline -ForegroundColor Cyan
Write-Host "$ohneSnap ohne Snapshot" -ForegroundColor $(if ($ohneSnap -gt 0) { "Red" } else { "Green" })
Write-Host ""

# ── HTML-Vorschau ─────────────────────────────────────────────────────────────
$cards = ""
foreach ($e in $Ergebnisse) {
    $statusFarbe = if ($e.SnapshotB64) { "#3fb950" } else { "#f85149" }
    $imgBlock = if ($e.SnapshotB64) {
        "<img src='data:image/jpeg;base64,$($e.SnapshotB64)' style='width:100%;border-radius:4px;margin-top:8px;display:block;'>"
    } else {
        "<div style='width:100%;height:140px;background:#21262d;border-radius:4px;margin-top:8px;display:flex;align-items:center;justify-content:center;color:#8b949e;font-size:0.85em;'>Kein Snapshot</div>"
    }
    $urlInfo = if ($e.SnapUrlOK) { "<div style='font-size:0.75em;color:#3fb950;margin-top:4px;word-break:break-all;'>$($e.SnapUrlOK)</div>" } else { "" }
    $ports   = "RTSP/554: $(if ($e.RtspOK) {'OFFEN'} else {'ZU'}) &nbsp;|&nbsp; HTTP/$($e.HttpPort): $(if ($e.HttpOK) {'OFFEN'} else {'ZU'})"

    $cards += @"
  <div style='background:#161b22;border:1px solid $statusFarbe;border-radius:8px;padding:12px;'>
    <div style='font-weight:600;font-size:1em;color:#e6edf3;'>$($e.Name)</div>
    <div style='font-family:monospace;font-size:0.82em;color:#8b949e;margin:2px 0;'>$($e.IP)</div>
    <div style='font-size:0.8em;color:#8b949e;margin:2px 0;'>$ports</div>
    $urlInfo
    $imgBlock
  </div>
"@
}

$html = @"
<!DOCTYPE html>
<html>
<head>
  <meta charset='UTF-8'>
  <title>Kamera Test $((Get-Date).ToString('dd.MM.yyyy HH:mm'))</title>
  <style>
    body { background:#0d1117; color:#e6edf3; font-family:Segoe UI,Arial,sans-serif; margin:0; padding:20px; }
    h1   { color:#58a6ff; margin-bottom:4px; }
    .grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(300px,1fr)); gap:16px; max-width:1400px; }
  </style>
</head>
<body>
  <h1>Kamera-Snapshot-Test</h1>
  <p style='color:#8b949e;font-size:0.9em;'>$((Get-Date).ToString('dd.MM.yyyy HH:mm:ss')) &nbsp;|&nbsp; $($Ergebnisse.Count) Kameras &nbsp;|&nbsp; $mitSnap/$($Ergebnisse.Count) Snapshots OK</p>
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

Write-Host "  HTML-Vorschau: $vorschauPfad" -ForegroundColor Cyan
Write-Host ""
