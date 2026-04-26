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

function Write-Konsole {
    param([string]$Zeitstempel, [string]$Icon, [string]$Name, [string]$IP, [string]$Status, [string]$Info)
    $farbe = switch ($Status) {
        "OK"      { "Green"  }
        "WARNUNG" { "Yellow" }
        "FEHLER"  { "Red"    }
        default   { "Gray"   }
    }
    $symbol = switch ($Status) {
        "OK"      { "OK" }
        "WARNUNG" { "WARNUNG" }
        "FEHLER"  { "FEHLER" }
        default   { $Status }
    }
    if ($NurFehler -and $Status -eq "OK") { return }
    $zeile = "[$Zeitstempel] $Icon  $($Name.PadRight(28)) ($IP)"
    Write-Host $zeile -NoNewline
    Write-Host "  $symbol" -ForegroundColor $farbe -NoNewline
    Write-Host "  $Info"
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
            SmtpPass      = (ConvertTo-SecureStringSafe $CredRaw.smtp_pass)
            NAS1Pass      = (ConvertTo-SecureStringSafe $CredRaw.nas1_pass)
            NAS2Pass      = (ConvertTo-SecureStringSafe $CredRaw.nas2_pass)
            MailstorePass = (ConvertTo-SecureStringSafe $CredRaw.mailstore_pass)
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

foreach ($Geraet in $GeraeteListe) {
    $zeitNow = (Get-Date).ToString("HH:mm:ss")
    $icon    = switch ($Geraet.typ) {
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
        # PING (fast alle Geräte)
        $pingResult = $null
        if ($Geraet.checks -contains "ping" -and $Geraet.ip -ne "SPÄTER_NACHTRAGEN") {
            $pingResult = Check-Ping -IP $Geraet.ip -TimeoutMs $Config.einstellungen.ping_timeout_ms
            if ($pingResult.Status -eq "FEHLER") {
                $checkStatus = "FEHLER"
                $checkInfo   = "Kein Ping"
            }
        }

        $latenz = if ($pingResult) { "$($pingResult.Latenz_ms)ms" } else { "n/a" }

        # Typ-spezifische Checks
        switch ($Geraet.typ) {

            "router" {
                $portCheck = Check-Port -IP $Geraet.ip -Port 80 -TimeoutMs $Config.einstellungen.port_timeout_ms
                $checkInfo = "HTTP: $($portCheck.Status)"
                if ($checkStatus -eq "OK") { $checkInfo = "Ping: OK | $checkInfo" }
            }

            "raspberry" {
                if ($Geraet.checks -contains "ssh" -and $checkStatus -ne "FEHLER") {
                    $sshResult = Check-SSH -IP $Geraet.ip -Port $Geraet.ssh_port -User $Geraet.ssh_user
                    $details   = $sshResult
                    if ($sshResult.Status -eq "FEHLER") { $checkStatus = "WARNUNG" }
                }
                if ($Geraet.checks -contains "pihole_api") {
                    $piholeResult = Check-PiholeAPI -IP $Geraet.ip
                    if ($piholeResult.Status -eq "FEHLER" -and $checkStatus -eq "OK") { $checkStatus = "WARNUNG" }
                    $checkInfo = "Pi-hole: $($piholeResult.Status) | ntopng: "
                    $details   = $piholeResult
                }
                if ($Geraet.checks -contains "ntopng_api") {
                    $ntopResult = Check-NtopngAPI -IP $Geraet.ip
                    if ($ntopResult.Status -eq "FEHLER" -and $checkStatus -eq "OK") { $checkStatus = "WARNUNG" }
                    $checkInfo += $ntopResult.Status
                }
                if ($checkStatus -eq "OK") { $checkInfo = "Pi-hole + ntopng aktiv" }
            }

            "nas_synology" {
                $nasPass = if ($Geraet.ip -eq "192.168.80.206") { $Creds.NAS1Pass } else { $Creds.NAS2Pass }
                if ($nasPass -and $checkStatus -ne "FEHLER") {
                    $nasResult = Check-SynologyAPI -IP $Geraet.ip -Port $Geraet.dsm_port -User $Geraet.ssh_user -PassSecure $nasPass
                    $details   = $nasResult
                    if ($nasResult.Status -eq "FEHLER")  { $checkStatus = "FEHLER"  }
                    if ($nasResult.Status -eq "WARNUNG") { $checkStatus = "WARNUNG" }
                    $checkInfo = $nasResult.Info
                } else {
                    $checkInfo = if ($checkStatus -ne "FEHLER") { "Ping OK (keine Credentials)" } else { "Nicht erreichbar" }
                }
                if ($Geraet.docker -eq $true -and $Creds -and $checkStatus -ne "FEHLER") {
                    $dockerResult = Check-Docker -IP $Geraet.ip -SSHPort $Geraet.ssh_port -SSHUser $Geraet.ssh_user
                    if ($dockerResult.Status -eq "FEHLER" -and $checkStatus -eq "OK") { $checkStatus = "WARNUNG" }
                }
            }

            "windows_host" {
                $rdpResult = Check-Port -IP $Geraet.ip -Port 3389 -TimeoutMs $Config.einstellungen.port_timeout_ms
                $checkInfo = "RDP Port 3389: $($rdpResult.Status)"
                if ($rdpResult.Status -eq "GESCHLOSSEN" -and $checkStatus -eq "OK") { $checkStatus = "WARNUNG" }
            }

            "mailstore" {
                if ($Creds -and $checkStatus -ne "FEHLER") {
                    $msResult  = Check-MailstoreAPI -IP $Geraet.ip -Port $Geraet.api_port -PassSecure $Creds.MailstorePass
                    $details   = $msResult
                    if ($msResult.Status -ne "OK") { $checkStatus = $msResult.Status }
                    $checkInfo = $msResult.Info
                } else {
                    $portResult = Check-Port -IP $Geraet.ip -Port $Geraet.api_port -TimeoutMs $Config.einstellungen.port_timeout_ms
                    $checkInfo  = "Port $($Geraet.api_port): $($portResult.Status)"
                }
            }

            "sma_homemanager" {
                $smaResult = Check-SMA -IP $Geraet.ip -SpeedwirePort $Geraet.speedwire_port
                $details   = $smaResult
                if ($smaResult.Status -eq "FEHLER") { $checkStatus = "FEHLER" }
                $checkInfo = if ($smaResult.Speedwire_Aktiv) { "Speedwire Port 9522: aktiv" } else { $smaResult.Info }
            }

            "elwa_heizstab" {
                $elwaResult = Check-ELWA -IP $Geraet.ip -TempMax $Geraet.temp_max
                $details    = $elwaResult
                if ($elwaResult.Status -eq "WARNUNG") { $checkStatus = "WARNUNG" }
                if ($elwaResult.Status -eq "FEHLER")  { $checkStatus = "FEHLER"  }
                $checkInfo  = "$($elwaResult.Temperatur) | $($elwaResult.Leistung_W)"
            }

            "powerline_fritzbox" {
                $plResult  = Check-Powerline -IP $Geraet.ip
                $details   = $plResult
                if ($plResult.Status -ne "OK") { $checkStatus = $plResult.Status }
                $checkInfo = "Ping: $(if ($plResult.Ping_OK) { 'OK' } else { 'FEHLER' }) | HTTP: $(if ($plResult.HTTP_Erreichbar) { 'OK' } else { 'FEHLER' })"
            }

            { $_ -in @("kamera_reolink","kamera_instar") } {
                $kamTyp    = if ($Geraet.typ -eq "kamera_reolink") { "reolink" } else { "instar" }
                $kamResult = Check-Camera -IP $Geraet.ip -Typ $kamTyp -FfprobePfad $FfprobePfad -Name $Geraet.name
                $details   = $kamResult
                if ($kamResult.Status -ne "OK") { $checkStatus = $kamResult.Status }
                $checkInfo = "RTSP: $($kamResult.RTSP_Port) | HTTP: $($kamResult.HTTP_Port)"
                if ($FfprobeVerfuegbar -and $kamResult.Stream_Aktiv -eq $true) {
                    $checkInfo += " | $($kamResult.Aufloesung)"
                }
            }
        }
    }
    catch {
        $checkStatus = "FEHLER"
        $checkInfo   = "Ausnahme: $($_.Exception.Message)"
        Write-Log "Ausnahme bei $($Geraet.name): $($_.Exception.Message)" "ERROR"
    }

    Write-Konsole -Zeitstempel $zeitNow -Icon $icon -Name $Geraet.name -IP $Geraet.ip -Status $checkStatus -Info $checkInfo
    Write-Log "$($Geraet.name) ($($Geraet.ip)) – $checkStatus – $checkInfo"

    $AlleErgebnisse += [PSCustomObject]@{
        Geraet      = $Geraet.name
        IP          = $Geraet.ip
        Typ         = $Geraet.typ
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
    Start-Process $reportAktuell
}

# ── Alerts senden ─────────────────────────────────────────────────────────────
if ($Creds -and $Config.einstellungen.alarm_bei_fehler -and $AnzahlFehler -gt 0) {
    Send-Alert -Typ "Alarm" -Ergebnisse $AlleErgebnisse -SmtpConfig $Config.einstellungen -SmtpPass $Creds.SmtpPass
}
elseif ($Creds -and $Config.einstellungen.alarm_bei_warnung -and $AnzahlWarn -gt 0) {
    Send-Alert -Typ "Warnung" -Ergebnisse $AlleErgebnisse -SmtpConfig $Config.einstellungen -SmtpPass $Creds.SmtpPass
}
elseif ($Creds -and $AnzahlFehler -eq 0 -and $AnzahlWarn -eq 0) {
    Send-Alert -Typ "Entwarnung" -Ergebnisse $AlleErgebnisse -SmtpConfig $Config.einstellungen -SmtpPass $Creds.SmtpPass
}

if ($Creds -and $Tagesbericht) {
    Send-Alert -Typ "Tagesbericht" -Ergebnisse $AlleErgebnisse -SmtpConfig $Config.einstellungen -SmtpPass $Creds.SmtpPass
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
