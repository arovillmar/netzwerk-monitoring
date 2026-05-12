function Check-Powerline {
    param(
        [Parameter(Mandatory)][string]$IP,
        [string]$FritzBoxIP = "192.168.80.1"
    )

    $pingOK         = $false
    $httpErreichbar = $false

    # Ping
    try {
        $pingOK = (New-Object System.Net.NetworkInformation.Ping).Send($IP, 1000).Status -eq 'Success'
        if (-not $pingOK) { throw "Kein Ping" }
    }
    catch {
        $pingOK = $false
    }

    # HTTP Port 80
    try {
        $client     = New-Object System.Net.Sockets.TcpClient
        $verbindung = $client.BeginConnect($IP, 80, $null, $null)
        $erfolg     = $verbindung.AsyncWaitHandle.WaitOne(2000, $false)
        if ($erfolg -and $client.Connected) {
            $client.EndConnect($verbindung)
            $httpErreichbar = $true
        }
        $client.Close()
        $client.Dispose()
    }
    catch {
        $httpErreichbar = $false
    }

    if (-not $pingOK) {
        return [PSCustomObject]@{
            Status          = "FEHLER"
            Ping_OK         = $false
            HTTP_Erreichbar = $false
            Info            = "Powerline Adapter $IP nicht erreichbar (kein Ping)"
        }
    }

    $gesamtStatus = if ($httpErreichbar) { "OK" } else { "WARNUNG" }
    $infoText     = "Powerline $IP – Ping: OK | HTTP Port 80: $(if ($httpErreichbar) { 'erreichbar' } else { 'nicht erreichbar' })"

    return [PSCustomObject]@{
        Status          = $gesamtStatus
        Ping_OK         = $pingOK
        HTTP_Erreichbar = $httpErreichbar
        Info            = $infoText
    }
}
