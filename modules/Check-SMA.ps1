function Check-SMA {
    param(
        [string]$IP            = "192.168.80.49",
        [int]$SpeedwirePort    = 9522
    )

    $pingOK        = $false
    $speedwireAktiv = $false

    try {
        $pingResult = Test-Connection -ComputerName $IP -Count 1 -TimeoutSeconds 1 -ErrorAction Stop
        $pingOK = $true
    }
    catch {
        $pingOK = $false
    }

    try {
        $client     = New-Object System.Net.Sockets.TcpClient
        $verbindung = $client.BeginConnect($IP, $SpeedwirePort, $null, $null)
        $erfolg     = $verbindung.AsyncWaitHandle.WaitOne(2000, $false)

        if ($erfolg -and $client.Connected) {
            $client.EndConnect($verbindung)
            $speedwireAktiv = $true
        }
        $client.Close()
        $client.Dispose()
    }
    catch {
        $speedwireAktiv = $false
    }

    if (-not $pingOK -and -not $speedwireAktiv) {
        return [PSCustomObject]@{
            Status          = "FEHLER"
            Ping_OK         = $false
            Speedwire_Aktiv = $false
            Info            = "ALARM: SMA Home Manager nicht erreichbar – Photovoltaik-Anlage moeglicherweise ausgefallen!"
        }
    }

    if ($pingOK -and -not $speedwireAktiv) {
        return [PSCustomObject]@{
            Status          = "FEHLER"
            Ping_OK         = $true
            Speedwire_Aktiv = $false
            Info            = "ALARM: SMA Home Manager nicht erreichbar – Photovoltaik-Anlage moeglicherweise ausgefallen!"
        }
    }

    return [PSCustomObject]@{
        Status          = "OK"
        Ping_OK         = $pingOK
        Speedwire_Aktiv = $speedwireAktiv
        Info            = "SMA Home Manager erreichbar. Speedwire Port $SpeedwirePort aktiv."
    }
}
