function Check-Port {
    param(
        [Parameter(Mandatory)][string]$IP,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMs = 2000
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $client = New-Object System.Net.Sockets.TcpClient

    try {
        $verbindung = $client.BeginConnect($IP, $Port, $null, $null)
        $erfolg = $verbindung.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        $stopwatch.Stop()

        if ($erfolg -and $client.Connected) {
            $client.EndConnect($verbindung)
            return [PSCustomObject]@{
                Status  = "OFFEN"
                Port    = $Port
                Zeit_ms = $stopwatch.ElapsedMilliseconds
            }
        }
        else {
            return [PSCustomObject]@{
                Status  = "GESCHLOSSEN"
                Port    = $Port
                Zeit_ms = $stopwatch.ElapsedMilliseconds
            }
        }
    }
    catch {
        $stopwatch.Stop()
        return [PSCustomObject]@{
            Status  = "GESCHLOSSEN"
            Port    = $Port
            Zeit_ms = $stopwatch.ElapsedMilliseconds
        }
    }
    finally {
        $client.Close()
        $client.Dispose()
    }
}
