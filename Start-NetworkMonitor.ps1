#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$TaskScheduler,
    [switch]$Tagesbericht,
    [switch]$NurFehler,
    [string]$Geraet = ""
)

Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$StartZeit    = Get-Date
$SkriptPfad   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPfad   = Join-Path $SkriptPfad "config.json"
$ModulPfad    = Join-Path $SkriptPfad "modules"
$VersionInfo  = "1.0"

# ── Logging ─────────────────────────────────────────────────────────────────
function Write-Log {
    param([string]$Nachricht, [string]$Ebene = "INFO")
    $zeitstempel = (Get-Date).ToString("HH:mm:ss")
    $logDatei    = Join-Path $Config.einstellungen.log_pfad "Monitor_$((Get-Date).ToString('yyyyMMdd')).log"
    $zeile       = "[$zeitstempel] [$Ebene] $Nachricht"
    try { $zeile | Add-Content $logDatei -Encoding UTF8 } catch {}
}

function Get-LatenzInfo {
    param([string]$Latenz)
    if ($Latenz -eq "n/a" -or $Latenz -eq "") { return @{ Text = "n/a     "; Farbe = "Gray" } }
    $ms = 0
    [int]::TryParse(($Latenz -replace 'ms','').Trim(), [ref]$ms) | Out-Null
    if ($ms -le 2)  { return @{ Text = "$($Latenz.PadLeft(5))  LAN      "; Farbe = "Green"  } }
    if ($ms -le 10) { return @{ Text = "$($Latenz.PadLeft(5))  gut      "; Farbe = "Green"  } }
    if ($ms -le 30) { return @{ Text = "$($Latenz.PadLeft(5))  traege   "; Farbe = "Yellow" } }
                      return @{ Text = "$($Latenz.PadLeft(5))  LANGSAM! "; Farbe = "Red"    }
}

function Write-Konsole {
    param([string]$Zeitstempel, [string]$Icon, [string]$Name, [string]$IP, [string]$Status, [string]$Info, [string]$Latenz = "n/a")
    $farbe = switch ($Status) {
        "OK"      { "Green"  }
        "WARNUNG" { "Yellow" }
        "FEHLER"  { "Red"    }
        default   { "Gray"   }
    }
    $symbol = switch ($Status) {
        "OK"      { "OK     " }
        "WARNUNG" { "WARNUNG" }
        "FEHLER"  { "FEHLER " }
        default   { $Status   }
    }
    if ($NurFehler -and $Status -eq "OK") { return }
    $latInfo = Get-LatenzInfo -Latenz $Latenz
    Write-Host "[$Zeitstempel] $Icon  $($Name.PadRight(26)) $($IP.PadRight(16))" -NoNewline
    Write-Host $latInfo.Text -ForegroundColor $latInfo.Farbe -NoNewline
    Write-Host "  $symbol  " -ForegroundColor $farbe -NoNewline
    Write-Host $Info
}

# ── Config laden ─────────────────────────────────────────────────────────────
if (-not (Test-Path $ConfigPfad)) {
    Write-Host "FEHLER: config.json nicht gefunden unter $ConfigPfad" -ForegroundColor Red
    exit 1
}
$Config = Get-Content $ConfigPfad -Raw -Encoding UTF8 | ConvertFrom-Json

# Ordner sicherstellen
@($Config.einstellungen.report_pfad, $Config.einstellungen.log_pfad) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

# ── Credentials laden ────────────────────────────────────────────────────────
$CredPfad = Join-Path $SkriptPfad "credentials.json"
$Creds    = $null

if (Test-Path $CredPfad) {
    try {
        $CredRaw = Get-Content $CredPfad -Raw -Encoding UTF8 | ConvertFrom-Json
        function ConvertTo-SecureStringSafe {
            param([string]$Wert)
            if ($Wert -and $Wert.Length -gt 10) {
                return ($Wert | ConvertTo-SecureString)
            }
            return $null
        }
        $Creds = [PSCustomObject]@{
            SmtpPass         = (ConvertTo-SecureStringSafe $CredRaw.smtp_pass)
            PiholePass       = (ConvertTo-SecureStringSafe $CredRaw.pihole_pass)
            NAS1Pass         = (ConvertTo-SecureStringSafe $CredRaw.nas1_pass)
            NAS2Pass         = (ConvertTo-SecureStringSafe $CredRaw.nas2_pass)
            MailstorePass    = (ConvertTo-SecureStringSafe $CredRaw.mailstore_pass)
            MailstoreWinPass = (ConvertTo-SecureStringSafe $CredRaw.mailstore_win_pass)
            ReolinkPass      = (ConvertTo-SecureStringSafe $CredRaw.reolink_pass)
            InstarPass       = (ConvertTo-SecureStringSafe $CredRaw.instar_pass)
        }
    }
    catch {
        Write-Host "WARNUNG: Credentials konnten nicht geladen werden: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Bitte Setup-Credentials.ps1 ausfuehren!" -ForegroundColor Yellow
    }
}
else {
    Write-Host ""
    Write-Host "  credentials.json nicht gefunden!" -ForegroundColor Yellow
    Write-Host "  Bitte zuerst ausfuehren: .\Setup-Credentials.ps1" -ForegroundColor Yellow
    Write-Host ""
}

# ── Module laden ─────────────────────────────────────────────────────────────
Get-ChildItem -Path $ModulPfad -Filter "*.ps1" | ForEach-Object { . $_.FullName }

# ── ffprobe prüfen ───────────────────────────────────────────────────────────
$FfprobePfad       = $Config.einstellungen.ffprobe_pfad
$FfprobeVerfuegbar = Test-Path $FfprobePfad

if (-not $FfprobeVerfuegbar) {
    Write-Log "ffprobe nicht gefunden – Kamera-Stream-Check deaktiviert." "INFO"
}

# ── Geräte filtern ───────────────────────────────────────────────────────────
$GeraeteListe = $Config.geraete | Where-Object { $_.aktiv -eq $true }
if ($Geraet -ne "") {
    $GeraeteListe = $GeraeteListe | Where-Object { $_.name -like "*$Geraet*" }
}

# ── Haupt-Check-Schleife ─────────────────────────────────────────────────────
$AlleErgebnisse = @()
Write-Host ""
Write-Host "  Heimnetz Monitor v$VersionInfo – Start: $($StartZeit.ToString('dd.MM.yyyy HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "  $($GeraeteListe.Count) Geraete werden geprueft..." -ForegroundColor Gray
Write-Host ""

foreach ($G in $GeraeteListe) {
    $zeitNow = (Get-Date).ToString("HH:mm:ss")
    $icon    = switch ($G.typ) {
        "router"            { "Netz" }
        "raspberry"         { "Pi  " }
        "nas_synology"      { "NAS " }
        "windows_host"      { "Win " }
        "mailstore"         { "Mail" }
        "sma_homemanager"   { "PV  " }
        "elwa_heizstab"     { "Heiz" }
        "powerline_fritzbox"{ "Plne" }
        "kamera_reolink"    { "Cam " }
        "kamera_instar"     { "Cam " }
        default             { "Sys " }
    }

    $checkStatus = "OK"
    $checkInfo   = ""
    $details     = $null

    try {
        $pingResult = $null
        if ($G.checks -contains "ping" -and $G.ip -ne "SPAETER_NACHTRAGEN" -and $G.ip -ne "SPÄTER_NACHTRAGEN") {
            $pingResult = Check-Ping -IP $G.ip -TimeoutMs $Config.einstellungen.ping_timeout_ms
            if ($pingResult.Status -eq "FEHLER") {
                $checkStatus = "FEHLER"
                $checkInfo   = "Kein Ping"
            }
        }

        $latenz = if ($pingResult) { "$($pingResult.Latenz_ms)ms" } else { "n/a" }

        switch ($G.typ) {

            "router" {
                $portCheck = Check-Port -IP $G.ip -Port 80 -TimeoutMs $Config.einstellungen.port_timeout_ms
                $checkInfo = "HTTP/:80 $($portCheck.Status)"
            }

            "raspberry" {
                if ($G.checks -contains "ssh" -and $checkStatus -ne "FEHLER") {
                    $sshResult = Check-SSH -IP $G.ip -Port $G.ssh_port -User $G.ssh_user
                    $details   = $sshResult
                    if ($sshResult.Status -eq "FEHLER") { $checkStatus = "WARNUNG" }
                }
                $checkInfo = "SSH/:$($G.ssh_port) $(if ($sshResult -and $sshResult.Status -eq 'OK') { 'OK' } else { 'FEHLER' })"
                if ($G.checks -contains "pihole_api") {
                    $piholePass   = if ($Creds) { $Creds.PiholePass } else { $null }
                    $piholeResult = Check-PiholeAPI -IP $G.ip -PassSecure $piholePass
                    if ($piholeResult.Status -eq "FEHLER" -and $checkStatus -eq "OK") { $checkStatus = "WARNUNG" }
                    $checkInfo += " | Pi-hole/:80 $($piholeResult.Status) ($($piholeResult.Blockierrate))"
                    $details   = $piholeResult
                }
                if ($G.checks -contains "ntopng_api") {
                    $ntopResult = Check-NtopngAPI -IP $G.ip
                    if ($ntopResult.Status -eq "FEHLER" -and $checkStatus -eq "OK") { $checkStatus = "WARNUNG" }
                    $checkInfo += " | ntopng/:3000 $($ntopResult.Status)"
                }
            }

            "nas_synology" {
                if ($checkStatus -ne "FEHLER") {
                    $nasResult = Check-SynologyAPI -IP $G.ip -Port $G.ssh_port -User $G.ssh_user
                    $details   = $nasResult
                    if ($nasResult.Status -eq "FEHLER")  { $checkStatus = "FEHLER"  }
                    if ($nasResult.Status -eq "WARNUNG") { $checkStatus = "WARNUNG" }
                    $checkInfo = "SSH/:$($G.ssh_port) | $($nasResult.Info)"
                }
                if ($G.docker -eq $true -and $checkStatus -ne "FEHLER") {
                    $dockerResult = Check-Docker -IP $G.ip -SSHPort $G.ssh_port -SSHUser $G.ssh_user
                    if ($dockerResult.Status -eq "FEHLER" -and $checkStatus -eq "OK") { $checkStatus = "WARNUNG" }
                    $checkInfo += " | Docker: $($dockerResult.Container_Name) ($($dockerResult.Container_Status))"
                    if ($details) { Add-Member -InputObject $details -MemberType NoteProperty -Name "Docker" -Value $dockerResult -Force }
                }
            }

            "windows_host" {
                $rdpResult = Check-Port -IP $G.ip -Port 3389 -TimeoutMs $Config.einstellungen.port_timeout_ms
                $checkInfo = "RDP/:3389 $($rdpResult.Status)"
                if ($rdpResult.Status -eq "GESCHLOSSEN" -and $checkStatus -eq "OK") { $checkStatus = "WARNUNG" }
            }

            "mailstore" {
                $msPass    = if ($Creds) { $Creds.MailstorePass    } else { $null }
                $msWinPass = if ($Creds) { $Creds.MailstoreWinPass } else { $null }
                $msResult  = Check-MailstoreAPI -IP $G.ip -User "admin" -PassSecure $msPass -WinPassSecure $msWinPass
                $details  = $msResult
                if ($msResult.Status -ne "OK") { $checkStatus = $msResult.Status }
                $checkInfo = $msResult.Info
            }

            "sma_homemanager" {
                $smaResult = Check-SMA -IP $G.ip -SpeedwirePort $G.speedwire_port
                $details   = $smaResult
                if ($smaResult.Status -eq "FEHLER") { $checkStatus = "FEHLER" }
                $checkInfo = "Ping OK | HTTP/:80 $(if ($smaResult.Status -eq 'OK') { 'OK' } else { 'FEHLER' }) | Speedwire/UDP:$($G.speedwire_port)"
            }

            "elwa_heizstab" {
                $elwaResult = Check-ELWA -IP $G.ip -TempMax $G.temp_max
                $details    = $elwaResult
                if ($elwaResult.Status -eq "WARNUNG") { $checkStatus = "WARNUNG" }
                if ($elwaResult.Status -eq "FEHLER")  { $checkStatus = "FEHLER"  }
                $checkInfo  = "HTTP/:80 | Temp: $($elwaResult.Temperatur) | Leistung: $($elwaResult.Leistung_W)"
            }

            "powerline_fritzbox" {
                $plResult  = Check-Powerline -IP $G.ip
                $details   = $plResult
                if ($plResult.Status -ne "OK") { $checkStatus = $plResult.Status }
                $checkInfo = "HTTP/:80 $(if ($plResult.HTTP_Erreichbar) { 'OK' } else { 'FEHLER' })"
            }

            { $_ -in @("kamera_reolink","kamera_instar") } {
                $kamTyp  = if ($G.typ -eq "kamera_reolink") { "reolink" } else { "instar" }
                $kamPass = if ($G.typ -eq "kamera_reolink" -and $Creds) { $Creds.ReolinkPass } `
                           elseif ($Creds) { $Creds.InstarPass } else { $null }
                $httpP   = if ($G.http_port) { [int]$G.http_port } else { if ($kamTyp -eq "reolink") { 80 } else { 8080 } }
                $kamResult = Check-Camera -IP $G.ip -Typ $kamTyp -HttpPort $httpP `
                    -RtspUrl $G.rtsp_url -FfprobePfad $FfprobePfad -Name $G.name `
                    -ReolinkPassSecure $kamPass
                $details   = $kamResult
                if ($kamResult.Status -ne "OK") { $checkStatus = $kamResult.Status }
                $checkInfo = "RTSP/:554 $($kamResult.RTSP_Port) | HTTP/:$httpP $($kamResult.HTTP_Port)"
                if ($FfprobeVerfuegbar -and $kamResult.Stream_Aktiv -eq $true) {
                    $checkInfo += " | $($kamResult.Aufloesung)"
                }
                if ($kamResult.Lockout_Aktiv) { $checkInfo += " | LOCKOUT!" }
            }
        }
    }
    catch {
        $checkStatus = "FEHLER"
        $checkInfo   = "Ausnahme: $($_.Exception.Message)"
        Write-Log "Ausnahme bei $($G.name): $($_.Exception.Message)" "ERROR"
    }

    Write-Konsole -Zeitstempel $zeitNow -Icon $icon -Name $G.name -IP $G.ip -Status $checkStatus -Info $checkInfo -Latenz $latenz
    Write-Log "$($G.name) ($($G.ip)) – $checkStatus – $checkInfo"

    $AlleErgebnisse += [PSCustomObject]@{
        Geraet      = $G.name
        IP          = $G.ip
        Typ         = $G.typ
        CheckStatus = $checkStatus
        Latenz      = $latenz
        Info        = $checkInfo
        Details     = $details
        Zeitstempel = $zeitNow
    }
}

# ── External Logins (einmalig pro Lauf) ──────────────────────────────────────
Write-Host ""
Write-Host "  Pruefe externe Zugriffe..." -ForegroundColor Gray
$LoginResult = $null
try {
    $LoginResult = Check-ExternalLogins
    Write-Log "Externe Logins: $($LoginResult.Status) – $($LoginResult.Info)"
}
catch {
    Write-Log "Externe Logins konnten nicht geprueft werden: $($_.Exception.Message)" "ERROR"
}

# ── Statistik ────────────────────────────────────────────────────────────────
$AnzahlOK      = ($AlleErgebnisse | Where-Object { $_.CheckStatus -eq "OK"      }).Count
$AnzahlWarn    = ($AlleErgebnisse | Where-Object { $_.CheckStatus -eq "WARNUNG" }).Count
$AnzahlFehler  = ($AlleErgebnisse | Where-Object { $_.CheckStatus -eq "FEHLER"  }).Count
$LaufzeitSek   = [Math]::Round(((Get-Date) - $StartZeit).TotalSeconds, 1)

Write-Host ""
Write-Host "  Ergebnis: OK: $AnzahlOK  |  Warnungen: $AnzahlWarn  |  Fehler: $AnzahlFehler  |  Laufzeit: $($LaufzeitSek)s" -ForegroundColor Cyan
Write-Host ""

# ── HTML-Report erstellen ─────────────────────────────────────────────────────
$reportDateiname = "Monitor_$((Get-Date).ToString('yyyyMMdd_HHmm')).html"
$reportPfad      = Join-Path $Config.einstellungen.report_pfad $reportDateiname
$reportAktuell   = Join-Path $Config.einstellungen.report_pfad "Monitor_Aktuell.html"

$htmlContent = New-HtmlReport -Ergebnisse $AlleErgebnisse -LoginResult $LoginResult `
    -AnzahlOK $AnzahlOK -AnzahlWarn $AnzahlWarn -AnzahlFehler $AnzahlFehler `
    -LaufzeitSek $LaufzeitSek -Config $Config

$htmlContent | Set-Content $reportPfad    -Encoding UTF8
$htmlContent | Set-Content $reportAktuell -Encoding UTF8
Write-Log "Report gespeichert: $reportDateiname"

# ── Browser öffnen (nur manueller Start) ─────────────────────────────────────
if (-not $TaskScheduler) {
    $browser = @("msedge","chrome","firefox") | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    if ($browser) { Start-Process $browser $reportAktuell } else { Start-Process $reportAktuell }
}

# ── Alerts senden ─────────────────────────────────────────────────────────────
if ($Creds -and $Config.einstellungen.alarm_bei_fehler -and $AnzahlFehler -gt 0) {
    Send-Alert -Typ "Alarm" -Ergebnisse $AlleErgebnisse -LoginResult $LoginResult -SmtpConfig $Config.einstellungen -SmtpPass $Creds.SmtpPass
}
elseif ($Creds -and $Config.einstellungen.alarm_bei_warnung -and $AnzahlWarn -gt 0) {
    Send-Alert -Typ "Warnung" -Ergebnisse $AlleErgebnisse -LoginResult $LoginResult -SmtpConfig $Config.einstellungen -SmtpPass $Creds.SmtpPass
}
elseif ($Creds -and $AnzahlFehler -eq 0 -and $AnzahlWarn -eq 0) {
    Send-Alert -Typ "Entwarnung" -Ergebnisse $AlleErgebnisse -LoginResult $LoginResult -SmtpConfig $Config.einstellungen -SmtpPass $Creds.SmtpPass
}

if ($Creds -and $Tagesbericht) {
    Send-Alert -Typ "Tagesbericht" -Ergebnisse $AlleErgebnisse -LoginResult $LoginResult -SmtpConfig $Config.einstellungen -SmtpPass $Creds.SmtpPass
}

# ── GitHub Push ───────────────────────────────────────────────────────────────
$commitBeschreibung = if ($Tagesbericht) {
    "daily: Automatischer Backup-Commit $((Get-Date).ToString('yyyy-MM-dd'))"
} else {
    "monitoring: Check abgeschlossen – OK:$AnzahlOK WARN:$AnzahlWarn ERR:$AnzahlFehler"
}
Push-GitCommit -Beschreibung $commitBeschreibung

Write-Log "Lauf abgeschlossen. Laufzeit: $($LaufzeitSek)s"

# ════════════════════════════════════════════════════════════════════════════
