# Create-Systemdoku.ps1
# Erstellt Word-Dokumentation der kompletten Heimnetz-Systemlandschaft

param(
    [string]$Ausgabepfad = "C:\Armin\Systemlandschaft_Heimnetz_$(Get-Date -Format 'yyyyMMdd').docx"
)

Write-Host "Erstelle Systemdokumentation..." -ForegroundColor Cyan

try {
    $word = New-Object -ComObject Word.Application -ErrorAction Stop
} catch {
    Write-Error "Microsoft Word nicht gefunden: $_"
    exit 1
}
$word.Visible = $false
$doc = $word.Documents.Add()
$sel = $word.Selection

# ===== HILFSFUNKTIONEN =====
function Write-H1 { param($t); $sel.Style = -2; $sel.TypeText($t); $sel.TypeParagraph() }
function Write-H2 { param($t); $sel.Style = -3; $sel.TypeText($t); $sel.TypeParagraph() }
function Write-H3 { param($t); $sel.Style = -4; $sel.TypeText($t); $sel.TypeParagraph() }
function Write-P  { param($t); $sel.Style = -1; $sel.TypeText($t); $sel.TypeParagraph() }

function Write-Info {
    param([string]$Label, [string]$Wert)
    $sel.Style = -1
    $sel.Font.Bold = $true;  $sel.TypeText("${Label}: ")
    $sel.Font.Bold = $false; $sel.TypeText($Wert)
    $sel.TypeParagraph()
}

function Write-Bullet { param($t); $sel.Style = -1; $sel.TypeText("  • $t"); $sel.TypeParagraph() }

function New-Table {
    param([string[]]$Spalten, [string[][]]$Zeilen)
    $tbl = $doc.Tables.Add($sel.Range, ($Zeilen.Count + 1), $Spalten.Count)
    $tbl.Borders.Enable = $true
    for ($c = 1; $c -le $Spalten.Count; $c++) {
        $tbl.Cell(1, $c).Range.Text = $Spalten[$c - 1]
        $tbl.Cell(1, $c).Range.Font.Bold = $true
    }
    for ($r = 0; $r -lt $Zeilen.Count; $r++) {
        $z = $Zeilen[$r]
        for ($c = 1; $c -le [Math]::Min($Spalten.Count, $z.Count); $c++) {
            $tbl.Cell($r + 2, $c).Range.Text = $z[$c - 1]
        }
    }
    $rng = $tbl.Range; $rng.Collapse(0)
    $sel.SetRange($rng.Start, $rng.End)
    $sel.TypeParagraph()
}

# ===== INHALT =====

Write-H1 "Systemlandschaft Heimnetz – Armin Rosbach"
Write-P  "Netzwerksegment: 192.168.80.0/24  |  Stand: $(Get-Date -Format 'dd. MMMM yyyy')"
Write-P  "Zweck: Grundlage fuer neues Projekt 'IP-Alias & HTTPS-Zertifikate'"
Write-P  ""

# 1. GERAETE-INVENTAR
Write-H1 "1. Geraete-Inventar (18 aktive Geraete)"
New-Table `
    -Spalten @("ID", "Geraet", "IP-Adresse", "Typ", "Hauptfunktion") `
    -Zeilen @(
        ,@("1",  "Fritz!Box",            "192.168.80.1",   "Router",       "Gateway, DHCP, DNS, VPN (WireGuard/IPSec)")
        ,@("2",  "Raspberry Pi 5",       "192.168.80.20",  "Linux-Server", "Pi-hole (DNS/Adblocker), ntopng (Traffic-Monitoring)")
        ,@("3",  "Synology DS1525+",     "192.168.80.206", "NAS",          "Haupt-NAS, Docker-Host (4 Container)")
        ,@("4",  "Synology DS723+",      "192.168.80.207", "NAS",          "Backup-NAS, kein Docker")
        ,@("5",  "SASCHA_SERVER",        "192.168.80.87",  "Windows-PC",   "Host fuer Mailstore VM, RDP 3389")
        ,@("6",  "Mailstore VM",         "192.168.80.120", "Windows-VM",   "E-Mail-Archivierung, MailStore Server v26.1")
        ,@("7",  "SMA Home Manager 2",   "192.168.80.49",  "IoT",          "PV-Anlage Steuerung (Speedwire)")
        ,@("8",  "AC ELWA-E Heizstab",   "192.168.80.122", "IoT",          "PV-Warmwasser, my-PV")
        ,@("9",  "Powerline Adapter 1",  "192.168.80.75",  "Netzwerk",     "Fritz!Box Powerline Adapter")
        ,@("10", "Powerline Adapter 2",  "192.168.80.77",  "Netzwerk",     "Fritz!Box Powerline Adapter")
        ,@("11", "Powerline Adapter 3",  "192.168.80.138", "Netzwerk",     "Fritz!Box Powerline Adapter")
        ,@("12", "Reolink Garten-2",     "192.168.80.76",  "IP-Kamera",    "RLC-820A, Garten Sued")
        ,@("13", "Reolink Garten-1",     "192.168.80.127", "IP-Kamera",    "RLC-820A, Garten Nord")
        ,@("14", "Reolink Eingang",      "192.168.80.130", "IP-Kamera",    "RLC-843A, Eingang/Tor")
        ,@("15", "Reolink Keller",       "192.168.80.171", "IP-Kamera",    "RLC-810A, Keller/Werkstatt")
        ,@("16", "Reolink Garten-4",     "192.168.80.172", "IP-Kamera",    "RLC-820A, Garten")
        ,@("17", "INSTAR Kamera 1",      "192.168.80.67",  "IP-Kamera",    "INSTAR Innen, HTTP 8011, HTTPS 4430")
        ,@("18", "INSTAR Kamera 2",      "192.168.80.50",  "IP-Kamera",    "INSTAR Innen, HTTP 8011, HTTPS 4430")
    )

# 2. NETZWERK-INFRASTRUKTUR
Write-H1 "2. Netzwerk-Infrastruktur"

Write-H2 "2.1 Fritz!Box (Router/Gateway)"
Write-Info "IP-Adresse"    "192.168.80.1"
Write-Info "Funktion"      "Gateway, DHCP-Server, DNS-Resolver, NAT/Firewall"
Write-Info "VPN"           "WireGuard + IPSec (MyFRITZ! externer Zugang)"
Write-Info "Dienste"       "HTTP 80 (Web-UI), TR-064 API (UPnP), DNS 53"
Write-Info "Protokoll"     "HTTP intern — HTTPS extern via MyFRITZ!"
Write-P ""

Write-H2 "2.2 Raspberry Pi 5"
Write-Info "Hostname"      "raspberry5"
Write-Info "IP-Adresse"    "192.168.80.20"
Write-Info "OS"            "Debian Trixie"
Write-Info "SSH"           "Port 22, Key-Authentifizierung (User: pi)"
Write-Info "Pi-hole URL"   "http://192.168.80.20/admin  (HTTP, kein HTTPS)"
Write-Info "ntopng URL"    "http://192.168.80.20:3000   (HTTP, kein HTTPS)"
Write-P ""

Write-H2 "2.3 Powerline Adapter (3x Fritz!Box)"
New-Table `
    -Spalten @("Bezeichnung", "IP-Adresse", "Port", "Protokoll") `
    -Zeilen @(
        ,@("Powerline Adapter 1", "192.168.80.75",  "80", "HTTP")
        ,@("Powerline Adapter 2", "192.168.80.77",  "80", "HTTP")
        ,@("Powerline Adapter 3", "192.168.80.138", "80", "HTTP")
    )

# 3. SERVER & NAS
Write-H1 "3. Server & NAS"

Write-H2 "3.1 Synology DS1525+ (Haupt-NAS)"
Write-Info "IP-Adresse"    "192.168.80.206"
Write-Info "SSH"           "Port 822, User: Armin, Key-Authentifizierung"
Write-Info "DSM Web-UI"    "http://192.168.80.206:5000  (HTTPS: Port 5001 vorhanden)"
Write-Info "Docker"        "Aktiv – 4 Container (siehe Abschnitt 4)"
Write-Info "Betrieb"       "Dauerbetrieb 24/7"
Write-P ""

Write-H2 "3.2 Synology DS723+ (Backup-NAS)"
Write-Info "IP-Adresse"    "192.168.80.207"
Write-Info "SSH"           "Port 822, User: Armin, Key-Authentifizierung"
Write-Info "DSM Web-UI"    "http://192.168.80.207:5000  (HTTPS: Port 5001 vorhanden)"
Write-Info "Docker"        "Nicht installiert"
Write-Info "Betrieb"       "Dauerbetrieb 24/7"
Write-P ""

Write-H2 "3.3 SASCHA_SERVER (Windows 10 Host)"
Write-Info "IP-Adresse"    "192.168.80.87"
Write-Info "OS"            "Windows 10 Pro 64-bit"
Write-Info "Funktion"      "Hyper-V Host fuer Mailstore VM"
Write-Info "Fernzugriff"   "RDP Port 3389"
Write-P ""

Write-H2 "3.4 Mailstore VM"
Write-Info "IP-Adresse"    "192.168.80.120"
Write-Info "Software"      "MailStore Server v26.1.0.23845"
Write-Info "Lizenz"        "FEP Financial Engineering Partners.com, 5 Benutzer"
Write-Info "Archiv"        "545.439 Nachrichten"
Write-Info "API"           "HTTP Port 8463 (Management API, User: admin — NICHT Windows-Admin!)"
Write-Info "PSRemoting"    "WinRM (User: Administrator)"
Write-Info "Datumsformat"  "yyyy-MM-ddTHH:mm:ss (kein Timezone-Suffix)"
Write-Info "Bekannte Probleme" "Gmail OAuth2 fehlt; IONOS-Konten unverschluesselt"
Write-P ""

# 4. DOCKER-CONTAINER
Write-H1 "4. Docker-Container (Synology DS1525+, 192.168.80.206)"
Write-P "Docker-Socket ist root:root — kein SSH-docker-Zugriff moeglich. Monitoring via TCP-Port-Check."
Write-P ""
New-Table `
    -Spalten @("Container", "Port", "Protokoll", "Beschreibung", "URL") `
    -Zeilen @(
        ,@("maennerballet", "3000", "HTTP", "Web-Applikation",    "http://192.168.80.206:3000")
        ,@("bookstack",     "6875", "HTTP", "Wiki / Dokumentation","http://192.168.80.206:6875")
        ,@("nginx-rtmp",    "1935", "RTMP", "Video-Streaming",     "rtmp://192.168.80.206:1935")
        ,@("nginx",         "8080", "HTTP", "nginx Web-Server",    "http://192.168.80.206:8080")
    )

# 5. KAMERAS
Write-H1 "5. IP-Kameras"

Write-H2 "5.1 Reolink Kameras (5 Stueck)"
Write-P "Snapshot-URL: https://IP/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=RAND&user=admin&password=PASS"
Write-P "RTSP bei den meisten Kameras deaktiviert (kein WARNUNG-Status, HTTP allein genuegt)."
Write-P ""
New-Table `
    -Spalten @("Name", "IP-Adresse", "Modell", "HTTP", "HTTPS", "RTSP", "Standort") `
    -Zeilen @(
        ,@("Reolink Garten-2", "192.168.80.76",  "RLC-820A", "80", "443", "554", "Garten Sued")
        ,@("Reolink Garten-1", "192.168.80.127", "RLC-820A", "80", "443", "554", "Garten Nord")
        ,@("Reolink Eingang",  "192.168.80.130", "RLC-843A", "80", "443", "554", "Eingang/Tor (Ports manuell geoeffnet)")
        ,@("Reolink Keller",   "192.168.80.171", "RLC-810A", "80", "443", "554", "Keller/Werkstatt")
        ,@("Reolink Garten-4", "192.168.80.172", "RLC-820A", "80", "443", "554", "Garten")
    )

Write-H2 "5.2 INSTAR Kameras (2 Stueck)"
Write-P "HTTP-Port 8011 (nicht 80!), HTTPS 4430, RTSP 554 und 1554."
Write-P "Auth: Basic Auth Header. curl.exe Digest-Fallback wenn Basic Auth scheitert."
Write-P "Snapshot-Reihenfolge: /snap.cgi -> /tmpfs/snap.jpg -> /cgi-bin/snapshot.cgi"
Write-P ""
New-Table `
    -Spalten @("Name", "IP-Adresse", "HTTP", "HTTPS", "RTSP", "Snapshot-URL", "Standort") `
    -Zeilen @(
        ,@("INSTAR Kamera 1", "192.168.80.67", "8011", "4430", "554/1554", "/snap.cgi",       "Innenbereich 1")
        ,@("INSTAR Kamera 2", "192.168.80.50", "8011", "4430", "554/1554", "/tmpfs/snap.jpg", "Innenbereich 2")
    )

# 6. IOT & ENERGIE
Write-H1 "6. IoT & Energie-Management"

Write-H2 "6.1 SMA Home Manager 2 (PV-Anlage)"
Write-Info "IP-Adresse"  "192.168.80.49"
Write-Info "Dienste"     "HTTP 80 (Web-UI), Speedwire UDP 9522"
Write-Info "Funktion"    "Steuerung und Monitoring der Photovoltaik-Anlage"
Write-Info "Hinweis"     "Speedwire ist UDP — nur Ping + HTTP testbar"
Write-P ""

Write-H2 "6.2 AC ELWA-E Heizstab (my-PV)"
Write-Info "IP-Adresse"  "192.168.80.122"
Write-Info "API"         "HTTP GET http://192.168.80.122/data.jsn (JSON)"
Write-Info "Funktion"    "Warmwasser-Aufbereitung mit PV-Ueberschuss"
Write-Info "Temperatur"  "temp1 / 10 = Grad C, WARNUNG bei > 75 Grad C"
Write-P ""

# 7. SERVICE-PORT-UEBERSICHT
Write-H1 "7. Vollstaendige Service- & Port-Uebersicht"
Write-P "Alle erreichbaren Dienste mit Port, Protokoll und HTTP/HTTPS-Status:"
Write-P ""
New-Table `
    -Spalten @("Geraet", "IP", "Port", "Protokoll", "Dienst", "HTTP/HTTPS") `
    -Zeilen @(
        ,@("Fritz!Box",         "192.168.80.1",   "80",   "HTTP",    "Router Web-UI",            "HTTP")
        ,@("Fritz!Box",         "192.168.80.1",   "53",   "DNS",     "DNS-Resolver",             "UDP")
        ,@("Raspberry Pi 5",    "192.168.80.20",  "22",   "SSH",     "Shell",                    "SSH (TLS)")
        ,@("Raspberry Pi 5",    "192.168.80.20",  "80",   "HTTP",    "Pi-hole Admin /admin",     "HTTP (kein HTTPS!)")
        ,@("Raspberry Pi 5",    "192.168.80.20",  "3000", "HTTP",    "ntopng Dashboard",         "HTTP (kein HTTPS!)")
        ,@("Synology DS1525+",  "192.168.80.206", "822",  "SSH",     "NAS Shell",                "SSH (TLS)")
        ,@("Synology DS1525+",  "192.168.80.206", "5000", "HTTP",    "DSM Web-UI",               "HTTP (HTTPS 5001 moeglich)")
        ,@("Synology DS1525+",  "192.168.80.206", "5001", "HTTPS",   "DSM Web-UI sicher",        "HTTPS")
        ,@("Synology DS1525+",  "192.168.80.206", "3000", "HTTP",    "Docker: maennerballet",    "HTTP (kein HTTPS!)")
        ,@("Synology DS1525+",  "192.168.80.206", "6875", "HTTP",    "Docker: BookStack Wiki",   "HTTP (kein HTTPS!)")
        ,@("Synology DS1525+",  "192.168.80.206", "1935", "RTMP",    "Docker: nginx-rtmp",       "RTMP")
        ,@("Synology DS1525+",  "192.168.80.206", "8080", "HTTP",    "Docker: nginx",            "HTTP (kein HTTPS!)")
        ,@("Synology DS723+",   "192.168.80.207", "822",  "SSH",     "NAS Shell",                "SSH (TLS)")
        ,@("Synology DS723+",   "192.168.80.207", "5000", "HTTP",    "DSM Web-UI",               "HTTP (HTTPS 5001 moeglich)")
        ,@("SASCHA_SERVER",     "192.168.80.87",  "3389", "RDP",     "Windows Remote Desktop",   "RDP (TLS)")
        ,@("Mailstore VM",      "192.168.80.120", "8463", "HTTP",    "MailStore API",            "HTTP (nur intern)")
        ,@("SMA Home Manager",  "192.168.80.49",  "80",   "HTTP",    "PV-Manager Web-UI",        "HTTP")
        ,@("SMA Home Manager",  "192.168.80.49",  "9522", "UDP",     "Speedwire Protokoll",      "UDP")
        ,@("ELWA-E",            "192.168.80.122", "80",   "HTTP",    "JSON API /data.jsn",       "HTTP")
        ,@("Reolink (5x)",      "div. .76-.172",  "443",  "HTTPS",   "Kamera API + Snapshot",    "HTTPS (Hersteller-Zertifikat)")
        ,@("Reolink (5x)",      "div. .76-.172",  "554",  "RTSP",    "Video-Stream",             "RTSP")
        ,@("INSTAR (2x)",       ".67 und .50",    "8011", "HTTP",    "Kamera Web-UI",            "HTTP")
        ,@("INSTAR (2x)",       ".67 und .50",    "4430", "HTTPS",   "Kamera HTTPS",             "HTTPS (vorhanden)")
        ,@("INSTAR (2x)",       ".67 und .50",    "554",  "RTSP",    "Video-Stream",             "RTSP")
    )

# 8. SICHERHEITSANALYSE
Write-H1 "8. Sicherheitsanalyse: HTTP vs. HTTPS"
Write-P "Grundlage fuer das Projekt 'IP-Alias & HTTPS-Zertifikate'."
Write-P ""

Write-H2 "8.1 Handlungsbedarf (HTTP ohne Verschluesselung)"
New-Table `
    -Spalten @("Dienst", "IP:Port", "Prioritaet", "Begruendung") `
    -Zeilen @(
        ,@("Pi-hole Admin",      "192.168.80.20:80",    "HOCH",    "Passwort-Anmeldung ueber HTTP")
        ,@("ntopng Dashboard",   "192.168.80.20:3000",  "HOCH",    "Traffic-Daten + Passwort unverschluesselt")
        ,@("BookStack Wiki",     "192.168.80.206:6875", "HOCH",    "Wiki-Inhalte + Anmeldung unverschluesselt")
        ,@("maennerballet App",  "192.168.80.206:3000", "MITTEL",  "Webapp ueber HTTP")
        ,@("nginx Docker",       "192.168.80.206:8080", "MITTEL",  "HTTP-Endpunkt ohne TLS")
        ,@("DSM (beide NAS)",    "*.206:5000 / *.207:5000","MITTEL","HTTPS-Port 5001 bereits da, 5000 offen")
        ,@("SMA Home Manager",   "192.168.80.49:80",    "NIEDRIG", "Nur Status, keine Anmeldung")
        ,@("ELWA-E Heizstab",    "192.168.80.122:80",   "NIEDRIG", "Nur JSON-Status, keine Credentials")
    )

Write-H2 "8.2 Bereits sicher aufgestellt"
New-Table `
    -Spalten @("Dienst", "IP:Port", "Zertifikat", "Bemerkung") `
    -Zeilen @(
        ,@("Reolink Kameras (5x)", "div:443",  "Hersteller", "HTTPS-Snapshot-API")
        ,@("INSTAR Kameras (2x)", "div:4430",  "Hersteller", "HTTPS vorhanden")
        ,@("Fritz!Box extern",    "myfritz.net","Let's Encrypt","Extern via MyFRITZ!")
        ,@("SSH (alle Server)",   "div:22/822", "SSH-Key",    "Key-Authentifizierung")
        ,@("RDP (SASCHA_SERVER)", ".87:3389",   "TLS",        "Verschluesselt")
    )

# 9. PLANUNG: IP-ALIAS & HTTPS
Write-H1 "9. Planung: IP-Alias & HTTPS-Zertifikate (Neues Claude-Projekt)"

Write-H2 "9.1 Projektziele"
Write-Bullet "Sprechende Alias-Namen fuer alle Anwendungen (z.B. pihole.home, bookstack.home)"
Write-Bullet "HTTPS fuer alle Dienste mit Passwort-Anmeldung"
Write-Bullet "Gueltige Zertifikate (keine Browser-Sicherheitswarnung)"
Write-Bullet "Zentrale Verwaltung via Reverse Proxy"
Write-Bullet "DNS-basierte Alias-Aufloesung intern via Pi-hole"
Write-P ""

Write-H2 "9.2 Geplante Alias-Namen (Vorschlag)"
New-Table `
    -Spalten @("Alias", "Ziel-IP", "Ziel-Port", "HTTPS", "Prioritaet") `
    -Zeilen @(
        ,@("pihole.home",        "192.168.80.20",  "80/443",  "ja", "HOCH")
        ,@("ntopng.home",        "192.168.80.20",  "3000/443","ja", "HOCH")
        ,@("bookstack.home",     "192.168.80.206", "6875/443","ja", "HOCH")
        ,@("nas1.home",          "192.168.80.206", "5001",    "ja", "MITTEL")
        ,@("nas2.home",          "192.168.80.207", "5001",    "ja", "MITTEL")
        ,@("maennerballet.home", "192.168.80.206", "3000/443","ja", "MITTEL")
        ,@("fritzbox.home",      "192.168.80.1",   "80",      "nein","NIEDRIG")
        ,@("sma.home",           "192.168.80.49",  "80",      "nein","NIEDRIG")
        ,@("elwa.home",          "192.168.80.122", "80",      "nein","NIEDRIG")
        ,@("mailstore.home",     "192.168.80.120", "8463",    "nein","NIEDRIG")
    )

Write-H2 "9.3 Technischer Ansatz (3 Optionen)"

Write-H3 "Option A: Pi-hole DNS + Nginx Reverse Proxy auf DS1525+ (EMPFOHLEN)"
Write-Bullet "Pi-hole: Custom DNS Records fuer *.home -> IP des Reverse Proxy (DS1525+)"
Write-Bullet "Nginx Proxy Manager als neuer Docker-Container auf DS1525+ (Port 81 Admin, 80/443 Proxy)"
Write-Bullet "Zertifikate: mkcert (lokal) oder Let's Encrypt via DNS-Challenge"
Write-Bullet "Vorteil: Pi-hole bereits vorhanden, DS1525+ laeuft 24/7, nginx schon in Docker"
Write-P ""

Write-H3 "Option B: Traefik als Reverse Proxy (Docker auf DS1525+)"
Write-Bullet "Automatische Service-Discovery via Docker Labels"
Write-Bullet "Let's Encrypt mit DNS-Challenge (z.B. Cloudflare API)"
Write-Bullet "Vorteil: Automatische Konfiguration — nachteil: komplexere Einrichtung"
Write-P ""

Write-H3 "Option C: Synology Reverse Proxy (DSM eingebaut)"
Write-Bullet "DSM > Systemsteuerung > Anwendungsportal > Reverseproxy"
Write-Bullet "Synology eigener Certificate Manager mit Let's Encrypt"
Write-Bullet "Vorteil: Kein zusaetzlicher Docker-Container — Nachteil: weniger flexibel"
Write-P ""

Write-H2 "9.4 Zertifikat-Optionen"
New-Table `
    -Spalten @("Option", "Methode", "Gueltigkeit", "Aufwand", "Empfehlung") `
    -Zeilen @(
        ,@("mkcert",         "Lokale CA + mkcert-Tool, Root-CA in Windows/Browser importieren", "Unbegrenzt", "Niedrig", "Ideal fuer rein internes Netz")
        ,@("Let's Encrypt",  "ACME DNS-Challenge, kein Port 80/443 extern noetig",              "90 Tage",    "Mittel",  "Beste Loesung mit DNS-API")
        ,@("Synology CA",    "DSM Certificate Manager",                                          "Frei",       "Niedrig", "Nur fuer DSM-Dienste")
        ,@("Self-signed CA", "Eigene Root-CA + Intermediate-CA, manuell verwaltet",              "Frei",       "Hoch",    "Maximale Kontrolle")
    )

Write-H2 "9.5 Umsetzungsreihenfolge (empfohlen)"
Write-P "Phase 1 — DNS-Grundlage"
Write-Bullet "Pi-hole: Custom DNS Records fuer alle *.home Alias-Namen anlegen"
Write-Bullet "Test: ping pihole.home -> muss 192.168.80.20 aufloesen"
Write-Bullet "Fritz!Box: DNS-Rebind-Schutz fuer *.home pruefen/deaktivieren"
Write-P ""
Write-P "Phase 2 — Reverse Proxy"
Write-Bullet "Nginx Proxy Manager als Docker-Container auf DS1525+ deployen"
Write-Bullet "Erste Route: pihole.home -> http://192.168.80.20:80"
Write-Bullet "Testen im Browser: http://pihole.home"
Write-P ""
Write-P "Phase 3 — Zertifikate"
Write-Bullet "mkcert installieren (choco install mkcert oder direkter Download)"
Write-Bullet "mkcert -install  (Root-CA in Windows Certificate Store einpflegen)"
Write-Bullet "mkcert *.home pihole.home ntopng.home bookstack.home  (Wildcard-Zertifikat)"
Write-Bullet "Zertifikat in Nginx Proxy Manager einbinden"
Write-P ""
Write-P "Phase 4 — Alle Dienste migrieren"
Write-Bullet "Schrittweise alle Dienste in den Reverse Proxy aufnehmen (HOCH -> MITTEL -> NIEDRIG)"
Write-P ""

Write-H2 "9.6 Voraussetzungen"
Write-Bullet "Pi-hole: Custom DNS Records verfuegbar (Pi-hole v5+ / v6)"
Write-Bullet "DS1525+ Docker: Freier Port fuer Nginx Proxy Manager (81, 80, 443)"
Write-Bullet "Windows-Client: mkcert Root-CA in Windows Certificate Store importieren"
Write-Bullet "Fritz!Box: DNS-Rebind-Schutz fuer *.home Domain deaktivieren (falls noetig)"
Write-Bullet "Browser: Root-CA einmalig vertrauen (automatisch via mkcert -install)"
Write-P ""

# 10. MONITORING-SYSTEM
Write-H1 "10. Monitoring-System (Netzwerk-Monitoring)"
Write-Info "Pfad"          "C:\Armin\claude_Projekte\Netzwerk-Monitoring\"
Write-Info "GitHub"        "https://github.com/arovillmar/netzwerk-monitoring (privat)"
Write-Info "Intervall"     "Alle 15 Minuten via Windows Task Scheduler"
Write-Info "Tagesbericht"  "Taeglich 08:00 Uhr per E-Mail"
Write-Info "E-Mail"        "rosbach@fe-partners.com (IONOS SMTP exchange.ionos.eu:587 STARTTLS)"
Write-Info "Alarm"         "Bei Fehler + Warnung, max. 1x pro 30 Minuten (Anti-Spam)"
Write-P ""

Write-H2 "10.1 Check-Module"
New-Table `
    -Spalten @("Modul", "Funktion") `
    -Zeilen @(
        ,@("Check-Camera.ps1",        "Ping, RTSP:554, HTTPS-Snapshot (JPEG 0xFF 0xD8 Validierung)")
        ,@("Check-SynologyAPI.ps1",   "SSH: df -h, mdstat, uptime — RAID/SMART/Speicherplatz")
        ,@("Check-MailstoreAPI.ps1",  "Ping, RDP:3389, WinRM, Admin-API Port 8463")
        ,@("Check-PiholeAPI.ps1",     "Pi-hole v6: REST POST /api/auth + GET Stats")
        ,@("Check-NtopngAPI.ps1",     "ntopng REST v2: externe Flows, Bedrohungserkennung")
        ,@("Check-ExternalLogins.ps1","Fritz!Box TR-064 + Synology SSH Login-Audit (24h)")
        ,@("Check-Docker.ps1",        "TCP-Port-Check pro Container (4 Container)")
        ,@("Check-ELWA.ps1",          "HTTP GET /data.jsn, Temperatur-Auswertung")
        ,@("Check-SMA.ps1",           "Ping + HTTP:80 (Speedwire ist UDP)")
        ,@("Check-SSH.ps1",           "SSH-Test mit 10s Timeout via Start-Job")
    )

Write-H2 "10.2 Credentials (DPAPI-verschluesselt, 9 Passwoerter)"
New-Table `
    -Spalten @("Schluessel", "Verwendung", "System") `
    -Zeilen @(
        ,@("smtp_pass",          "IONOS SMTP Versand",           "exchange.ionos.eu:587")
        ,@("pihole_pass",        "Pi-hole v6 Session-Auth",      "192.168.80.20/api/auth")
        ,@("nas1_pass",          "Synology DS1525+ SSH",         "192.168.80.206:822, User: Armin")
        ,@("nas2_pass",          "Synology DS723+ SSH",          "192.168.80.207:822, User: Armin")
        ,@("mailstore_pass",     "MailStore Admin API",          "192.168.80.120:8463, User: admin")
        ,@("mailstore_win_pass", "Windows VM PSRemoting",        "192.168.80.120, User: Administrator")
        ,@("reolink_pass",       "Alle 5 Reolink Kameras",       "div. IPs, User: admin")
        ,@("instar_pass",        "Beide INSTAR Kameras",         "192.168.80.67+50, User: admin")
        ,@("ntopng_pass",        "ntopng REST API",              "192.168.80.20:3000, User: admin")
    )

# ABSCHLUSS
Write-P ""
Write-P "--- Ende der Dokumentation ---"
Write-P "Erstellt am: $(Get-Date -Format 'dd.MM.yyyy HH:mm') Uhr mit Create-Systemdoku.ps1"

# SPEICHERN
Write-Host "Speichere Word-Dokument..." -ForegroundColor Yellow
try {
    $doc.SaveAs([ref]$Ausgabepfad)
    Write-Host ""
    Write-Host "Fertig! Dokument gespeichert:" -ForegroundColor Green
    Write-Host $Ausgabepfad -ForegroundColor White
    $word.Visible = $true
} catch {
    Write-Error "Fehler beim Speichern: $_"
    $doc.Close($false)
    $word.Quit()
}
