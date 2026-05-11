function Check-PiholeAPI {
    param(
        [string]$IP                                        = "192.168.80.20",
        [System.Security.SecureString]$PassSecure          = $null
    )

    $startzeit = [System.Diagnostics.Stopwatch]::StartNew()

    # Passwort entschlüsseln
    $passwort = ""
    if ($PassSecure) {
        $bstr     = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PassSecure)
        $passwort = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }

    # STUFE 1 – Session-Token holen (Pi-hole v6 POST /api/auth)
    $sid = $null
    try {
        $authBody = @{ password = $passwort } | ConvertTo-Json -Compress
        $authResp = Invoke-RestMethod `
            -Uri     "http://$IP/api/auth" `
            -Method  Post `
            -Body    $authBody `
            -ContentType "application/json" `
            -TimeoutSec 8 `
            -ErrorAction Stop

        $sid = $authResp.session.sid
        if (-not $sid) {
            $startzeit.Stop()
            return [PSCustomObject]@{
                Status        = "FEHLER"
                Queries_Heute = 0
                Blockierrate  = "n/a"
                Aktive_Clients = 0
                Gravity_Liste = 0
                Antwortzeit_ms = $startzeit.ElapsedMilliseconds
                Info          = "Pi-hole Auth fehlgeschlagen – kein SID in Antwort (Passwort falsch?)"
            }
        }
    }
    catch {
        $startzeit.Stop()
        $meldung = $_.Exception.Message
        if ($_ -match "401") { $meldung = "HTTP 401 – Passwort falsch" }
        return [PSCustomObject]@{
            Status         = "FEHLER"
            Queries_Heute  = 0
            Blockierrate   = "n/a"
            Aktive_Clients = 0
            Gravity_Liste  = 0
            Antwortzeit_ms = $startzeit.ElapsedMilliseconds
            Info           = "Pi-hole Auth nicht erreichbar: $meldung"
        }
    }
    finally {
        $passwort = $null
    }

    # STUFE 2 – Stats abrufen (GET /api/stats/summary mit sid-Header)
    $headers = @{ sid = $sid }

    try {
        $summary = Invoke-RestMethod `
            -Uri     "http://$IP/api/stats/summary" `
            -Method  Get `
            -Headers $headers `
            -TimeoutSec 8 `
            -ErrorAction Stop

        $queriesHeute  = 0
        $blockiert     = 0
        $blockierrate  = 0
        $aktiveClients = 0
        $gravityListe  = 0

        if ($summary.queries) {
            $queriesHeute  = [int]$summary.queries.total
            $blockiert     = [int]$summary.queries.blocked
            $aktiveClients = if ($summary.clients.active -ne $null) { [int]$summary.clients.active } else { 0 }
        }
        if ($summary.gravity) {
            $gravityListe = [int]$summary.gravity.domains_being_blocked
        }
        if ($queriesHeute -gt 0) {
            $blockierrate = [Math]::Round(($blockiert / $queriesHeute) * 100, 1)
        }

        $warnText = ""
        $status   = "OK"
        if ($blockierrate -lt 5 -and $queriesHeute -gt 100) {
            $status   = "WARNUNG"
            $warnText = " WARNUNG: Blockierrate nur $blockierrate%!"
        }

        $startzeit.Stop()

        return [PSCustomObject]@{
            Status         = $status
            Queries_Heute  = $queriesHeute
            Blockierrate   = "$blockierrate%"
            Aktive_Clients = $aktiveClients
            Gravity_Liste  = $gravityListe
            Antwortzeit_ms = $startzeit.ElapsedMilliseconds
            Info           = "Pi-hole OK. Queries: $queriesHeute | Blockiert: $blockierrate% | Clients: $aktiveClients | Gravity: $gravityListe Domains.$warnText"
        }
    }
    catch {
        $startzeit.Stop()
        return [PSCustomObject]@{
            Status         = "FEHLER"
            Queries_Heute  = 0
            Blockierrate   = "n/a"
            Aktive_Clients = 0
            Gravity_Liste  = 0
            Antwortzeit_ms = $startzeit.ElapsedMilliseconds
            Info           = "Pi-hole Stats nicht abrufbar: $($_.Exception.Message)"
        }
    }
    finally {
        # Session beenden (Pi-hole v6: DELETE /api/auth)
        if ($sid) {
            try {
                Invoke-RestMethod `
                    -Uri     "http://$IP/api/auth" `
                    -Method  Delete `
                    -Headers @{ sid = $sid } `
                    -TimeoutSec 4 | Out-Null
            } catch {}
        }
    }
}
