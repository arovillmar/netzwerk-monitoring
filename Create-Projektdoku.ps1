#Requires -Version 5.1
Set-StrictMode -Off

$AusgabePfad = "C:\Armin\claude_Projekte\Netzwerk-Monitoring\reports\Projektdoku_Netzwerk_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"
$null = New-Item -ItemType Directory -Path (Split-Path $AusgabePfad) -Force

$datum = Get-Date -Format "dd.MM.yyyy HH:mm"
$lines = [System.Collections.Generic.List[string]]::new()

function L  { param([string]$t = "") $lines.Add($t) }
function H1 { param([string]$t) L ""; L ("=" * 70); L "  $t"; L ("=" * 70) }
function H2 { param([string]$t) L ""; L "  $t"; L ("  " + ("-" * ($t.Length))) }
function Sep { L ("  " + ("-" * 66)) }

# ================================================================
# TITELSEITE
# ================================================================
L ("=" * 70)
L "  HEIMNETZ MONITOR"
L "  Projektdokumentation und Reolink Kamera-Tests"
L ("=" * 70)
L "  Erstellt am:  $datum"
L "  Erstellt auf: $env:COMPUTERNAME"
L ""

# ================================================================
H1 "1. PROJEKTÜBERSICHT"
# ================================================================
L ""
L "  Das Heimnetz Monitor Projekt ist ein PowerShell-basiertes"
L "  Monitoring-System fuer das lokale Netzwerk (192.168.80.0/24)."
L "  Es prueft regelmaessig alle wichtigen Netzwerkgeraete und sendet"
L "  Berichte sowie Alarme per E-Mail."
L ""
L "  Hauptfunktionen:"
L "    - Automatische Pruefung aller Geraete alle 15 Minuten"
L "      via Windows Task Scheduler"
L "    - Tagesbericht taeglich um 08:00 Uhr per E-Mail"
L "    - Sofortbericht (Send-Sofortbericht.ps1) jederzeit manuell"
L "    - Kamera-Test (Test-Kameras.ps1) mit Snapshot-Vorschau"
L "    - E-Mail via IONOS SMTP (exchange.ionos.eu:587 / STARTTLS)"

# ================================================================
H2 "1.1  Ueberwachte Netzwerkgeraete"
# ================================================================
L ""
L "  ID   Name                  IP               Typ               Status"
Sep
L "   1   Fritz!Box             192.168.80.1     Router            Aktiv"
L "   2   Raspberry Pi 5        192.168.80.20    Raspberry Pi      Aktiv"
L "   3   Synology DS1525+      192.168.80.206   NAS Synology      Aktiv"
L "   4   Synology DS723+       192.168.80.207   NAS Synology      Aktiv"
L "   5   SASCHA_SERVER         192.168.80.87    Windows Host      Aktiv"
L "   6   Mailstore VM          192.168.80.120   Mailstore         Aktiv"
L "   7   SMA Home Manager 2    192.168.80.49    PV Steuerung      Aktiv"
L "   8   AC ELWA-E Heizstab    192.168.80.122   Heizstab          Aktiv"
L "   9   Powerline Adapter 1   192.168.80.75    Powerline         Aktiv"
L "  10   Powerline Adapter 2   192.168.80.77    Powerline         Aktiv"
L "  11   Powerline Adapter 3   192.168.80.138   Powerline         Aktiv"
L "  12   Reolink Garten-2      192.168.80.76    Kamera Reolink    Aktiv"
L "  13   Reolink Garten-1      192.168.80.127   Kamera Reolink    Aktiv"
L "  14   Reolink Eingang       192.168.80.130   Kamera Reolink    Aktiv"
L "  15   Reolink Keller        192.168.80.171   Kamera Reolink    Aktiv"
L "  16   Reolink Garten-4      192.168.80.172   Kamera Reolink    Aktiv"
L "  17   INSTAR Kamera 1       192.168.80.67    Kamera INSTAR     Aktiv"
L "  18   INSTAR Kamera 2       nicht bekannt    Kamera INSTAR     Inaktiv"
Sep
L ""
L "  Gepruefte Dienste je Typ:"
L "    Router:          Ping, HTTP/80, TR-064 API, VPN"
L "    Raspberry Pi:    Ping, SSH/22, Pi-hole API, ntopng"
L "    Synology NAS:    Ping, SSH/822, RAID-Status, Speicher, Docker"
L "    Windows Host:    Ping, RDP/3389"
L "    Mailstore:       Ping, Port/8474, Mailstore API"
L "    PV Steuerung:    Ping, HTTP/80"
L "    Heizstab:        Ping, HTTP JSON API"
L "    Powerline:       Ping, HTTP/80"
L "    Kamera Reolink:  Ping, HTTP/80, Reolink API, Snapshot"
L "    Kamera INSTAR:   Ping, HTTP/8080"

# ================================================================
H2 "1.2  PowerShell-Skripte"
# ================================================================
L ""
L "  Skript                    Zweck"
Sep
L "  Start-NetworkMonitor.ps1  Haupt-Monitor, alle 15 Min. via Task Scheduler"
L "  Send-Sofortbericht.ps1    Alle Checks + E-Mail sofort senden (manuell)"
L "  Test-Kameras.ps1          Nur Kameras pruefen, HTML-Vorschau mit Snapshots"
L "  Test-Email.ps1            SMTP TCP / Auth / Zustellung einzeln testen"
L "  Test-ReoinkLogin.ps1      Reolink API-Login direkt mit 3 Varianten testen"
L "  Setup-Credentials.ps1     Alle 6 Passwoerter DPAPI-verschluesselt speichern"
L "  Setup-Task.ps1            Windows Task Scheduler Eintrag (als Admin)"
L ""
L "  Module (modules\):"
Sep
L "  Check-Camera.ps1          Reolink+INSTAR: HTTP, API-Login, DevInfo, Snapshot"
L "  Check-SynologyAPI.ps1     Synology NAS via SSH: Volumes, RAID, Speicher"
L "  Check-SSH.ps1             Allgemeiner SSH-Check, 10s Timeout (Start-Job)"
L "  Check-SMA.ps1             SMA Home Manager: Ping + HTTP/80"
L "  Check-EmailDelivery.ps1   SMTP: TCP, Auth, Zustellung separat pruefen"

# ================================================================
H1 "2. TECHNISCHE DETAILS"
# ================================================================
L ""
L "  PowerShell Version   : 7.5.5 (basiert auf .NET 6)"
L "  Betriebssystem       : Windows 11 Pro 10.0.26200"
L "  Computer             : $env:COMPUTERNAME"
L "  Projekt-Pfad         : C:\Armin\claude_Projekte\Netzwerk-Monitoring"
L "  SMTP-Server          : exchange.ionos.eu:587 (STARTTLS)"
L "  E-Mail Von/An        : rosbach@fe-partners.com"
L "  Netzwerk             : 192.168.80.0/24"
L "  Reolink Modelle      : RLC-820A (4x), RLC-843A (1x), RLC-810A (1x)"
L "  Reolink API          : HTTPS Port 443, nginx, selbst-sign. Zertifikat"
L "  Reolink Endpunkte    : https://IP/cgi-bin/api.cgi  oder  https://IP/api.cgi"
L "  Synology SSH         : Port 822, Benutzer: Armin, Public-Key-Auth"
L "  Credential-Speicher  : Windows DPAPI (ConvertFrom/To-SecureString)"
L "  Gespeicherte Passwort: smtp, nas1, nas2, mailstore, reolink, instar"

# ================================================================
H1 "3. REOLINK KAMERA-TESTS — CHRONOLOGISCHE DOKUMENTATION"
# ================================================================
L ""
L "  Ziel: Reolink HTTP-API aus PowerShell ansprechen fuer Login,"
L "  Geraete-Info (DevInfo) und Snapshot-Abruf."
L ""

H2 "3.1  Session 1 — API-Grundlagen und SSL-Problematik"
L ""

$tests1 = @(
    @{
        Nr = "01"; Titel = "RTSP-Port 554 pruefen"
        Methode  = "TCP-Verbindungstest auf Port 554"
        Ergebnis = "Port 554 geschlossen -> alle Kameras zeigen WARNUNG"
        Massnahme= "Status-Logik geaendert: OK wenn HTTP/80 offen ist"
    },
    @{
        Nr = "02"; Titel = "HTTP-Port 80 als primaeren Check verwenden"
        Methode  = "TCP-Verbindungstest auf Port 80"
        Ergebnis = "4 Reolink-Kameras OK. Reolink Eingang (130) WARNUNG (Port geschlossen)"
        Massnahme= "HTTP-Check als Basis-Verfuegbarkeitstest etabliert"
    },
    @{
        Nr = "03"; Titel = "Reolink HTTP-API erstmals aufgerufen"
        Methode  = "Invoke-RestMethod auf http://IP/api.cgi"
        Ergebnis = "API-Status: n/a — Code-Block wird nicht erreicht"
        Massnahme= "Passwort-Variable wurde nicht korrekt uebergeben — Parameter korrigiert"
    },
    @{
        Nr = "04"; Titel = "Passwort in URL-Query-String"
        Methode  = "Login via ?user=admin&password=PASS in der URL"
        Ergebnis = "FEHLER: Invalid URI — Hostname konnte nicht geparst werden"
        Massnahme= "Sonderzeichen im Passwort brechen URL-Parsing -> Passwort aus URL entfernt"
    },
    @{
        Nr = "05"; Titel = "SSL-Verbindung zu HTTPS"
        Methode  = "Invoke-RestMethod auf https://IP/cgi-bin/api.cgi"
        Ergebnis = "FEHLER: SSL connection could not be established"
        Massnahme= "Kamera leitet HTTP->HTTPS um (nginx 302). Selbst-signiertes Zertifikat"
    },
    @{
        Nr = "06"; Titel = "SSL-Bypass Versuch 1: ICertificatePolicy Add-Type"
        Methode  = "Add-Type fuer System.Net.ICertificatePolicy"
        Ergebnis = "FEHLER: Interface in .NET 5+ nicht mehr vorhanden"
        Massnahme= "PS 7 basiert auf .NET 6 — dieser SSL-Bypass nicht moeglich"
    },
    @{
        Nr = "07"; Titel = "SSL-Bypass Versuch 2: ServicePointManager Callback"
        Methode  = "ServicePointManager.ServerCertificateValidationCallback = {`$true}"
        Ergebnis = "Ohne Wirkung — PS 7 ignoriert diese Einstellung"
        Massnahme= "PS-Version 7.5.5 bestaetigt. Loesung: -SkipCertificateCheck Parameter"
    },
    @{
        Nr = "08"; Titel = "HTTP 302 Redirect-Test"
        Methode  = "Invoke-WebRequest mit -MaximumRedirection 0"
        Ergebnis = "HTTP 302 bestaetigt: Kamera leitet auf HTTPS um"
        Massnahme= "Loesung: `$ssl = @{SkipCertificateCheck=`$true} als Splat verwenden"
    },
    @{
        Nr = "09"; Titel = "-SkipCertificateCheck via Splat"
        Methode  = "`$ssl=@{SkipCertificateCheck=`$true}; Invoke-RestMethod @ssl"
        Ergebnis = "SSL-Fehler behoben! Login-Antwort empfangen. Aber: DevInfo Code 1"
        Massnahme= "Login gibt Code 0 zurueck (Erfolg). DevInfo schlaegt noch fehl"
    },
    @{
        Nr = "10"; Titel = "Login-Body als manueller JSON-String"
        Methode  = "Body als String mit eingebettetem Passwort"
        Ergebnis = "DevInfo Code 1 | Login Code 0 OK | Snapshot liefert text/html"
        Massnahme= "Login funktioniert! Snapshot-Problem und DevInfo-Problem verbleiben"
    },
    @{
        Nr = "11"; Titel = "ConvertTo-Json fuer Login-Body"
        Methode  = "Passwort via ConvertTo-Json -Depth 6 -Compress serialisiert"
        Ergebnis = "DevInfo Code 1 | Snap HTTP 200 CT:text/html — unveraendert"
        Massnahme= "Sonderzeichen korrekt escaped. Snapshot-Problem bleibt offen"
    }
)

foreach ($t in $tests1) {
    L "  Test #$($t.Nr): $($t.Titel)"
    L "    Methode  : $($t.Methode)"
    L "    Ergebnis : $($t.Ergebnis)"
    L "    Massnahme: $($t.Massnahme)"
    L ""
}

H2 "3.2  Session 2 — Encoding, Bitdefender, Lockout"
L ""

$tests2 = @(
    @{
        Nr = "12"; Titel = "Token URL-Encoding + alternative Snap-URLs"
        Methode  = "[Uri]::EscapeDataString(token) + snap.cgi als Fallback"
        Ergebnis = "Login Code 1 bei /cgi-bin/api.cgi — kein Token erhalten"
        Massnahme= "Login schlaegt auf beiden Endpunkten fehl — Ursache noch unklar"
    },
    @{
        Nr = "13"; Titel = "Bitdefender HTTPS-Scanning als Ursache identifiziert"
        Methode  = "Bitdefender interceptiert POST-Body als transparenter MITM-Proxy"
        Ergebnis = "cmd: Unknown / please login first (rspCode -6) — leerer Body"
        Massnahme= "Bitdefender deinstalliert — Problem bleibt weiterhin bestehen"
    },
    @{
        Nr = "14"; Titel = "Direkttest mit Test-ReoinkLogin.ps1 (Body als String)"
        Methode  = "3 JSON-Varianten x 2 Endpunkte, Body als String gesendet"
        Ergebnis = "cmd: Unknown / please login first — Kamera erkennt Befehl nicht"
        Massnahme= "String-Encoding fehlerhaft: Body wird nicht korrekt uebertragen"
    },
    @{
        Nr = "15"; Titel = "Body als explizite UTF-8 Bytes senden"
        Methode  = "[System.Text.Encoding]::UTF8.GetBytes(body) statt String"
        Ergebnis = "Code 1 (please login first) — Kamera erkennt Login-Befehl jetzt!"
        Massnahme= "Encoding-Bug behoben! Code 1 = Konto gesperrt (API-Lockout ~15 Versuche)"
    },
    @{
        Nr = "16"; Titel = "Browser-Login zur Passwort-Verifikation"
        Methode  = "https://192.168.80.76 in Chrome, admin + Passwort eingegeben"
        Ergebnis = "Login erfolgreich — Kamera-Dashboard und Live-Bild sichtbar"
        Massnahme= "Passwort korrekt! Code 1 in API = nur Lockout, nicht falsches Passwort"
    },
    @{
        Nr = "17"; Titel = "AKTUELLER STATUS: Warte auf Lockout-Ablauf"
        Methode  = "Kamera neustarten (Strom 10s trennen) oder 30 Min. warten"
        Ergebnis = "Noch nicht durchgefuehrt — steht als naechster Schritt an"
        Massnahme= "Nach Neustart: Test-ReoinkLogin.ps1 -> LOGIN ERFOLGREICH erwartet"
    }
)

foreach ($t in $tests2) {
    L "  Test #$($t.Nr): $($t.Titel)"
    L "    Methode  : $($t.Methode)"
    L "    Ergebnis : $($t.Ergebnis)"
    L "    Massnahme: $($t.Massnahme)"
    L ""
}

# ================================================================
H1 "4. GEFUNDENE FEHLER UND LOESUNGEN"
# ================================================================
L ""
$fehler = @(
    @("Skript haengt nach Fritz!Box",
      "SSH ConnectTimeout deckt nur TCP ab, nicht den Handshake",
      "SSH-Aufruf in Start-Job mit 10 Sekunden Wait-Job Timeout"),
    @("Synology DSM API Fehler 403",
      "2-Faktor-Authentifizierung auf DSM admin-Konto aktiviert",
      "Auf SSH-basiertes Monitoring umgestellt — kein DSM API"),
    @("SMA Home Manager FEHLER",
      "Speedwire = UDP Port 9522, TCP-Test schlaegt immer fehl",
      "Check auf Ping + HTTP/80 umgebaut"),
    @("Kameras zeigen WARNUNG",
      "RTSP Port 554 geschlossen, HTTP/80 aber offen",
      "Status: OK wenn HTTP/80 offen ist"),
    @("Synology zeigt 30 Volumes",
      "ContainerManager-Unterpfade als Volumes erkannt",
      "Regex-Filter: nur Einhaengepunkte /volume[0-9]+"),
    @("Reolink SSL-Fehler",
      "HTTP->HTTPS redirect, selbst-signiertes Zertifikat",
      "-SkipCertificateCheck als Splat: `$ssl=@{SkipCertificateCheck=`$true}"),
    @("Reolink Body-Encoding (cmd: Unknown)",
      "String-Body wird vom PS7-HTTP-Client nicht korrekt uebertragen",
      "Body als UTF-8 Bytes: [System.Text.Encoding]::UTF8.GetBytes(body)"),
    @("Reolink API-Lockout (Code 1)",
      "~15 Fehlversuche im Debugging -> Konto temporaer gesperrt",
      "Kamera neustarten (Strom trennen) oder 30 Minuten warten")
)
foreach ($f in $fehler) {
    L "  Problem  : $($f[0])"
    L "  Ursache  : $($f[1])"
    L "  Loesung  : $($f[2])"
    Sep
}

# ================================================================
H1 "5. OFFENE PUNKTE / NAECHSTE SCHRITTE"
# ================================================================
L ""
L "  [HOCH]    1. Reolink API-Lockout aufheben"
L "               Kamera neustarten -> Test-ReoinkLogin.ps1"
L ""
L "  [HOCH]    2. Reolink Snapshots in E-Mail einbetten"
L "               Nach Lockout-Behebung: Test-Kameras.ps1 -> HTML-Vorschau"
L ""
L "  [MITTEL]  3. Reolink Eingang (192.168.80.130)"
L "               HTTP-Port geschlossen — Kamera offline oder anderen Port pruefen"
L ""
L "  [MITTEL]  4. INSTAR Snapshot-Funktion"
L "               INSTAR HTTP-API fuer Snapshot implementieren"
L ""
L "  [MITTEL]  5. Setup-Task.ps1 ausfuehren"
L "               Als Administrator starten fuer Task Scheduler Eintrag"
L ""
L "  [NIEDRIG] 6. Pi-hole API v6 Token einrichten"
L ""
L "  [NIEDRIG] 7. INSTAR Kamera 2 IP-Adresse in config.json eintragen"
L ""
L "  [NIEDRIG] 8. ELWA Heizstab Ping pruefen (Geraet oder IP verifizieren)"
L ""

L ("=" * 70)
L "  Ende der Dokumentation — erstellt am $datum"
L ("=" * 70)

# Datei schreiben
$lines | Set-Content -Path $AusgabePfad -Encoding UTF8
Write-Host "  Dokument erstellt: $AusgabePfad" -ForegroundColor Green
Start-Process notepad.exe $AusgabePfad
