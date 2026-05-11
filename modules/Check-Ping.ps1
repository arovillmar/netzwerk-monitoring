function Check-Ping {
    param(
        [Parameter(Mandatory)][string]$IP,
        [int]$TimeoutMs = 1000
    )

    try {
        $pinger = New-Object System.Net.NetworkInformation.Ping
        $result  = $pinger.Send($IP, $TimeoutMs)

        if ($result.Status -eq 'Success') {
            return [PSCustomObject]@{
                Status    = "OK"
                Latenz_ms = $result.RoundtripTime
                Info      = "Erreichbar"
            }
        } else {
            return [PSCustomObject]@{
                Status    = "FEHLER"
                Latenz_ms = 9999
                Info      = "Nicht erreichbar: $($result.Status)"
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            Status    = "FEHLER"
            Latenz_ms = 9999
            Info      = "Nicht erreichbar: $($_.Exception.Message)"
        }
    }
}
