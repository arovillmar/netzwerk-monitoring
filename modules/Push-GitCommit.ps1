function Push-GitCommit {
    param(
        [Parameter(Mandatory)][string]$Beschreibung
    )

    $projektPfad = Split-Path -Parent $PSScriptRoot
    $logPfad     = Join-Path $projektPfad "logs"

    function Write-GitLog {
        param([string]$Nachricht, [string]$Farbe = "Gray")
        $zeitstempel = (Get-Date).ToString("HH:mm:ss")
        Write-Host "  [Git] $Nachricht" -ForegroundColor $Farbe
        $logDatei = Join-Path $logPfad "Monitor_$((Get-Date).ToString('yyyyMMdd')).log"
        if (Test-Path $logPfad) {
            "[$zeitstempel] [Git] $Nachricht" | Add-Content $logDatei -Encoding UTF8
        }
    }

    # Einmalig: Git-Repository initialisieren falls noch nicht vorhanden
    $gitOrdner = Join-Path $projektPfad ".git"
    if (-not (Test-Path $gitOrdner)) {
        Write-GitLog "Kein .git-Verzeichnis gefunden – initialisiere Repository..." "Yellow"
        try {
            Push-Location $projektPfad

            & git init 2>&1 | Out-Null
            & git branch -M main 2>&1 | Out-Null

            $repoErstellt = & gh repo create netzwerk-monitoring `
                --private `
                --description "Heimnetz Monitoring System – Armin Rosbach" `
                --source=. `
                --remote=origin 2>&1

            if ($LASTEXITCODE -ne 0) {
                Write-GitLog "gh repo create fehlgeschlagen: $repoErstellt" "Red"
                Pop-Location
                return
            }

            & git add . 2>&1 | Out-Null

            # Sicherheitscheck vor erstem Commit
            $staged = & git diff --cached --name-only 2>&1
            if ($staged -match "credentials.json") {
                Write-GitLog "SICHERHEIT: credentials.json in Staging – Commit abgebrochen!" "Red"
                & git reset HEAD . 2>&1 | Out-Null
                Pop-Location
                return
            }

            & git commit -m "Initial: Netzwerk-Monitoring System v1.0" 2>&1 | Out-Null
            & git push -u origin main 2>&1 | Out-Null

            Write-GitLog "Repository erstellt und initialer Push durchgeführt." "Green"
            Pop-Location
        }
        catch {
            Write-GitLog "Fehler beim Repository-Setup: $($_.Exception.Message)" "Red"
            Pop-Location
        }
        return
    }

    # Normaler Push-Ablauf
    Push-Location $projektPfad
    try {
        # Änderungen prüfen
        $gitStatus = & git status --porcelain 2>&1
        if (-not $gitStatus) {
            Write-GitLog "Keine Änderungen vorhanden – kein Commit nötig." "DarkGray"
            Pop-Location
            return
        }

        # Sicherheitscheck: credentials.json niemals pushen
        $staged = & git diff --cached --name-only 2>&1
        $unstaged = & git status --porcelain 2>&1
        if ($staged -match "credentials\.json" -or ($unstaged | Where-Object { $_ -match "credentials\.json" -and $_ -notmatch "^\?\?" })) {
            Write-GitLog "SICHERHEIT: credentials.json erkannt – Commit sofort abgebrochen!" "Red"
            Write-Host ""
            Write-Host "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
            Write-Host "  !! WARNUNG: credentials.json darf NIEMALS auf    !!" -ForegroundColor Red
            Write-Host "  !! GitHub gepusht werden! Prüfe .gitignore!      !!" -ForegroundColor Red
            Write-Host "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
            Pop-Location
            return
        }

        # Staging (gitignore schützt sensitive Dateien)
        & git add . 2>&1 | Out-Null

        # Nochmal nach dem Staging prüfen
        $stagedNach = & git diff --cached --name-only 2>&1
        if ($stagedNach -match "credentials\.json") {
            Write-GitLog "SICHERHEIT: credentials.json in Staging nach git add – sofort zurückgesetzt!" "Red"
            & git reset HEAD . 2>&1 | Out-Null
            Pop-Location
            return
        }

        if (-not $stagedNach) {
            Write-GitLog "Keine stagbaren Änderungen (alles in .gitignore)." "DarkGray"
            Pop-Location
            return
        }

        # Commit
        $commitNachricht = "[$((Get-Date).ToString('yyyy-MM-dd HH:mm'))] $Beschreibung"
        & git commit -m $commitNachricht 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            Write-GitLog "Commit fehlgeschlagen." "Red"
            Pop-Location
            return
        }

        # Push
        & git push origin main 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-GitLog "GitHub Push erfolgreich: $Beschreibung" "Green"
        }
        else {
            Write-GitLog "Push fehlgeschlagen – bitte manuell prüfen." "Red"
        }
    }
    catch {
        Write-GitLog "Ausnahme: $($_.Exception.Message)" "Red"
    }
    finally {
        Pop-Location
    }
}
