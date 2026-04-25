function Check-Docker {
    param(
        [string]$IP      = "192.168.80.206",
        [int]$SSHPort    = 822,
        [string]$SSHUser = "Armin"
    )

    $composePfad = "/volume2/docker/maennerballet/docker-compose.yml"

    function Invoke-SSH {
        param([string]$Befehl)
        $args = @(
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=no",
            "-p", $SSHPort,
            "$SSHUser@$IP",
            $Befehl
        )
        $ausgabe  = & ssh.exe @args 2>&1
        $exitCode = $LASTEXITCODE
        return [PSCustomObject]@{ Ausgabe = $ausgabe; ExitCode = $exitCode }
    }

    try {
        $psBefehl  = "sudo docker compose -f $composePfad ps --format json 2>/dev/null || sudo docker compose -f $composePfad ps 2>&1"
        $psResult  = Invoke-SSH -Befehl $psBefehl

        if ($psResult.ExitCode -ne 0) {
            return [PSCustomObject]@{
                Status           = "FEHLER"
                Container_Name   = "n/a"
                Container_Status = "n/a"
                Container_Uptime = "n/a"
                Port_Mapping     = "n/a"
                Letzte_Logs      = @()
                Info             = "Docker-Abfrage fehlgeschlagen (Exit $($psResult.ExitCode)): $($psResult.Ausgabe -join ' ')"
            }
        }

        $ausgabeText = $psResult.Ausgabe -join "`n"

        $containerName   = "n/a"
        $containerStatus = "n/a"
        $containerUptime = "n/a"
        $portMapping     = "n/a"

        try {
            $json = $psResult.Ausgabe | Where-Object { $_ -match "^\{" } | ConvertFrom-Json -ErrorAction Stop | Select-Object -First 1
            if ($json) {
                $containerName   = if ($json.Name)    { $json.Name }    else { if ($json.Service) { $json.Service } else { "n/a" } }
                $containerStatus = if ($json.State)   { $json.State }   else { if ($json.Status)  { $json.Status }  else { "n/a" } }
                $containerUptime = if ($json.RunningFor) { $json.RunningFor } else { "n/a" }
                $portMapping     = if ($json.Publishers) {
                    ($json.Publishers | ForEach-Object { "$($_.PublishedPort):$($_.TargetPort)" }) -join ", "
                } else { "n/a" }
            }
        }
        catch {
            # Fallback: Text-Parsing wenn kein JSON
            $zeilen = $psResult.Ausgabe | Where-Object { $_ -notmatch "^NAME" -and $_ -match "\S" }
            if ($zeilen.Count -gt 0) {
                $teile           = $zeilen[0] -split "\s{2,}"
                $containerName   = if ($teile.Count -ge 1) { $teile[0].Trim() } else { "n/a" }
                $containerStatus = if ($ausgabeText -match "Up")      { "running" }
                                   elseif ($ausgabeText -match "Exit") { "exited"  }
                                   else                                { "unknown" }
                $portMapping     = if ($teile.Count -ge 4) { $teile[3].Trim() } else { "n/a" }
            }
        }

        # Letzte 5 Log-Zeilen
        $logBefehl = "sudo docker compose -f $composePfad logs --tail=5 app 2>&1"
        $logResult = Invoke-SSH -Befehl $logBefehl
        $letzteLogs = if ($logResult.ExitCode -eq 0) {
            $logResult.Ausgabe | Where-Object { $_ -match "\S" } | Select-Object -Last 5
        } else { @("Log-Abfrage fehlgeschlagen") }

        $gesamtStatus = switch -Regex ($containerStatus) {
            "running|up"       { "OK"     }
            "restarting"       { "WARNUNG" }
            default            { "FEHLER"  }
        }

        return [PSCustomObject]@{
            Status           = $gesamtStatus
            Container_Name   = $containerName
            Container_Status = $containerStatus
            Container_Uptime = $containerUptime
            Port_Mapping     = $portMapping
            Letzte_Logs      = $letzteLogs
            Info             = "Docker-Abfrage erfolgreich. Container: $containerName ($containerStatus)"
        }
    }
    catch {
        return [PSCustomObject]@{
            Status           = "FEHLER"
            Container_Name   = "n/a"
            Container_Status = "n/a"
            Container_Uptime = "n/a"
            Port_Mapping     = "n/a"
            Letzte_Logs      = @()
            Info             = "Ausnahme: $($_.Exception.Message)"
        }
    }
}
