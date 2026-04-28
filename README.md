# Heimnetz Monitor v2.0 – Einrichtungsanleitung

Automatisches Monitoring-System für **19 Netzwerkgeräte** im Heimnetz (192.168.80.0/24).
Prüft alle 15 Minuten, sendet E-Mail-Alarm bei Problemen, erstellt HTML-Reports.

---

## Voraussetzungen

| Anforderung | Version / Info |
|---|---|
| Windows PC | Windows 10/11 (ArminRosbach @ 192.168.80.145) |
| PowerShell | 5.1 oder höher (vorinstalliert) |
| OpenSSH Client | `ssh.exe` verfügbar (Windows 10/11 Feature) |
| ffprobe | Optional – für Kamera-Stream-Check |

**OpenSSH prüfen:**
```powershell
ssh.exe -V
```
Falls nicht vorhanden: Windows-Einstellungen → Apps → Optionale Features → OpenSSH Client

---

## Einmalige Einrichtung (in dieser Reihenfolge!)

### Schritt 1 – SSH-Keys einrichten

SSH-Key generieren (falls noch nicht vorhanden):
```powershell
ssh-keygen -t ed25519 -C "heimnetz-monitor"
```

Key auf alle Linux-Hosts übertragen:
```powershell
# Raspberry Pi 5 (Port 22)
ssh-copy-id -p 22 pi@192.168.80.20

# Synology DS1525+ (SSH in DSM aktivieren: Systemsteuerung → Terminal & SNMP)
ssh-copy-id -p 822 Armin@192.168.80.206

# Synology DS723+
ssh-copy-id -p 822 Armin@192.168.80.207
```

Verbindung testen – jeder Befehl muss `OK` ausgeben (ohne Passwort-Abfrage):
```powershell
ssh -o BatchMode=yes pi@192.168.80.20 "echo OK"
ssh -o BatchMode=yes -p 822 Armin@192.168.80.206 "echo OK"
ssh -o BatchMode=yes -p 822 Armin@192.168.80.207 "echo OK"
```

---

### Schritt 2 – PowerShell Remoting für Mailstore aktivieren

Auf der Mailstore-VM (192.168.80.120) als Administrator ausführen:
```powershell
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.80.145" -Force
Restart-Service WinRM
```

Vom Monitoring-PC testen:
```powershell
Test-WSMan -ComputerName 192.168.80.120
Invoke-Command -ComputerName 192.168.80.120 -ScriptBlock { Get-Service | Where-Object DisplayName -like "*MailStore*" }
```

> **Ohne PowerShell Remoting:** Das Script prüft nur Ping + RDP-Port.
> Stufe 2/3/4 (Dienst-Status, Jobs, Archiv) sind dann nicht verfügbar.

---

### Schritt 3 – Mailstore PowerShell Wrapper installieren (optional)

Ermöglicht Abruf von Job-Ergebnissen und Archivstatistiken via API.

1. Auf der Mailstore-VM (192.168.80.120) in PowerShell als Admin:
```powershell
# Wrapper-Pfad prüfen (einer davon sollte existieren):
Test-Path "C:\Program Files (x86)\deepinvent\MailStore Server\administration\MS.PS.Lib.psd1"
```

2. Falls nicht vorhanden: Mailstore Scripting Tutorial herunterladen von:
   `Mailstore Server → Hilfe → Skriptbasierte Administration`
   und nach `C:\MailStore Server Scripting Tutorial\` entpacken.

3. Testen:
```powershell
Import-Module "C:\Program Files (x86)\deepinvent\MailStore Server\administration\MS.PS.Lib.psd1"
Connect-MSApiSession -ServerName "localhost" -UserName "admin" -Password "IhrPasswort"
Invoke-MSApiCall "GetServerInfo"
```

> **Bekannte Probleme (werden im Report als "bekannt" markiert, kein Alarm):**
> - `andrearosbach27@gmail.com` → Gmail OAuth2-Token abgelaufen
> - `Andrea_IMAP_IONOS` → unverschlüsselte Verbindung
> - `Armin_FEP_Exchange` → unverschlüsselte Verbindung

---

### Schritt 4 – ffprobe installieren (optional)

Für den Kamera-Stream-Check (prüft ob RTSP-Stream wirklich aktiv ist):

1. ffmpeg herunterladen: https://ffmpeg.org/download.html → Windows Builds (gpl-shared)
2. ZIP entpacken nach:
   ```
   C:\Armin\claude_Projekte\Netzwerk-Monitoring\tools\ffmpeg\
   ```
3. Struktur prüfen:
   ```
   tools\ffmpeg\bin\ffprobe.exe   ← muss genau hier liegen
   tools\ffmpeg\bin\ffmpeg.exe
   ```
4. Testen:
   ```powershell
   .\tools\ffmpeg\bin\ffprobe.exe -version
   ```

Ohne ffprobe: Nur Ping + TCP-Port-Checks für Kameras, kein Stream-Check.

---

### Schritt 5 – E-Mail-Adressen eintragen

`config.json` öffnen und anpassen:
```json
"smtp_von": "rosbach@fe-partners.com",
"smtp_an":  "rosbach@fe-partners.com"
```

---

### Schritt 6 – Zugangsdaten einrichten

```powershell
.\Setup-Credentials.ps1
```

Abgefragt werden (verschlüsselt mit Windows DPAPI):

| # | Passwort | Wozu |
|---|----------|------|
| 1 | IONOS SMTP | E-Mail-Versand (exchange.ionos.eu:587) |
| 2 | Pi-hole | API v6 Session-Login (POST /api/auth) |
| 3 | Synology DS1525+ | SSH Benutzer Armin, Port 822 |
| 4 | Synology DS723+ | SSH Benutzer Armin, Port 822 |
| 5 | Mailstore Admin | PowerShell Remoting + CLI Wrapper |
| 6 | Reolink Kameras | Benutzer admin, alle 5 Reolink-Kameras |
| 7 | INSTAR Kameras | Benutzer admin, alle INSTAR-Kameras |

> **Sicherheit:** `credentials.json` ist in `.gitignore` – kommt **niemals** auf GitHub.
> DPAPI-Verschlüsselung ist an diesen PC gebunden. Bei PC-Wechsel: Setup-Credentials.ps1 erneut ausführen.

---

### Schritt 7 – Task Scheduler einrichten

Als **Administrator** ausführen:
```powershell
.\Setup-Task.ps1
```

Legt zwei geplante Aufgaben an:
- **Heimnetz-Monitor-Check**: Alle 15 Minuten (+ einmalig 3 Min nach Neustart)
- **Heimnetz-Monitor-Tagesbericht**: Täglich 08:00 Uhr mit vollständigem E-Mail-Report

---

### Schritt 8 – INSTAR Kamera 2 IP nachtragen

Sobald die IP bekannt ist:
1. `config.json` öffnen
2. Gerät 18 `"INSTAR Kamera 2"` suchen
3. `"SPÄTER_NACHTRAGEN"` durch echte IP ersetzen
4. `"aktiv": false` → `"aktiv": true` setzen
5. `rtsp_url` entsprechend anpassen

---

### Schritt 9 – Ersten manuellen Test starten

```powershell
.\Start-NetworkMonitor.ps1
```

Öffnet automatisch den HTML-Report im Browser.
Alle 19 Geräte werden geprüft – Laufzeit ca. 30–90 Sekunden.

---

## Tägliche Nutzung

**Vollautomatisch!** Der Task Scheduler übernimmt alles:

| Aufgabe | Zeitplan | Aktion |
|---|---|---|
| Netzwerk-Check | Alle 15 Minuten | Prüft alle 19 Geräte, Alarm bei Problemen |
| Tagesbericht | Täglich 08:00 | Vollständiger Report per E-Mail |
| Neustart-Check | 3 Min nach Systemstart | Prüft nach PC-Neustart |

Reports werden gespeichert unter:
```
reports\Monitor_YYYYMMDD_HHmm.html   (historisch)
reports\Monitor_Aktuell.html          (immer aktuell, wird überschrieben)
```

---

## Manueller Start – Parameter

```powershell
# Standard (öffnet Browser, alle 19 Geräte)
.\Start-NetworkMonitor.ps1

# Nur Fehler und Warnungen anzeigen
.\Start-NetworkMonitor.ps1 -NurFehler

# Nur ein bestimmtes Gerät prüfen
.\Start-NetworkMonitor.ps1 -Geraet "Synology"
.\Start-NetworkMonitor.ps1 -Geraet "Reolink"
.\Start-NetworkMonitor.ps1 -Geraet "ELWA"
.\Start-NetworkMonitor.ps1 -Geraet "Mailstore"

# Tagesbericht sofort senden
.\Start-NetworkMonitor.ps1 -Tagesbericht

# Wie Task Scheduler (kein Browser, kein interaktives Fenster)
.\Start-NetworkMonitor.ps1 -TaskScheduler
```

---

## Geräte-Übersicht

| # | Name | IP | Checks | Besonderheit |
|---|------|----|--------|--------------|
| 01 | Fritz!Box | 192.168.80.1 | Ping, HTTP:80 | Gateway, DHCP |
| 02 | Raspberry Pi 5 | 192.168.80.20 | Ping, SSH:22, Pi-hole, ntopng | Pi-hole v6 Auth! |
| 03 | Synology DS1525+ | 192.168.80.206 | Ping, SSH:822, DSM, Docker | Docker: Männerballet Port 3000 |
| 04 | Synology DS723+ | 192.168.80.207 | Ping, SSH:822, DSM | Kein Docker |
| 05 | SASCHA_SERVER | 192.168.80.87 | Ping, RDP:3389 | Windows-Host |
| 06 | Mailstore VM | 192.168.80.120 | Ping, RDP:3389, WinRM | PowerShell Remoting (kein REST!) |
| 07 | SMA Home Manager 2 | 192.168.80.49 | Ping, UDP:9522 | PV-Anlage, Alarm bei Ausfall |
| 08 | AC ELWA-E Heizstab | 192.168.80.122 | Ping, HTTP:/data.jsn | temp1 ÷ 10 = °C, blockactive=OK |
| 09 | Powerline Adapter 1 | 192.168.80.75 | Ping, HTTP:80 | |
| 10 | Powerline Adapter 2 | 192.168.80.77 | Ping, HTTP:80 | |
| 11 | Powerline Adapter 3 | 192.168.80.138 | Ping, HTTP:80 | |
| 12 | Reolink Garten-2 | 192.168.80.76 | Ping, RTSP:554, HTTP:80 | RLC-820A |
| 13 | Reolink Garten-1 | 192.168.80.127 | Ping, RTSP:554, HTTP:80 | RLC-820A |
| 14 | Reolink Eingang | 192.168.80.130 | Ping, RTSP:554, **HTTP:9000** | RLC-843A, neuere Firmware! |
| 15 | Reolink Keller-Werkstatt | 192.168.80.171 | Ping, RTSP:554, HTTP:80 | RLC-810A |
| 16 | Reolink Garten-4 | 192.168.80.172 | Ping, RTSP:554, HTTP:80 | RLC-820A |
| 17 | INSTAR Kamera 1 | 192.168.80.67 | Ping, RTSP:554, HTTP:8080 | |
| 18 | INSTAR Kamera 2 | SPÄTER_NACHTRAGEN | Ping, RTSP:554, HTTP:8080 | Deaktiviert bis IP bekannt |

---

## Troubleshooting

### SSH-Verbindung schlägt fehl
```powershell
# Verbose-Diagnose
ssh -v -p 822 Armin@192.168.80.206
```
Häufige Ursachen:
- SSH im DSM noch nicht aktiviert → Systemsteuerung → Terminal & SNMP → SSH aktivieren
- Falscher Port (Synology: **822**, Raspberry: **22**)
- SSH-Key nicht kopiert → `ssh-copy-id` erneut ausführen

### Pi-hole gibt HTTP 401 zurück
Pi-hole v6 erfordert Session-Authentifizierung. Sicherstellen dass:
- `pihole_pass` in `credentials.json` gesetzt ist → `.\Setup-Credentials.ps1` erneut ausführen
- Das Passwort mit dem Pi-hole Admin-Passwort übereinstimmt
- Pi-hole API läuft: `Invoke-RestMethod http://192.168.80.20/api/auth -Method Post -Body '{"password":"test"}' -ContentType "application/json"`

### ELWA-E API gibt 404 zurück
Korrekter Endpunkt ist `/data.jsn` (nicht `/mypv_act.jsn`):
```powershell
Invoke-RestMethod http://192.168.80.122/data.jsn
```
Gibt JSON mit `temp1`, `power`, `blockactive` etc. zurück.

### Reolink Kamera gesperrt (Lockout)
Nach 3 fehlgeschlagenen Login-Versuchen sperrt Reolink für 1 Stunde.
Das Script schützt davor via `logs\camera_lockout.json`.
- Lockout-Status zurücksetzen: `Remove-Item logs\camera_lockout.json`
- Kamera direkt im Browser testen: `http://192.168.80.76` (oder Port 9000 bei Eingang)
- Passwort prüfen: `.\Setup-Credentials.ps1`

### Reolink Eingang zeigt HTTP-Fehler
Dieses Modell (RLC-843A) verwendet Port **9000** statt 80!
```powershell
Test-NetConnection 192.168.80.130 -Port 9000
```

### Mailstore – PowerShell Remoting schlägt fehl
```powershell
# Auf Mailstore-VM testen (als Admin):
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

# Vom Monitoring-PC testen:
Test-WSMan -ComputerName 192.168.80.120
```
Das Script läuft auch ohne Remoting weiter (nur Ping + RDP-Check).

### Mailstore Gmail-Fehler (bekanntes Problem)
- `andrearosbach27@gmail.com`: Gmail OAuth2-Token abgelaufen
- Lösung: Mailstore Server → Archivierungsprofile → Gmail-Konto → OAuth2 neu autorisieren
- Dieser Fehler wird im Report als **"bekannt"** markiert und löst keinen Alarm aus.

### credentials.json nach PC-Wechsel ungültig
DPAPI-Verschlüsselung ist benutzerbezogen – nach PC-Wechsel oder Profil-Reset:
```powershell
.\Setup-Credentials.ps1   # alle 7 Passwörter neu eingeben
```

### Task Scheduler startet nicht
```powershell
# ExecutionPolicy prüfen
Get-ExecutionPolicy
# Log prüfen
Get-Content logs\Monitor_$(Get-Date -Format yyyyMMdd).log | Select-Object -Last 50
# Task-Status prüfen
Get-ScheduledTask "Heimnetz-Monitor-Check" | Select-Object TaskName, State
```

---

## Dateistruktur

```
Netzwerk-Monitoring\
├── Start-NetworkMonitor.ps1      Haupt-Orchestrator
├── config.json                   19 Geräte + globale Einstellungen
├── credentials.json              DPAPI-verschlüsselt (in .gitignore!)
├── Setup-Credentials.ps1         7 Passwörter einrichten
├── Setup-Task.ps1                Task Scheduler einrichten (als Admin)
├── README.md                     Diese Anleitung
├── modules\
│   ├── Check-Ping.ps1            ICMP Ping
│   ├── Check-Port.ps1            TCP Port-Check mit Latenz
│   ├── Check-SSH.ps1             SSH Key-Auth (uptime, disk, RAM)
│   ├── Check-PiholeAPI.ps1       Pi-hole v6 Session-Auth (POST /api/auth)
│   ├── Check-NtopngAPI.ps1       ntopng REST API Port 3000
│   ├── Check-SynologyAPI.ps1     SSH: Volumes, RAID, Uptime
│   ├── Check-Docker.ps1          Docker Compose Status via SSH
│   ├── Check-MailstoreAPI.ps1    4-stufig: Ping → RDP → WinRM → CLI
│   ├── Check-ELWA.ps1            GET /data.jsn (temp÷10=°C)
│   ├── Check-SMA.ps1             Ping + HTTP (Speedwire UDP)
│   ├── Check-Camera.ps1          RTSP:554 + HTTP:konfigurierbar + Lockout
│   ├── Check-Powerline.ps1       Ping + HTTP:80
│   ├── Check-ExternalLogins.ps1  Auth-Logs SSH + RDP-Check
│   ├── New-HtmlReport.ps1        HTML-Report (Port-Spalte + Performance)
│   ├── Send-Alert.ps1            E-Mail via IONOS SMTP (Anti-Spam)
│   └── Push-GitCommit.ps1        Auto-Git-Commit nach jedem Check
├── reports\                      HTML-Reports (in .gitignore)
├── logs\                         Log-Dateien 30 Tage (in .gitignore)
│   └── camera_lockout.json       Reolink Login-Versuche (automatisch)
└── tools\ffmpeg\bin\
    └── ffprobe.exe               Manuell installieren (optional)
```

---

## Sicherheitshinweise

- `credentials.json` → **niemals** committen (in `.gitignore`)
- SSH läuft ausschließlich über Key-Authentifizierung (kein Passwort im Script)
- Kamera-Login: Max. 3 Versuche/Stunde (Lockout-Schutz aktiv)
- DPAPI-Verschlüsselung ist an den lokalen PC + Benutzer gebunden
- GitHub Repository ist **private**

---

*Heimnetz Monitor v2.0 | Armin Rosbach | Stand: April 2026*
