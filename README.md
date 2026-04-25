# Heimnetz Monitor – Einrichtungsanleitung

Automatisches Monitoring-System für 18 Netzwerkgeräte im Heimnetz (192.168.80.0/24).
Prüft alle 15 Minuten, sendet E-Mail-Alarm bei Problemen, erstellt HTML-Reports.

---

## Voraussetzungen

| Anforderung | Version / Info |
|---|---|
| Windows PC | Windows 10/11 (ArminRosbach @ 192.168.80.145) |
| PowerShell | 5.1 oder höher (vorinstalliert) |
| OpenSSH Client | `ssh.exe` verfügbar (Windows 10/11 Feature) |
| GitHub CLI | `gh` installiert und eingerichtet (`gh auth login`) |
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
# Raspberry Pi 5
ssh-copy-id -p 22 pi@192.168.80.20

# Synology DS1525+ (SSH in DSM aktivieren: Systemsteuerung → Terminal)
ssh-copy-id -p 822 Armin@192.168.80.206

# Synology DS723+
ssh-copy-id -p 822 Armin@192.168.80.207
```

Verbindung testen:
```powershell
ssh -o BatchMode=yes pi@192.168.80.20 "echo OK"
ssh -o BatchMode=yes -p 822 Armin@192.168.80.206 "echo OK"
ssh -o BatchMode=yes -p 822 Armin@192.168.80.207 "echo OK"
```
Jeder Befehl muss `OK` ausgeben – ohne Passwort-Abfrage.

---

### Schritt 2 – ffprobe installieren (optional)

Für den Kamera-Stream-Check (prüft ob RTSP-Stream wirklich aktiv ist):

1. ffmpeg herunterladen von: https://ffmpeg.org/download.html → Windows Builds
2. ZIP entpacken nach:
   ```
   C:\Armin\claude_Projekte\Netzwerk-Monitoring\tools\ffmpeg\
   ```
3. Struktur prüfen:
   ```
   tools\ffmpeg\bin\ffprobe.exe   ← muss hier liegen
   tools\ffmpeg\bin\ffmpeg.exe
   ```
4. Testen:
   ```powershell
   .\tools\ffmpeg\bin\ffprobe.exe -version
   ```

Ohne ffprobe läuft das Script normal – nur Ping + Port-Checks für Kameras, kein Stream-Check.

---

### Schritt 3 – E-Mail-Adressen eintragen

`config.json` öffnen und anpassen:
```json
"smtp_von": "monitoring@deine-domain.de",
"smtp_an":  "armin@deine-domain.de"
```

---

### Schritt 4 – Zugangsdaten einrichten

```powershell
.\Setup-Credentials.ps1
```

Abgefragt werden (verschlüsselt mit Windows DPAPI):
- IONOS SMTP Passwort
- Synology DS1525+ DSM Passwort (Benutzer: Armin)
- Synology DS723+ DSM Passwort (Benutzer: Armin)
- Mailstore API Passwort

> **Sicherheit:** `credentials.json` ist in `.gitignore` und kommt **niemals** auf GitHub.
> Die Verschlüsselung ist an diesen PC gebunden – auf anderen PCs nicht entschlüsselbar.

---

### Schritt 5 – Task Scheduler einrichten

Als Administrator ausführen:
```powershell
.\Setup-Task.ps1
```

Legt zwei geplante Aufgaben an:
- **Heimnetz-Monitor-Check**: alle 15 Minuten, ganztags
- **Heimnetz-Monitor-Tagesbericht**: täglich 08:00 Uhr mit E-Mail-Report

---

### Schritt 6 – INSTAR Kamera 2 IP nachtragen

Sobald die IP bekannt ist:
1. `config.json` öffnen
2. Gerät 18 `"INSTAR Kamera 2"` suchen
3. `"SPÄTER_NACHTRAGEN"` durch echte IP ersetzen
4. `"aktiv": false` auf `"aktiv": true` setzen

---

### Schritt 7 – Ersten manuellen Test starten

```powershell
.\Start-NetworkMonitor.ps1
```

Öffnet automatisch den HTML-Report im Browser.
Alle Geräte werden geprüft – Laufzeit ca. 30–60 Sekunden.

---

## Tägliche Nutzung

**Vollautomatisch!** Der Task Scheduler übernimmt alles:

| Aufgabe | Zeitplan | Aktion |
|---|---|---|
| Netzwerk-Check | alle 15 Minuten | Prüft alle Geräte, sendet Alarm bei Problemen |
| Tagesbericht | täglich 08:00 | Vollständiger Report per E-Mail |

Reports werden gespeichert unter:
```
reports\Monitor_YYYYMMDD_HHmm.html   (historisch)
reports\Monitor_Aktuell.html          (immer aktuell)
```

---

## Manueller Start – Parameter

```powershell
# Standard (öffnet Browser)
.\Start-NetworkMonitor.ps1

# Nur Fehler und Warnungen anzeigen
.\Start-NetworkMonitor.ps1 -NurFehler

# Nur ein bestimmtes Gerät prüfen
.\Start-NetworkMonitor.ps1 -Geraet "Synology"
.\Start-NetworkMonitor.ps1 -Geraet "Kamera"
.\Start-NetworkMonitor.ps1 -Geraet "SMA"

# Tagesbericht sofort senden
.\Start-NetworkMonitor.ps1 -Tagesbericht

# Wie Task Scheduler (kein Browser)
.\Start-NetworkMonitor.ps1 -TaskScheduler
```

---

## Gerät nachträglich hinzufügen

1. `config.json` öffnen
2. Neues Objekt in das `"geraete"`-Array eintragen (analog zu bestehenden Geräten)
3. `"aktiv": true` setzen
4. Beim nächsten Check-Intervall (max. 15 Min) wird das Gerät automatisch geprüft

Pflichtfelder: `id`, `name`, `ip`, `typ`, `aktiv`, `checks`

---

## Troubleshooting

### SSH-Verbindung schlägt fehl
```powershell
# Verbose-Modus für Diagnose
ssh -v -p 822 Armin@192.168.80.206
```
Häufige Ursachen:
- SSH im DSM noch nicht aktiviert (Systemsteuerung → Terminal & SNMP)
- Falscher Port (Synology: 822, Pi: 22)
- SSH-Key nicht kopiert → `ssh-copy-id` erneut ausführen

### credentials.json Fehler
```powershell
# Neu erstellen
.\Setup-Credentials.ps1
```
Tritt auf wenn: PC gewechselt, Windows neu installiert oder Benutzerprofil geändert.

### Task Scheduler startet nicht
- PowerShell ExecutionPolicy prüfen: `Get-ExecutionPolicy`
- Task manuell starten: Task-Manager → Registerkarte "Geplante Tasks"
- Log prüfen: `logs\Monitor_YYYYMMDD.log`

### Kamera zeigt WARNUNG obwohl erreichbar
- RTSP Port 554 prüfen: `Test-NetConnection 192.168.80.76 -Port 554`
- ffprobe installieren für genaueren Stream-Check
- Kamera-Neustart prüfen

### Mailstore Gmail-Fehler (bekanntes Problem)
- `andrearosbach27@gmail.com`: Gmail OAuth2-Token abgelaufen
- Lösung: In Mailstore Server → Archivierungsprofile → Gmail-Konto → OAuth2 erneuern

### Synology API Fehler Code 105
- Monitoring-Benutzer hat keine ausreichenden Rechte
- Empfehlung: Dedizierten Read-Only Benutzer in DSM anlegen

---

## Geräte-Übersicht

| # | Name | IP | Typ | Checks |
|---|---|---|---|---|
| 01 | Fritz!Box | 192.168.80.1 | Router | Ping, HTTP, TR-064 |
| 02 | Raspberry Pi 5 | 192.168.80.20 | Raspberry | Ping, SSH, Pi-hole, ntopng |
| 03 | Synology DS1525+ | 192.168.80.206 | NAS | Ping, SSH, DSM API, Docker, SMART |
| 04 | Synology DS723+ | 192.168.80.207 | NAS | Ping, SSH, DSM API, SMART |
| 05 | SASCHA_SERVER | 192.168.80.87 | Windows | Ping, RDP 3389 |
| 06 | Mailstore VM | 192.168.80.120 | Mailstore | Ping, Port 8474, API |
| 07 | SMA Home Manager 2 | 192.168.80.49 | Photovoltaik | Ping, Speedwire 9522 |
| 08 | AC ELWA-E Heizstab | 192.168.80.122 | Heizstab | Ping, JSON API (Temp/Leistung) |
| 09 | Powerline Adapter 1 | 192.168.80.75 | Powerline | Ping, HTTP 80 |
| 10 | Powerline Adapter 2 | 192.168.80.77 | Powerline | Ping, HTTP 80 |
| 11 | Powerline Adapter 3 | 192.168.80.138 | Powerline | Ping, HTTP 80 |
| 12 | Reolink Garten-2 | 192.168.80.76 | Kamera | Ping, RTSP 554, HTTP 80 |
| 13 | Reolink Garten-1 | 192.168.80.127 | Kamera | Ping, RTSP 554, HTTP 80 |
| 14 | Reolink Eingang | 192.168.80.130 | Kamera | Ping, RTSP 554, HTTP 80 |
| 15 | Reolink Keller-Werkstatt | 192.168.80.171 | Kamera | Ping, RTSP 554, HTTP 80 |
| 16 | Reolink Garten-4 | 192.168.80.172 | Kamera | Ping, RTSP 554, HTTP 80 |
| 17 | INSTAR Kamera 1 | 192.168.80.67 | Kamera | Ping, RTSP 554, HTTP 8080 |
| 18 | INSTAR Kamera 2 | SPÄTER_NACHTRAGEN | Kamera | Ping, RTSP 554, HTTP 8080 |

---

## Dateistruktur

```
Netzwerk-Monitoring\
├── Start-NetworkMonitor.ps1    Haupt-Script + HTML-Report Generator
├── config.json                 Geräte-Konfiguration (18 Geräte)
├── Setup-Credentials.ps1       Passwörter sicher speichern (DPAPI)
├── Setup-Task.ps1              Task Scheduler einrichten
├── README.md                   Diese Anleitung
├── .gitignore                  Schützt credentials.json + reports/ + tools/
├── modules\
│   ├── Check-Ping.ps1          Ping-Check
│   ├── Check-Port.ps1          TCP-Port-Check
│   ├── Check-SSH.ps1           SSH-Check (Key-Auth)
│   ├── Check-PiholeAPI.ps1     Pi-hole API
│   ├── Check-NtopngAPI.ps1     ntopng API
│   ├── Check-SynologyAPI.ps1   Synology DSM API (Volumes, SMART, System)
│   ├── Check-Docker.ps1        Docker Compose Status (SSH)
│   ├── Check-MailstoreAPI.ps1  Mailstore Management API
│   ├── Check-SMA.ps1           SMA Speedwire Port 9522
│   ├── Check-ELWA.ps1          AC ELWA-E JSON API
│   ├── Check-Powerline.ps1     Powerline Adapter
│   ├── Check-Camera.ps1        Reolink + INSTAR (RTSP + ffprobe)
│   ├── Check-ExternalLogins.ps1 Auth-Logs + Fritz!Box + RDP
│   ├── Send-Alert.ps1          E-Mail Alarm/Warnung/Tagesbericht
│   └── Push-GitCommit.ps1      GitHub Auto-Commit
├── reports\                    HTML-Reports (nicht auf GitHub)
├── logs\                       Log-Dateien (nicht auf GitHub)
└── tools\ffmpeg\bin\           ffprobe.exe (manuell installieren)
```

---

## Sicherheitshinweise

- `credentials.json` → **niemals** committen (in `.gitignore`)
- SSH läuft ausschließlich über Key-Authentifizierung
- Synology: dedizierten Read-Only Monitoring-Benutzer verwenden (nicht Admin)
- GitHub Repository ist **private**
- DPAPI-Verschlüsselung ist an den lokalen PC gebunden

---

*Heimnetz Monitor v1.0 | Armin Rosbach | Stand: April 2026*
