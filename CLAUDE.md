# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PowerShell-based home network monitoring system for Windows 10/11. Checks 18 devices every 15 minutes via Ping, SSH, REST APIs, and RTSP streams, then sends HTML email alerts and auto-commits results to Git.

GitHub: https://github.com/arovillmar/netzwerk-monitoring (privat)

**Sprache:** Alle Ausgaben, Kommentare und Variablennamen im Projekt sind auf **Deutsch**.

## Running the Monitor

```powershell
# Full check (manual – opens HTML in browser afterward)
.\Start-NetworkMonitor.ps1

# Test a single device by name pattern
.\Start-NetworkMonitor.ps1 -Geraet "Synology"
.\Start-NetworkMonitor.ps1 -Geraet "INSTAR"

# Errors/warnings only in console output
.\Start-NetworkMonitor.ps1 -NurFehler

# As scheduled task (silent, no browser)
.\Start-NetworkMonitor.ps1 -TaskScheduler

# Include daily report email
.\Start-NetworkMonitor.ps1 -TaskScheduler -Tagesbericht
```

## Testing Utilities

```powershell
.\Test-Kameras.ps1          # Camera RTSP/HTTP diagnostics with HTML preview
.\Test-Email.ps1            # SMTP connectivity
.\Test-ReoinkLogin.ps1      # Reolink authentication
```

## Initial Setup (first run on a new machine)

```powershell
# 1. Create SSH keys and copy to Linux hosts
ssh-keygen -t ed25519 -C "heimnetz-monitor"
ssh-copy-id -p 22 pi@192.168.80.20       # Raspberry Pi
ssh-copy-id -p 822 Armin@192.168.80.206  # DS1525+
ssh-copy-id -p 822 Armin@192.168.80.207  # DS723+

# 2. Store encrypted passwords (interactive wizard, 9 credentials)
.\Setup-Credentials.ps1

# 3. Register Windows Task Scheduler tasks (as Administrator)
.\Setup-Task.ps1
```

## Architecture

### Data Flow

```
Start-NetworkMonitor.ps1
  ├── Loads config.json (device list + global settings)
  ├── Loads credentials.json (DPAPI-encrypted, 9 passwords)
  ├── Dot-sources all modules from modules/
  ├── FOR EACH active device → calls type-specific Check-* functions
  │     Result: { Geraet, IP, Status, Info, Latenz, Details }
  ├── New-HtmlReport → reports/Monitor_Aktuell.html + timestamped archive
  ├── Send-Alert (conditional, anti-spam via last_status.json)
  └── Push-GitCommit → auto-commits logs + reports
```

**Wichtig:** `Send-Sofortbericht.ps1` ist ein vollständig eigenständiges Skript (kein Import aus `Start-NetworkMonitor.ps1`). Änderungen an der Monitoring-Logik müssen in beiden Dateien separat gepflegt werden.

### Check Modules (`modules/`)

Each module is a standalone `.ps1` file dot-sourced into the main script. Key modules:

| Module | What it checks |
|---|---|
| `Check-Camera.ps1` | Ping → RTSP:554 → HTTPS snapshot → optional ffprobe stream validation |
| `Check-SynologyAPI.ps1` | SSH commands for RAID/volume status + DSM REST |
| `Check-MailstoreAPI.ps1` | 4-stage: Ping → RDP:3389 → WinRM (PSRemoting) → Mailstore CLI API |
| `Check-PiholeAPI.ps1` | Pi-hole v6 REST (POST /api/auth session, then GET stats) |
| `Check-NtopngAPI.ps1` | ntopng REST v2: external connection count, threat detection; result stored in `$script:NtopngResult` |
| `Check-ExternalLogins.ps1` | Fritz!Box TR-064 + Synology SSH login audit (last 24h) |
| `Check-ELWA.ps1` | GET `/data.jsn`, parses `temp1 ÷ 10 = °C` |
| `Check-SMA.ps1` | Ping + HTTP:80 TCP check (Speedwire is UDP — not directly testable) |
| `Check-Docker.ps1` | TCP port checks per container (Docker socket is root-only, no SSH access): maennerballet:3000, bookstack:6875, nginx-rtmp:1935, nginx:8080 |

### Configuration (`config.json`)

Two-part structure:
- `einstellungen` – global: SMTP settings, timeouts (`ping_timeout_ms: 1000`, `port_timeout_ms: 2000`), anti-spam interval (`max_alarm_wiederholung_minuten: 30`)
- `geraete[]` – 18 device objects: `id`, `name`, `ip`, `typ`, `aktiv`, `checks[]`, per-device API ports/credentials keys

Devices are filtered with `aktiv: true`. The `checks` array drives which modules run per device.

### Credentials (`credentials.json`)

DPAPI-encrypted, PC+user bound — **never committed** (in `.gitignore`). Re-run `Setup-Credentials.ps1` on any new machine. Exact keys used in code:

| Key | Used for |
|---|---|
| `smtp_pass` | IONOS SMTP (exchange.ionos.eu:587 STARTTLS) |
| `pihole_pass` | Pi-hole v6 session auth (POST /api/auth, password only) |
| `nas1_pass` | Synology DS1525+ SSH (user: Armin, port 822) |
| `nas2_pass` | Synology DS723+ SSH (user: Armin, port 822) |
| `mailstore_pass` | Mailstore admin API (user: `admin`, port 8463) |
| `mailstore_win_pass` | Windows VM 192.168.80.120 (user: Administrator, PSRemoting) |
| `reolink_pass` | All 5 Reolink cameras (user: admin) |
| `instar_pass` | Both INSTAR cameras (user: admin, shared password) |
| `ntopng_pass` | ntopng REST v2 (user: admin, port 3000) |

### Alert Logic

`Send-Alert.ps1` (module) and `Send-Sofortbericht.ps1` (standalone) both send emails via IONOS SMTP. Anti-spam is tracked in `last_status.json` — the same alert type is suppressed for `max_alarm_wiederholung_minuten` (default 30 min). Alert types: `Alarm`, `Warnung`, `Entwarnung`, `Tagesbericht`. All email types include ntopng block and camera snapshots.

### Camera Specifics

**Reolink (5 cameras):**
- HTTPS on **port 443** — snapshot URL always starts with `https://<ip>/` (no explicit port)
- Snapshot: `https://<ip>/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=<random>&user=admin&password=<pass>`
- TLS downgrade for older firmware: `[Net.ServicePointManager]::SecurityProtocol = Tls | Tls11 | Tls12`
- `curl.exe` fallback when PowerShell Invoke-WebRequest fails on TLS (checks JPEG magic bytes 0xFF 0xD8)
- RTSP closed on most cameras → no WARNUNG raised (HTTP alone = OK)
- Eingang (.130): ports 80/443/554 manually opened in iPhone app

**INSTAR (2 cameras):**
- HTTP port **8011** (not 80, not 8080), HTTPS 4430, RTSP 554/1554
- Auth: Basic Auth header; `curl.exe --digest` fallback if Basic fails
- Snapshot URL order: `/snap.cgi` → `/tmpfs/snap.jpg` → `/cgi-bin/snapshot.cgi`
  - Kamera 1 (.67): `/snap.cgi` works
  - Kamera 2 (.50): `/tmpfs/snap.jpg` works
- `ffprobe` (optional, `tools/ffmpeg/bin/ffprobe.exe`) validates live RTSP streams; checks degrade gracefully without it

### Mailstore API

- **Port 8463**, user `admin` (Mailstore-eigener Admin — nicht Windows Administrator!)
- **Date format:** `yyyy-MM-ddTHH:mm:ss` (no timezone suffix, no locale separators)
- **GetJobResults requires 3 parameters:** `fromIncluding`, `toExcluding`, `timeZoneId` (`"W. Europe Standard Time"`)
- **BOM handling:** always strip before parsing: `.TrimStart([char]0xFEFF) | ConvertFrom-Json`

### Output Files

| Path | Description |
|---|---|
| `reports/Monitor_Aktuell.html` | Always-current HTML dashboard |
| `reports/Monitor_YYYYMMDD_HHMM.html` | Timestamped archive |
| `logs/Monitor_YYYYMMDD.log` | Daily log, 30-day retention |
| `last_status.json` | Alert anti-spam state (not committed) |

All output paths are in `.gitignore` except the auto-committed Git entries from `Push-GitCommit.ps1`.

## Key Conventions

- Status values used throughout: `"OK"`, `"WARNUNG"`, `"FEHLER"`, `"UNBEKANNT"`.
- Check functions return a consistent hashtable: `@{ Status; Info; Latenz; Details }`.
- SSH connections use key-based auth only — no password prompts in automation.
- `$script:NtopngResult` is the scope variable that carries ntopng data from the device loop into `Send-Alert`.
