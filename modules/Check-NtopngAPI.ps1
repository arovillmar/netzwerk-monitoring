function Check-NtopngAPI {
    param(
        [string]$IP                                      = "192.168.80.20",
        [int]$Port                                       = 3000,
        [string]$User                                    = "admin",
        [System.Security.SecureString]$PassSecure        = $null
    )

    $baseUrl = "http://${IP}:${Port}"
    $headers = @{}

    if ($PassSecure) {
        $bstr     = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PassSecure)
        $passKlar = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${User}:${passKlar}"))
        $headers = @{ Authorization = "Basic $b64" }
        $passKlar = $null
    }

    try {
        # Basis-Info
        $infoResp = Invoke-RestMethod -Uri "$baseUrl/lua/rest/v2/get/ntopng/info.lua" `
            -Headers $headers -Method Get -TimeoutSec 5 -ErrorAction Stop

        $version = if ($infoResp.rsp.version) { $infoResp.rsp.version }
                   elseif ($infoResp.version)  { $infoResp.version }
                   else                        { "n/a" }

        # Externe Flows abfragen (Flows mit mind. einem non-RFC1918-Endpunkt)
        $externeFlows = @()
        try {
            $flowResp = Invoke-RestMethod -Uri "$baseUrl/lua/rest/v2/get/flow/active.lua" `
                -Headers $headers -Method Get -TimeoutSec 8 -ErrorAction Stop

            $flows = if ($flowResp.rsp.data) { $flowResp.rsp.data }
                     elseif ($flowResp.data)  { $flowResp.data }
                     else                     { @() }

            $privatePattern = '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|127\.|169\.254\.)'

            foreach ($flow in $flows) {
                $srcIP = $flow.cli_ip
                $dstIP = $flow.srv_ip
                $srcExt = $srcIP -and $srcIP -notmatch $privatePattern
                $dstExt = $dstIP -and $dstIP -notmatch $privatePattern

                if ($srcExt -or $dstExt) {
                    $extIP  = if ($srcExt) { $srcIP } else { $dstIP }
                    $intIP  = if ($srcExt) { $dstIP } else { $srcIP }
                    $proto  = if ($flow.proto.l4) { $flow.proto.l4 } elseif ($flow.l4proto) { $flow.l4proto } else { "n/a" }
                    $port   = if ($flow.srv_port) { $flow.srv_port } else { 0 }
                    $bytes  = if ($flow.bytes)    { $flow.bytes    } else { 0 }
                    $app    = if ($flow.proto.ndpi) { $flow.proto.ndpi } elseif ($flow.ndpi_proto) { $flow.ndpi_proto } else { "" }

                    $externeFlows += [PSCustomObject]@{
                        ExterneIP = $extIP
                        InternIP  = $intIP
                        Protokoll = $proto
                        Port      = $port
                        App       = $app
                        Bytes     = $bytes
                    }
                }
            }
        }
        catch {}

        $anzahlExtern = $externeFlows.Count
        $status = "OK"
        $info   = "ntopng v$version | $anzahlExtern externe Verbindung$(if ($anzahlExtern -ne 1) { 'en' }) aktiv"

        return [PSCustomObject]@{
            Status       = $status
            Version      = $version
            ExterneFlows = $externeFlows
            AnzahlExtern = $anzahlExtern
            Info         = $info
        }
    }
    catch {
        return [PSCustomObject]@{
            Status       = "FEHLER"
            Version      = "n/a"
            ExterneFlows = @()
            AnzahlExtern = 0
            Info         = "ntopng nicht erreichbar: $($_.Exception.Message)"
        }
    }
}
