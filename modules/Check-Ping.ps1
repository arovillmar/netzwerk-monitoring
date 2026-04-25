function Check-Ping {
    param(
        [Parameter(Mandatory)][string]$IP,
        [int]$TimeoutMs = 1000
    )

    try {
        $timeoutSec = [Math]::Max(1, [Math]::Ceiling($TimeoutMs / 1000))
        $ping = Test-Connection -ComputerName $IP -Count 1 -TimeoutSeconds $timeoutSec -ErrorAction Stop

        $latenz = if ($ping.Latency) { $ping.Latency } else { 0 }

        return [PSCustomObject]@{
            Status    = "OK"
            Latenz_ms = $latenz
            Info      = "Erreichbar"
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
