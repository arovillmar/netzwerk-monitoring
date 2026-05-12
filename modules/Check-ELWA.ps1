function Check-ELWA {
    param(
        [string]$IP      = "192.168.80.122",
        [int]$TempMax    = 75
    )

    $startzeit = [System.Diagnostics.Stopwatch]::StartNew()

    # Ping
    try {
        if ((New-Object System.Net.NetworkInformation.Ping).Send($IP, 2000).Status -ne 'Success') { throw "Kein Ping" }
    }
    catch {
        $startzeit.Stop()
        return [PSCustomObject]@{
            Status        = "FEHLER"
            Temperatur    = "n/a"
            Leistung_W    = "n/a"
            BlockActive   = $false
            BoostActive   = $false
            CtrlState     = "n/a"
            FwVersion     = "n/a"
            CloudState    = "n/a"
            Warnung       = $false
            Antwortzeit_ms = $startzeit.ElapsedMilliseconds
            Info          = "AC ELWA-E nicht erreichbar (kein Ping auf $IP)"
        }
    }

    # API-Abfrage – korrekter Endpunkt: /data.jsn (NICHT /mypv_act.jsn!)
    try {
        $response = Invoke-RestMethod `
            -Uri        "http://$IP/data.jsn" `
            -Method     Get `
            -TimeoutSec 5 `
            -ErrorAction Stop

        # temp1 ist in 1/10 °C → durch 10 dividieren!
        $tempRoh    = if ($response.temp1  -ne $null) { [double]$response.temp1  } else { $null }
        $temperatur = if ($tempRoh  -ne $null) { [Math]::Round($tempRoh / 10.0, 1) } else { $null }

        $leistung     = if ($response.power       -ne $null) { [int]$response.power       } else { $null }
        $blockActive  = if ($response.blockactive -ne $null) { [int]$response.blockactive -eq 1 } else { $false }
        $boostActive  = if ($response.boostactive -ne $null) { [int]$response.boostactive -eq 1 } else { $false }
        $ctrlState    = if ($response.ctrlstate   -ne $null) { "$($response.ctrlstate)"   } else { "n/a" }
        $fwVersion    = if ($response.fwversion   -ne $null) { "$($response.fwversion)"   } else { "n/a" }
        $cloudState   = if ($response.cloudstate  -ne $null) { [int]$response.cloudstate  } else { $null }

        # Status-Bewertung
        $warnung  = $false
        $warnText = ""

        if ($temperatur -ne $null -and $temperatur -gt $TempMax) {
            $warnung  = $true
            $warnText = " WARNUNG: Überhitzung $temperatur°C (Limit: $TempMax°C)!"
        }

        $gesamtStatus = if ($warnung) { "WARNUNG" } else { "OK" }

        $tempAnzeige    = if ($temperatur -ne $null) { "$temperatur°C" }    else { "n/a" }
        $leistungAnzeige = if ($leistung -ne $null)  { "$leistung W"  }    else { "n/a" }

        $infoTeile = @("Temp: $tempAnzeige", "Leistung: $leistungAnzeige")
        $infoTeile += "Ctrl: $ctrlState"
        if ($blockActive)  { $infoTeile += "PV-Block: aktiv (kein Überschuss)" }
        if ($boostActive)  { $infoTeile += "Boost: AN" }
        if ($cloudState -eq 4) { $infoTeile += "Cloud: verbunden" }
        if ($warnText)     { $infoTeile += $warnText }

        $startzeit.Stop()

        return [PSCustomObject]@{
            Status         = $gesamtStatus
            Temperatur     = $tempAnzeige
            Leistung_W     = $leistungAnzeige
            BlockActive    = $blockActive
            BoostActive    = $boostActive
            CtrlState      = $ctrlState
            FwVersion      = $fwVersion
            CloudState     = $cloudState
            Warnung        = $warnung
            Antwortzeit_ms = $startzeit.ElapsedMilliseconds
            Info           = $infoTeile -join " | "
        }
    }
    catch {
        $startzeit.Stop()
        return [PSCustomObject]@{
            Status         = "FEHLER"
            Temperatur     = "n/a"
            Leistung_W     = "n/a"
            BlockActive    = $false
            BoostActive    = $false
            CtrlState      = "n/a"
            FwVersion      = "n/a"
            CloudState     = "n/a"
            Warnung        = $false
            Antwortzeit_ms = $startzeit.ElapsedMilliseconds
            Info           = "ELWA-E API nicht erreichbar: $($_.Exception.Message)"
        }
    }
}
