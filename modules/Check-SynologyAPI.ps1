function Check-SynologyAPI {
    param(
        [Parameter(Mandatory)][string]$IP,
        [int]$Port                        = 5000,
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][System.Security.SecureString]$PassSecure
    )

    $baseUrl = "http://$IP:$Port/webapi"
    $sid     = $null

    function Invoke-SynoAPI {
        param([string]$Url)
        try {
            return Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 10 -ErrorAction Stop
        }
        catch {
            return $null
        }
    }

    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PassSecure)
        $pass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        $loginUrl = "$baseUrl/auth.cgi?api=SYNO.API.Auth&version=3&method=login&account=$([Uri]::EscapeDataString($User))&passwd=$([Uri]::EscapeDataString($pass))&format=sid"
        $pass = $null

        $loginResp = Invoke-SynoAPI -Url $loginUrl
        if (-not $loginResp -or -not $loginResp.success) {
            $fehler = if ($loginResp.error.code) { "Fehlercode: $($loginResp.error.code)" } else { "Keine Antwort" }
            return [PSCustomObject]@{
                Status       = "FEHLER"
                Volumes      = @()
                SMART_Status = @()
                CPU_Temp     = "n/a"
                Uptime       = "n/a"
                Warnung      = $false
                Info         = "DSM Login fehlgeschlagen – $fehler"
            }
        }

        $sid = $loginResp.data.sid

        # Volumes / Speicher
        $volumeUrl  = "$baseUrl/entry.cgi?api=SYNO.Storage.CGI.Storage&version=1&method=load_info&_sid=$sid"
        $volumeResp = Invoke-SynoAPI -Url $volumeUrl
        $volumes    = @()
        $warnung    = $false

        if ($volumeResp -and $volumeResp.success -and $volumeResp.data.volumes) {
            foreach ($vol in $volumeResp.data.volumes) {
                $groesseGB = [Math]::Round($vol.size.total / 1GB, 1)
                $freiGB    = [Math]::Round($vol.size.avail / 1GB, 1)
                $belegtGB  = $groesseGB - $freiGB
                $prozent   = if ($groesseGB -gt 0) { [Math]::Round(($belegtGB / $groesseGB) * 100, 1) } else { 0 }
                if ($prozent -gt 80) { $warnung = $true }

                $volumes += [PSCustomObject]@{
                    Name        = $vol.id
                    Groesse_GB  = $groesseGB
                    Frei_GB     = $freiGB
                    Prozent     = $prozent
                    RAID_Status = if ($vol.status) { $vol.status } else { "n/a" }
                }
            }
        }

        # SMART
        $smartUrl  = "$baseUrl/entry.cgi?api=SYNO.Storage.CGI.Smart&version=1&method=start&_sid=$sid"
        $smartResp = Invoke-SynoAPI -Url $smartUrl
        $smartList = @()

        if ($smartResp -and $smartResp.success -and $smartResp.data.disks) {
            foreach ($disk in $smartResp.data.disks) {
                $smartList += [PSCustomObject]@{
                    Disk   = if ($disk.name) { $disk.name } else { $disk.id }
                    Status = if ($disk.smart_status) { $disk.smart_status } else { "n/a" }
                    Temp_C = if ($disk.temp -ne $null) { $disk.temp } else { "n/a" }
                }
            }
        }

        # System Info
        $sysUrl  = "$baseUrl/entry.cgi?api=SYNO.Core.System&version=1&method=info&_sid=$sid"
        $sysResp = Invoke-SynoAPI -Url $sysUrl
        $cpuTemp = "n/a"
        $uptime  = "n/a"

        if ($sysResp -and $sysResp.success -and $sysResp.data) {
            $cpuTemp = if ($sysResp.data.cpu_temp -ne $null)  { "$($sysResp.data.cpu_temp)°C" } else { "n/a" }
            $uptime  = if ($sysResp.data.up_time)             { $sysResp.data.up_time }         else { "n/a" }
        }

        $gesamtStatus = if ($warnung) { "WARNUNG" } else { "OK" }
        $infoText     = "DSM erreichbar. $($volumes.Count) Volume(s), $($smartList.Count) Disk(s)."
        if ($warnung) { $infoText += " Mindestens ein Volume > 80% belegt!" }

        return [PSCustomObject]@{
            Status       = $gesamtStatus
            Volumes      = $volumes
            SMART_Status = $smartList
            CPU_Temp     = $cpuTemp
            Uptime       = $uptime
            Warnung      = $warnung
            Info         = $infoText
        }
    }
    catch {
        return [PSCustomObject]@{
            Status       = "FEHLER"
            Volumes      = @()
            SMART_Status = @()
            CPU_Temp     = "n/a"
            Uptime       = "n/a"
            Warnung      = $false
            Info         = "Ausnahme: $($_.Exception.Message)"
        }
    }
    finally {
        if ($sid) {
            $logoutUrl = "$baseUrl/auth.cgi?api=SYNO.API.Auth&method=logout&_sid=$sid"
            Invoke-SynoAPI -Url $logoutUrl | Out-Null
        }
    }
}
