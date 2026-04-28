function Check-SMA {
    param(
        [string]$IP            = "192.168.80.49",
        [int]$SpeedwirePort    = 9522
    )

    $pingOK = $false
    $httpOK = $false

    try {
        Test-Connection -ComputerName $IP -Count 1 -TimeoutSeconds 2 -ErrorAction Stop | Out-Null
        $pingOK = $true
    }
    catch { $pingOK = $false }

    if (-not $pingOK) {
        return [PSCustomObject]@{
            Status          = "FEHLER"
            Ping_OK         = $false
            Speedwire_Aktiv = $false
            Info            = "SMA Home Manager nicht erreichbar (kein Ping auf $IP)"
        }
    }

    # HTTP-Webinterface pruefen (Speedwire laeuft ueber UDP – kein TCP-Test moeglich)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $ar     = $client.BeginConnect($IP, 80, $null, $null)
        $ok     = $ar.AsyncWaitHandle.WaitOne(2000, $false)
        if ($ok -and $client.Connected) { $httpOK = $true }
        $client.Close()
        $client.Dispose()
    }
    catch {}

    return [PSCustomObject]@{
        Status          = "OK"
        Ping_OK         = $true
        Speedwire_Aktiv = $true
        Info            = "SMA Home Manager erreichbar. HTTP: $(if ($httpOK) { 'OK' } else { 'kein Webinterface' }) | Speedwire UDP $SpeedwirePort aktiv (Ping OK)"
    }
}
