#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$SkriptPfad    = Split-Path -Parent $MyInvocation.MyCommand.Path
$HauptSkript   = Join-Path $SkriptPfad "Start-NetworkMonitor.ps1"
$CredPfad      = Join-Path $SkriptPfad "credentials.json"
$GitOrdner     = Join-Path $SkriptPfad ".git"
$TaskName1     = "Heimnetz-Monitor-Check"
$TaskName2     = "Heimnetz-Monitor-Tagesbericht"

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║     Heimnetz Monitor – Task Scheduler einrichten     ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Voraussetzungen prüfen ───────────────────────────────────────────────────
$fehler = $false

Write-Host "  Prüfe Voraussetzungen..." -ForegroundColor Gray
Write-Host ""

# 1. credentials.json
if (Test-Path $CredPfad) {
    Write-Host "  [OK] credentials.json vorhanden" -ForegroundColor Green
} else {
    Write-Host "  [!!] credentials.json FEHLT" -ForegroundColor Red
    Write-Host "       Bitte zuerst ausfuehren: .\Setup-Credentials.ps1" -ForegroundColor Yellow
    $fehler = $true
}

# 2. Haupt-Skript
if (Test-Path $HauptSkript) {
    Write-Host "  [OK] Start-NetworkMonitor.ps1 vorhanden" -ForegroundColor Green
} else {
    Write-Host "  [!!] Start-NetworkMonitor.ps1 FEHLT unter $HauptSkript" -ForegroundColor Red
    $fehler = $true
}

# 3. SSH-Key Test (Raspberry Pi)
Write-Host "  [..] Teste SSH-Key zu Raspberry Pi (192.168.80.20)..." -ForegroundColor Gray -NoNewline
try {
    $sshTest = & ssh.exe -o "BatchMode=yes" -o "ConnectTimeout=3" -o "StrictHostKeyChecking=no" `
        "pi@192.168.80.20" "echo OK" 2>&1
    if ($sshTest -match "OK") {
        Write-Host "`r  [OK] SSH-Key zu Raspberry Pi funktioniert          " -ForegroundColor Green
    } else {
        Write-Host "`r  [!!] SSH-Key zu Raspberry Pi nicht eingerichtet    " -ForegroundColor Yellow
        Write-Host "       Befehl: ssh-copy-id -p 22 pi@192.168.80.20" -ForegroundColor Gray
    }
} catch {
    Write-Host "`r  [??] SSH-Test fehlgeschlagen: $($_.Exception.Message)    " -ForegroundColor Yellow
}

# 4. SSH-Key Test (DS1525+)
Write-Host "  [..] Teste SSH-Key zu DS1525+ (192.168.80.206)..." -ForegroundColor Gray -NoNewline
try {
    $sshTest2 = & ssh.exe -o "BatchMode=yes" -o "ConnectTimeout=3" -o "StrictHostKeyChecking=no" `
        -p 822 "Armin@192.168.80.206" "echo OK" 2>&1
    if ($sshTest2 -match "OK") {
        Write-Host "`r  [OK] SSH-Key zu DS1525+ funktioniert                " -ForegroundColor Green
    } else {
        Write-Host "`r  [!!] SSH-Key zu DS1525+ nicht eingerichtet          " -ForegroundColor Yellow
        Write-Host "       Befehl: ssh-copy-id -p 822 Armin@192.168.80.206" -ForegroundColor Gray
    }
} catch {
    Write-Host "`r  [??] SSH-Test fehlgeschlagen                            " -ForegroundColor Yellow
}

# 5. Git-Repository
if (Test-Path $GitOrdner) {
    Write-Host "  [OK] Git-Repository vorhanden" -ForegroundColor Green
} else {
    Write-Host "  [!!] Git-Repository FEHLT – wird beim ersten Lauf automatisch erstellt" -ForegroundColor Yellow
}

Write-Host ""

if ($fehler) {
    Write-Host "  Fehler gefunden – bitte erst beheben, dann erneut ausfuehren." -ForegroundColor Red
    Write-Host ""
    exit 1
}

# ── Task 1: Alle 15 Minuten ──────────────────────────────────────────────────
Write-Host "  Erstelle Task 1: '$TaskName1' (alle 15 Minuten)..." -ForegroundColor Gray

try {
    # Vorhandenen Task entfernen
    if (Get-ScheduledTask -TaskName $TaskName1 -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName1 -Confirm:$false
        Write-Host "  Vorhandener Task entfernt." -ForegroundColor Gray
    }

    $aktion1 = New-ScheduledTaskAction `
        -Execute "PowerShell.exe" `
        -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HauptSkript`" -TaskScheduler"

    # Täglich ab 00:00 starten, alle 15 Minuten wiederholen, 24 Stunden lang
    $trigger1 = New-ScheduledTaskTrigger -Daily -At "00:00"
    $trigger1.Repetition = New-Object Microsoft.Management.Infrastructure.CimInstance `
        -ArgumentList "MSFT_TaskRepetitionPattern","Root/Microsoft/Windows/TaskScheduler"
    $trigger1.Repetition.CimInstanceProperties["Interval"].Value    = "PT15M"
    $trigger1.Repetition.CimInstanceProperties["Duration"].Value    = "P1D"
    $trigger1.Repetition.CimInstanceProperties["StopAtDurationEnd"].Value = $false

    $einstellungen1 = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 5) `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable

    $principal1 = New-ScheduledTaskPrincipal `
        -UserId "$env:USERDOMAIN\$env:USERNAME" `
        -LogonType Interactive `
        -RunLevel Highest

    Register-ScheduledTask `
        -TaskName $TaskName1 `
        -Action $aktion1 `
        -Trigger $trigger1 `
        -Settings $einstellungen1 `
        -Principal $principal1 `
        -Description "Heimnetz Monitor – prueft alle 15 Minuten alle 18 Netzwerkgeraete" `
        -Force | Out-Null

    Write-Host "  [OK] Task '$TaskName1' erstellt." -ForegroundColor Green
}
catch {
    Write-Host "  [!!] Fehler bei Task 1: $($_.Exception.Message)" -ForegroundColor Red

    # Fallback: schtasks.exe
    Write-Host "       Versuche Fallback mit schtasks.exe..." -ForegroundColor Gray
    $schtasksArgs = "/Create /TN `"$TaskName1`" /SC MINUTE /MO 15 " +
        "/TR `"PowerShell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \`"$HauptSkript\`" -TaskScheduler`" " +
        "/RU `"$env:USERDOMAIN\$env:USERNAME`" /RL HIGHEST /F"
    & schtasks.exe /Create /TN "$TaskName1" /SC MINUTE /MO 15 `
        /TR "PowerShell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HauptSkript`" -TaskScheduler" `
        /RU "$env:USERDOMAIN\$env:USERNAME" /RL HIGHEST /F 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Task per schtasks.exe erstellt." -ForegroundColor Green
    } else {
        Write-Host "  [!!] Fallback fehlgeschlagen – bitte manuell anlegen." -ForegroundColor Red
    }
}

# ── Task 2: Täglich 08:00 Tagesbericht ───────────────────────────────────────
Write-Host "  Erstelle Task 2: '$TaskName2' (täglich 08:00 Uhr)..." -ForegroundColor Gray

try {
    if (Get-ScheduledTask -TaskName $TaskName2 -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName2 -Confirm:$false
    }

    $aktion2 = New-ScheduledTaskAction `
        -Execute "PowerShell.exe" `
        -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HauptSkript`" -TaskScheduler -Tagesbericht"

    $trigger2 = New-ScheduledTaskTrigger -Daily -At "08:00"

    $einstellungen2 = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable

    $principal2 = New-ScheduledTaskPrincipal `
        -UserId "$env:USERDOMAIN\$env:USERNAME" `
        -LogonType Interactive `
        -RunLevel Highest

    Register-ScheduledTask `
        -TaskName $TaskName2 `
        -Action $aktion2 `
        -Trigger $trigger2 `
        -Settings $einstellungen2 `
        -Principal $principal2 `
        -Description "Heimnetz Monitor – sendet täglich um 08:00 den vollständigen Tagesbericht" `
        -Force | Out-Null

    Write-Host "  [OK] Task '$TaskName2' erstellt." -ForegroundColor Green
}
catch {
    Write-Host "  [!!] Fehler bei Task 2: $($_.Exception.Message)" -ForegroundColor Red
    & schtasks.exe /Create /TN "$TaskName2" /SC DAILY /ST "08:00" `
        /TR "PowerShell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HauptSkript`" -TaskScheduler -Tagesbericht" `
        /RU "$env:USERDOMAIN\$env:USERNAME" /RL HIGHEST /F 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Task per schtasks.exe erstellt." -ForegroundColor Green
    } else {
        Write-Host "  [!!] Fallback fehlgeschlagen." -ForegroundColor Red
    }
}

# ── Zusammenfassung ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Setup abgeschlossen!" -ForegroundColor Green
Write-Host ""
Write-Host "  Geplante Aufgaben:" -ForegroundColor White
Write-Host "  • $TaskName1" -ForegroundColor Gray
Write-Host "    → Alle 15 Minuten, ganztags" -ForegroundColor DarkGray
Write-Host "  • $TaskName2" -ForegroundColor Gray
Write-Host "    → Täglich um 08:00 Uhr mit E-Mail-Bericht" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Jetzt verfügbar:" -ForegroundColor White
Write-Host "  • Manueller Test:    .\Start-NetworkMonitor.ps1" -ForegroundColor Cyan
Write-Host "  • Nur Fehler zeigen: .\Start-NetworkMonitor.ps1 -NurFehler" -ForegroundColor Cyan
Write-Host "  • Ein Gerät prüfen:  .\Start-NetworkMonitor.ps1 -Geraet 'Synology'" -ForegroundColor Cyan
Write-Host ""

# Task-Status anzeigen
Write-Host "  Aktueller Task-Status:" -ForegroundColor White
Get-ScheduledTask -TaskName $TaskName1  -ErrorAction SilentlyContinue |
    Select-Object TaskName, State | Format-Table -AutoSize | Out-String | Write-Host
Get-ScheduledTask -TaskName $TaskName2  -ErrorAction SilentlyContinue |
    Select-Object TaskName, State | Format-Table -AutoSize | Out-String | Write-Host
