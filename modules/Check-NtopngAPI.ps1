function Check-NtopngAPI {
    param(
        [string]$IP   = "192.168.80.20",
        [int]$Port    = 3000
    )

    try {
        $infoUrl = "http://$IP:$Port/lua/rest/v2/get/ntopng/info.lua"

        $response = Invoke-RestMethod -Uri $infoUrl -Method Get -TimeoutSec 5 -ErrorAction Stop

        $aktiveHosts = 0
        $alerts      = 0

        if ($response.rsp) {
            $rsp = $response.rsp
            if ($rsp.hosts)  { $aktiveHosts = $rsp.hosts }
            if ($rsp.alerts) { $alerts      = $rsp.alerts }
        }
        elseif ($response.hosts -ne $null) {
            $aktiveHosts = $response.hosts
            $alerts      = if ($response.alerts) { $response.alerts } else { 0 }
        }

        $version = if ($response.rsp.version) { $response.rsp.version }
                   elseif ($response.version)  { $response.version }
                   else                        { "n/a" }

        return [PSCustomObject]@{
            Status       = "OK"
            Aktive_Hosts = $aktiveHosts
            Alerts       = $alerts
            Info         = "ntopng erreichbar. Version: $version"
        }
    }
    catch {
        return [PSCustomObject]@{
            Status       = "FEHLER"
            Aktive_Hosts = 0
            Alerts       = 0
            Info         = "ntopng API nicht erreichbar: $($_.Exception.Message)"
        }
    }
}
