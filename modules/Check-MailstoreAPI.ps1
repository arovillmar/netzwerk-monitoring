function Check-MailstoreAPI {
    param(
        [string]$IP                                       = "192.168.80.120",
        [int]$Port                                        = 8474,
        [string]$User                                     = "admin",
        [Parameter(Mandatory)][System.Security.SecureString]$PassSecure
    )

    $baseUrl = "http://$IP:$Port/api/invoke"

    function Invoke-MailstoreAPI {
        param([string]$Methode, [System.Management.Automation.PSCredential]$Cred)
        try {
            $url = "$baseUrl/$Methode"
            return Invoke-RestMethod -Uri $url -Method Get -Credential $Cred -TimeoutSec 10 -ErrorAction Stop
        }
        catch {
            return $null
        }
    }

    try {
        $cred = New-Object System.Management.Automation.PSCredential($User, $PassSecure)

        # Job-Ergebnisse abrufen
        $jobResp = Invoke-MailstoreAPI -Methode "GetJobResults" -Cred $cred

        $jobs           = @()
        $kritischeJobs  = @()
        $archivGesamt   = 0
        $neuArchiviert  = 0

        if ($jobResp -and $jobResp.result) {
            foreach ($job in $jobResp.result) {
                $jobName     = if ($job.name)         { $job.name }         else { "Unbekannt" }
                $jobStatus   = if ($job.result)       { $job.result }       else { "n/a" }
                $letzteAusfuehrung = if ($job.timeCompleted) { $job.timeCompleted } else { "n/a" }
                $fehler      = if ($job.numErrors -ne $null)   { $job.numErrors }   else { 0 }
                $warnungen   = if ($job.numWarnings -ne $null) { $job.numWarnings } else { 0 }

                $jobObj = [PSCustomObject]@{
                    Name               = $jobName
                    Status             = $jobStatus
                    Letzte_Ausfuehrung = $letzteAusfuehrung
                    Fehler             = $fehler
                    Warnungen          = $warnungen
                }
                $jobs += $jobObj

                if ($fehler -gt 0 -or $jobStatus -eq "failed") {
                    $kritischeJobs += $jobObj
                }
            }
        }

        # Archiv-Statistiken
        $msgResp = Invoke-MailstoreAPI -Methode "GetMessages" -Cred $cred
        if ($msgResp -and $msgResp.result) {
            $archivGesamt  = if ($msgResp.result.count -ne $null)    { $msgResp.result.count }    else { 0 }
            $neuArchiviert = if ($msgResp.result.countToday -ne $null) { $msgResp.result.countToday } else { 0 }
        }

        # Bekannte Gmail-Problem hervorheben
        $gmailJob = $jobs | Where-Object { $_.Name -match "andrearosbach27@gmail" }
        if ($gmailJob -and $gmailJob.Fehler -gt 0) {
            if ($kritischeJobs -notcontains $gmailJob) {
                $kritischeJobs += $gmailJob
            }
        }

        $gesamtStatus = if ($kritischeJobs.Count -gt 0) { "WARNUNG" }
                        elseif (-not $jobResp)           { "FEHLER"  }
                        else                             { "OK"      }

        $infoText = "Mailstore erreichbar. $($jobs.Count) Job(s) abgerufen."
        if ($kritischeJobs.Count -gt 0) {
            $infoText += " $($kritischeJobs.Count) Job(s) mit Fehlern!"
        }
        if ($archivGesamt -gt 0) {
            $infoText += " Archiv: $archivGesamt Nachrichten."
        }

        return [PSCustomObject]@{
            Status           = $gesamtStatus
            Jobs             = $jobs
            Archiv_Gesamt    = $archivGesamt
            Neu_Archiviert   = $neuArchiviert
            Kritische_Jobs   = $kritischeJobs
            Info             = $infoText
        }
    }
    catch {
        return [PSCustomObject]@{
            Status           = "FEHLER"
            Jobs             = @()
            Archiv_Gesamt    = 0
            Neu_Archiviert   = 0
            Kritische_Jobs   = @()
            Info             = "Mailstore API nicht erreichbar: $($_.Exception.Message)"
        }
    }
}
