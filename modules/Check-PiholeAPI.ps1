function Check-PiholeAPI {
    param(
        [string]$IP = "192.168.80.20"
    )

    try {
        $summaryUrl   = "http://$IP/api/stats/summary"
        $upstreamsUrl = "http://$IP/api/stats/upstreams"

        $summary = Invoke-RestMethod -Uri $summaryUrl -Method Get -TimeoutSec 5 -ErrorAction Stop

        $queriesHeute = 0
        $blockierrate = 0
        $gravityListe = 0
        $piholeAktiv  = $false

        if ($summary.queries) {
            $queriesHeute = $summary.queries.total
            $blockiert    = $summary.queries.blocked
            if ($queriesHeute -gt 0) {
                $blockierrate = [Math]::Round(($blockiert / $queriesHeute) * 100, 1)
            }
        }
        elseif ($summary.dns_queries_today -ne $null) {
            $queriesHeute = $summary.dns_queries_today
            $blockierrate = $summary.ads_percentage_today
        }

        if ($summary.gravity) {
            $gravityListe = $summary.gravity.domains_being_blocked
        }
        elseif ($summary.domains_being_blocked -ne $null) {
            $gravityListe = $summary.domains_being_blocked
        }

        if ($summary.status -ne $null) {
            $piholeAktiv = ($summary.status -eq "enabled")
        }
        else {
            $piholeAktiv = $true
        }

        try {
            $upstreams = Invoke-RestMethod -Uri $upstreamsUrl -Method Get -TimeoutSec 5 -ErrorAction Stop
            $upstreamInfo = if ($upstreams.upstreams) { "$($upstreams.upstreams.Count) Upstream(s) aktiv" } else { "Upstream-Info n/a" }
        }
        catch {
            $upstreamInfo = "Upstream-Abfrage fehlgeschlagen"
        }

        return [PSCustomObject]@{
            Status        = "OK"
            Queries_Heute = $queriesHeute
            Blockierrate  = "$blockierrate%"
            Gravity_Liste = $gravityListe
            PiHole_Aktiv  = $piholeAktiv
            Info          = "Pi-hole erreichbar. $upstreamInfo"
        }
    }
    catch {
        return [PSCustomObject]@{
            Status        = "FEHLER"
            Queries_Heute = 0
            Blockierrate  = "n/a"
            Gravity_Liste = 0
            PiHole_Aktiv  = $false
            Info          = "Pi-hole API nicht erreichbar: $($_.Exception.Message)"
        }
    }
}
