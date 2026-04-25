function Check-ELWA {
    param(
        [string]$IP      = "192.168.80.122",
        [int]$TempMax    = 75
    )

    $pingOK = $false

    try {
        Test-Connection -ComputerName $IP -Count 1 -TimeoutSeconds 1 -ErrorAction Stop | Out-Null
        $pingOK = $true
    }
    catch {
        $pingOK = $false
    }

    if (-not $pingOK) {
        return [PSCustomObject]@{
            Status        = "FEHLER"
            Temperatur    = "n/a"
            Leistung_W    = "n/a"
            Geraet_Status = "n/a"
            Warnung       = $false
            Info          = "AC ELWA-E nicht erreichbar (kein Ping auf $IP)"
        }
    }

    try {
        $apiUrl  = "http://$IP/mypv_act.jsn"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 5 -ErrorAction Stop

        $temperatur   = if ($response.temp1  -ne $null) { [double]$response.temp1  } else { $null }
        $leistung     = if ($response.power  -ne $null) { [int]$response.power     } else { $null }
        $geraetStatus = if ($response.status -ne $null) { $response.status         } else { "n/a" }

        $warnung  = $false
        $warnText = ""

        if ($temperatur -ne $null -and $temperatur -gt $TempMax) {
            $warnung  = $true
            $warnText = " WARNUNG: Temperatur $temperatur°C ueberschreitet Limit von $TempMax°C!"
        }

        $gesamtStatus = if ($warnung) { "WARNUNG" } else { "OK" }

        $tempAnzeige    = if ($temperatur -ne $null) { "$temperatur°C" }  else { "n/a" }
        $leistungAnzeige = if ($leistung -ne $null)  { "$leistung W" }    else { "n/a" }
        $infoText       = "ELWA-E erreichbar. Temperatur: $tempAnzeige | Leistung: $leistungAnzeige | Status: $geraetStatus.$warnText"

        return [PSCustomObject]@{
            Status        = $gesamtStatus
            Temperatur    = $tempAnzeige
            Leistung_W    = $leistungAnzeige
            Geraet_Status = $geraetStatus
            Warnung       = $warnung
            Info          = $infoText
        }
    }
    catch {
        return [PSCustomObject]@{
            Status        = "FEHLER"
            Temperatur    = "n/a"
            Leistung_W    = "n/a"
            Geraet_Status = "n/a"
            Warnung       = $false
            Info          = "ELWA-E API nicht erreichbar: $($_.Exception.Message)"
        }
    }
}
