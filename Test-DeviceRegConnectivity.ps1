<# 
 
.SYNOPSIS
    Test-HybridDevicesInternetConnectivity V3.2 PowerShell script.

.DESCRIPTION
    Test-HybridDevicesInternetConnectivity is a PowerShell script that helps to test the Internet connectivity to the following Microsoft resources under the system context to validate the connection status between the device that needs to be connected to Azure AD as hybrid Azure AD joined device and Microsoft resources that are used during device registration process:

    https://login.microsoftonline.com
    https://device.login.microsoftonline.com
    https://enterpriseregistration.windows.net


.AUTHOR:
    Mohammad Zmaili

.EXAMPLE
    .\Test-DeviceRegConnectivity
    
#>

Function RunPScript([String] $PSScript){
    $GUID=[guid]::NewGuid().Guid
    $Job = Register-ScheduledJob -Name $GUID -ScheduledJobOption (New-ScheduledJobOption -RunElevated) -ScriptBlock ([ScriptBlock]::Create($PSScript)) -ArgumentList ($PSScript) -ErrorAction Stop
    $Task = Register-ScheduledTask -TaskName $GUID -Action (New-ScheduledTaskAction -Execute $Job.PSExecutionPath -Argument $Job.PSExecutionArgs) -Principal (New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest) -ErrorAction Stop
    $Task | Start-ScheduledTask -AsJob -ErrorAction Stop | Wait-Job | Remove-Job -Force -Confirm:$False
    While (($Task | Get-ScheduledTaskInfo).LastTaskResult -eq 267009) {Start-Sleep -Milliseconds 150}
    $Job1 = Get-Job -Name $GUID -ErrorAction SilentlyContinue | Wait-Job
    $Job1 | Receive-Job -Wait -AutoRemoveJob 
    Unregister-ScheduledJob -Id $Job.Id -Force -Confirm:$False
    Unregister-ScheduledTask -TaskName $GUID -Confirm:$false
}

Function checkProxy{
    # Check Proxy settings
    Write-Host "Checking winHTTP proxy settings..." -ForegroundColor Yellow
    Write-Log -Message "Checking winHTTP proxy settings..."
    $global:ProxyServer="NoProxy"
    $winHTTP = netsh winhttp show proxy
    $Proxy = $winHTTP | Select-String server
    $global:ProxyServer=$Proxy.ToString().TrimStart("Proxy Server(s) :  ")
    $global:Bypass = $winHTTP | Select-String Bypass
    $global:Bypass=$global:Bypass.ToString().TrimStart("Bypass List     :  ")

    if ($global:ProxyServer -eq "Direct access (no proxy server)."){
        $global:ProxyServer="NoProxy"
        Write-Host "      Access Type : DIRECT"
        Write-Log -Message "      Access Type : DIRECT"
    }

    if ( ($global:ProxyServer -ne "NoProxy") -and (-not($global:ProxyServer.StartsWith("http://")))){
        Write-Host "      Access Type : PROXY"
        Write-Log -Message "      Access Type : PROXY"
        Write-Host "Proxy Server List :" $global:ProxyServer
        Write-Log -Message "Proxy Server List : $global:ProxyServer"
        Write-Host "Proxy Bypass List :" $global:Bypass
        Write-Log -Message "Proxy Bypass List : $global:Bypass"
        $global:ProxyServer = "http://" + $global:ProxyServer
    }

    $global:login= $global:Bypass.Contains("*.microsoftonline.com") -or $global:Bypass.Contains("login.microsoftonline.com")

    $global:device= $global:Bypass.Contains("*.microsoftonline.com") -or $global:Bypass.Contains("*.login.microsoftonline.com") -or $global:Bypass.Contains("device.login.microsoftonline.com")

    $global:enterprise= $global:Bypass.Contains("*.windows.net") -or $global:Bypass.Contains("enterpriseregistration.windows.net")

    #CheckwinInet proxy
    Write-Host ''
    Write-Host "Checking winInet proxy settings..." -ForegroundColor Yellow
    Write-Log -Message "Checking winInet proxy settings..."
    $winInet=RunPScript -PSScript "Get-ItemProperty -Path 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings'"
    if($winInet.ProxyEnable){Write-Host "    Proxy Enabled : Yes"; Write-Log -Message "    Proxy Enabled : Yes"}else{Write-Host "    Proxy Enabled : No";Write-Log -Message "    Proxy Enabled : No"}
    $winInetProxy="Proxy Server List : "+$winInet.ProxyServer
    Write-Host $winInetProxy
    Write-Log -Message $winInetProxy
    $winInetBypass="Proxy Bypass List : "+$winInet.ProxyOverride
    Write-Host $winInetBypass
    Write-Log -Message $winInetBypass
    $winInetAutoConfigURL="    AutoConfigURL : "+$winInet.AutoConfigURL
    Write-Host $winInetAutoConfigURL
    Write-Log -Message $winInetAutoConfigURL

    return $global:ProxyServer
}

Function Write-Log{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$False)]
        [ValidateSet("INFO","WARN","ERROR","FATAL","DEBUG")]
        [String] $Level = "INFO",

        [Parameter(Mandatory=$True)]
        [string] $Message,

        [Parameter(Mandatory=$False)]
        [string] $logfile = "Test-DeviceRegConnectivity.log"
    )
    if ($Message -eq " "){
        Add-Content $logfile -Value " " -ErrorAction SilentlyContinue
    }else{
        #$Date= Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $Date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff')
        Add-Content $logfile -Value "[$date] [$Level] $Message" -ErrorAction SilentlyContinue
    }
}

Function Test-DevRegConnectivity{
    $ProxyTestFailed=$false
    Write-Host
    Write-Host "Testing Internet Connectivity..." -ForegroundColor Yellow
    Write-Log -Message "Testing Internet Connectivity..."
    $ErrorActionPreference= 'silentlycontinue'
    $global:TestFailed=$false

    $global:ProxyServer = checkProxy
    Write-Host
    Write-Host "Testing Device Registration Endpoints..." -ForegroundColor Yellow
    Write-Log -Message "Testing Device Registration Endpoints..."
    if ($global:ProxyServer -ne "NoProxy"){
        Write-Host "Testing connection via winHTTP proxy..." -ForegroundColor Yellow
        Write-Log -Message "Testing connection via winHTTP proxy..."
        if ($global:login){
            $PSScript = "(Invoke-WebRequest -uri 'https://login.microsoftonline.com/common/oauth2' -UseBasicParsing).StatusCode"
            $TestResult = RunPScript -PSScript $PSScript
        }else{
            $PSScript = "(Invoke-WebRequest -uri 'https://login.microsoftonline.com/common/oauth2' -UseBasicParsing -Proxy $global:ProxyServer).StatusCode"
            $TestResult = RunPScript -PSScript $PSScript
        }
        if ($TestResult -eq 200){
            Write-Host ''
            Write-Host "Connection to login.microsoftonline.com .............. Succeeded." -ForegroundColor Green
            Write-Log -Message "Connection to login.microsoftonline.com .............. Succeeded."
        }else{
            $ProxyTestFailed=$true
        }

        if ($global:device){
            $PSScript = "(Invoke-WebRequest -uri 'https://device.login.microsoftonline.com/common/oauth2' -UseBasicParsing).StatusCode"
            $TestResult = RunPScript -PSScript $PSScript
        }else{
            $PSScript = "(Invoke-WebRequest -uri 'https://device.login.microsoftonline.com/common/oauth2' -UseBasicParsing -Proxy $global:ProxyServer).StatusCode"
            $TestResult = RunPScript -PSScript $PSScript
        }
        if ($TestResult -eq 200){
            Write-Host "Connection to device.login.microsoftonline.com ......  Succeeded." -ForegroundColor Green
            Write-Log -Message "Connection to device.login.microsoftonline.com ......  Succeeded."
        }else{
            $ProxyTestFailed=$true
        }

        if ($global:enterprise){
            $PSScript = "(Invoke-WebRequest -uri 'https://enterpriseregistration.windows.net/microsoft.com/discover?api-version=1.7' -UseBasicParsing -Headers @{'Accept' = 'application/json'; 'ocp-adrs-client-name' = 'dsreg'; 'ocp-adrs-client-version' = '10'}).StatusCode"
            $TestResult = RunPScript -PSScript $PSScript
        }else{
            $PSScript = "(Invoke-WebRequest -uri 'https://enterpriseregistration.windows.net/microsoft.com/discover?api-version=1.7' -UseBasicParsing -Proxy $global:ProxyServer -Headers @{'Accept' = 'application/json'; 'ocp-adrs-client-name' = 'dsreg'; 'ocp-adrs-client-version' = '10'}).StatusCode"
            $TestResult = RunPScript -PSScript $PSScript
        }
        if ($TestResult -eq 200){
            Write-Host "Connection to enterpriseregistration.windows.net ..... Succeeded." -ForegroundColor Green
            Write-Log -Message "Connection to enterpriseregistration.windows.net ..... Succeeded."
        }else{
            $ProxyTestFailed=$true
        }
    }
    
    if (($global:ProxyServer -eq "NoProxy") -or ($ProxyTestFailed -eq $true)){
        if($ProxyTestFailed -eq $true){
            Write-host "Connection failed via winHTTP, trying winInet..."
            Write-Log -Message "Connection failed via winHTTP, trying winInet..." -Level WARN
        }else{
            Write-host "Testing connection via winInet..." -ForegroundColor Yellow
            Write-Log -Message "Testing connection via winInet..."
        }
        $PSScript = "(Invoke-WebRequest -uri 'https://login.microsoftonline.com/common/oauth2' -UseBasicParsing).StatusCode"
        $TestResult = RunPScript -PSScript $PSScript
        if ($TestResult -eq 200){
            Write-Host ''
            Write-Host "Connection to login.microsoftonline.com .............. Succeeded." -ForegroundColor Green
            Write-Log -Message "Connection to login.microsoftonline.com .............. Succeeded."
        }else{
            $global:TestFailed=$true
            Write-Host ''
            Write-Host "Connection to login.microsoftonline.com ................. failed." -ForegroundColor Red
            Write-Log -Message "Connection to login.microsoftonline.com ................. failed." -Level ERROR
        }
        $PSScript = "(Invoke-WebRequest -uri 'https://device.login.microsoftonline.com/common/oauth2' -UseBasicParsing).StatusCode"
        $TestResult = RunPScript -PSScript $PSScript
        if ($TestResult -eq 200){
            Write-Host "Connection to device.login.microsoftonline.com ......  Succeeded." -ForegroundColor Green
            Write-Log -Message "Connection to device.login.microsoftonline.com ......  Succeeded."
        }else{
            $global:TestFailed=$true
            Write-Host "Connection to device.login.microsoftonline.com .......... failed." -ForegroundColor Red
            Write-Log -Message "Connection to device.login.microsoftonline.com .......... failed." -Level ERROR
        }

        $PSScript = "(Invoke-WebRequest -uri 'https://enterpriseregistration.windows.net/microsoft.com/discover?api-version=1.7' -UseBasicParsing -Headers @{'Accept' = 'application/json'; 'ocp-adrs-client-name' = 'dsreg'; 'ocp-adrs-client-version' = '10'}).StatusCode"
        $TestResult = RunPScript -PSScript $PSScript
        if ($TestResult -eq 200){
            Write-Host "Connection to enterpriseregistration.windows.net ..... Succeeded." -ForegroundColor Green
            Write-Log -Message "Connection to enterpriseregistration.windows.net ..... Succeeded."
        }else{
            $global:TestFailed=$true
            Write-Host "Connection to enterpriseregistration.windows.net ........ failed." -ForegroundColor Red
            Write-Log -Message "Connection to enterpriseregistration.windows.net ........ failed." -Level ERROR
        }
    }

    # If test failed
    if ($global:TestFailed){
        Write-Host ''
        Write-Host ''
        Write-Host "Test failed: device is not able to communicate with MS endpoints under system account" -ForegroundColor red
        Write-Log -Message "Test failed: device is not able to communicate with MS endpoints under system account" -Level ERROR
        Write-Host ''
        Write-Host "Recommended actions: " -ForegroundColor Yellow
        Write-Host "- Make sure that the device is able to communicate with the above MS endpoints successfully under the system account." -ForegroundColor Yellow
        Write-Host "- If the organization requires access to the internet via an outbound proxy, it is recommended to implement Web Proxy Auto-Discovery (WPAD)." -ForegroundColor Yellow
        Write-Host "- If you don't use WPAD, you can configure proxy settings with GPO by deploying WinHTTP Proxy Settings on your computers beginning with Windows 10 1709." -ForegroundColor Yellow
        Write-Host "- If the organization requires access to the internet via an authenticated outbound proxy, make sure that Windows 10 computers can successfully authenticate to the outbound proxy using the machine context." -ForegroundColor Yellow
        Write-Log -Message "Recommended actions:
        - Make sure that the device is able to communicate with the above MS endpoints successfully under the system account.
        - If the organization requires access to the internet via an outbound proxy, it is recommended to implement Web Proxy Auto-Discovery (WPAD).
        - If you don't use WPAD, you can configure proxy settings with GPO by deploying WinHTTP Proxy Settings on your computers beginning with Windows 10 1709.
        - If the organization requires access to the internet via an authenticated outbound proxy, make sure that Windows 10 computers can successfully authenticate to the outbound proxy using the machine context."
        Write-Host ''
        Write-Host ''
        Write-Host "Script completed successfully." -ForegroundColor Green
        Write-Log -Message "Script completed successfully."
        Write-Host ''
    }else{
        Write-Host ''
        Write-Host "Test passed: Device is able to communicate with MS endpoints successfully under system context" -ForegroundColor Green
        Write-Log -Message "Test passed: Device is able to communicate with MS endpoints successfully under system context"
        Write-Host ''
        Write-Host ''
        Write-Host "Script completed successfully." -ForegroundColor Green
        Write-Log -Message "Script completed successfully."
        Write-Host ''
    }
}

Function PSasAdmin{
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$global:Bypass=""
$global:login=$false
$global:device=$false
$global:enterprise=$false

Write-Host ''
'====================================================='
Write-Host '        Test Device Registration Connectivity        ' -ForegroundColor Green 
'====================================================='

Add-Content ".\Test-DeviceRegConnectivity.log" -Value "===========================================================================" -ErrorAction SilentlyContinue
if($Error[0].Exception.Message -ne $null){
    if($Error[0].Exception.Message.Contains('denied')){
        Write-Host ''
        Write-Host "Was not able to create log file." -ForegroundColor Yellow
    }else{
        Write-Host ''
        Write-Host "Test-DeviceRegConnectivity log file has been created." -ForegroundColor Yellow
    }
}else{
    Write-Host ''
    Write-Host "Test-DeviceRegConnectivity log file has been created." -ForegroundColor Yellow
}
Add-Content ".\Test-DeviceRegConnectivity.log" -Value "===========================================================================" -ErrorAction SilentlyContinue
Write-Log -Message "Test-DeviceRegConnectivity 3.2 has started"
$msg="Device Name : " + (Get-Childitem env:computername).value
Write-Log -Message $msg
Add-Type -AssemblyName System.DirectoryServices.AccountManagement            
$UserPrincipal = [System.DirectoryServices.AccountManagement.UserPrincipal]::Current
If ($UserPrincipal.ContextType -ne "Machine"){
    $UserUPN=whoami /upn
}
$msg="User Account: " + (whoami) +", UPN: "+$UserUPN
Write-Log -Message $msg

if (PSasAdmin){
    # PS running as admin.
    Test-DevRegConnectivity
}else{
    Write-Host ''
    Write-Host "PowerShell is NOT running with elevated privileges" -ForegroundColor Red
    Write-Log -Message "PowerShell is NOT running with elevated privileges" -Level ERROR
    Write-Host ''
    Write-Host "Recommended action: This test needs to be running with elevated privileges" -ForegroundColor Yellow
    Write-Log -Message "Recommended action: This test needs to be running with elevated privileges"
    Write-Host ''
    Write-Host ''
    Write-Host "Script completed successfully." -ForegroundColor Green
    Write-Log -Message "Script completed successfully."
    Write-Host ''
    exit
}

# SIG # Begin signature block
# MIInmAYJKoZIhvcNAQcCoIIniTCCJ4UCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCrU8T9S50bUEga
# b6RxkLKEdu5IJbOwwdlCRO3Kx2+xyKCCDXYwggX0MIID3KADAgECAhMzAAACy7d1
# OfsCcUI2AAAAAALLMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjIwNTEyMjA0NTU5WhcNMjMwNTExMjA0NTU5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC3sN0WcdGpGXPZIb5iNfFB0xZ8rnJvYnxD6Uf2BHXglpbTEfoe+mO//oLWkRxA
# wppditsSVOD0oglKbtnh9Wp2DARLcxbGaW4YanOWSB1LyLRpHnnQ5POlh2U5trg4
# 3gQjvlNZlQB3lL+zrPtbNvMA7E0Wkmo+Z6YFnsf7aek+KGzaGboAeFO4uKZjQXY5
# RmMzE70Bwaz7hvA05jDURdRKH0i/1yK96TDuP7JyRFLOvA3UXNWz00R9w7ppMDcN
# lXtrmbPigv3xE9FfpfmJRtiOZQKd73K72Wujmj6/Su3+DBTpOq7NgdntW2lJfX3X
# a6oe4F9Pk9xRhkwHsk7Ju9E/AgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUrg/nt/gj+BBLd1jZWYhok7v5/w4w
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzQ3MDUyODAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAJL5t6pVjIRlQ8j4dAFJ
# ZnMke3rRHeQDOPFxswM47HRvgQa2E1jea2aYiMk1WmdqWnYw1bal4IzRlSVf4czf
# zx2vjOIOiaGllW2ByHkfKApngOzJmAQ8F15xSHPRvNMmvpC3PFLvKMf3y5SyPJxh
# 922TTq0q5epJv1SgZDWlUlHL/Ex1nX8kzBRhHvc6D6F5la+oAO4A3o/ZC05OOgm4
# EJxZP9MqUi5iid2dw4Jg/HvtDpCcLj1GLIhCDaebKegajCJlMhhxnDXrGFLJfX8j
# 7k7LUvrZDsQniJZ3D66K+3SZTLhvwK7dMGVFuUUJUfDifrlCTjKG9mxsPDllfyck
# 4zGnRZv8Jw9RgE1zAghnU14L0vVUNOzi/4bE7wIsiRyIcCcVoXRneBA3n/frLXvd
# jDsbb2lpGu78+s1zbO5N0bhHWq4j5WMutrspBxEhqG2PSBjC5Ypi+jhtfu3+x76N
# mBvsyKuxx9+Hm/ALnlzKxr4KyMR3/z4IRMzA1QyppNk65Ui+jB14g+w4vole33M1
# pVqVckrmSebUkmjnCshCiH12IFgHZF7gRwE4YZrJ7QjxZeoZqHaKsQLRMp653beB
# fHfeva9zJPhBSdVcCW7x9q0c2HVPLJHX9YCUU714I+qtLpDGrdbZxD9mikPqL/To
# /1lDZ0ch8FtePhME7houuoPcMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGXgwghl0AgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAALLt3U5+wJxQjYAAAAAAsswDQYJYIZIAWUDBAIB
# BQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIMqUKLMb6OUH18BvFaxGKDy0
# 5Lp88N2P6IEZQeONhXXdMEQGCisGAQQBgjcCAQwxNjA0oBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEcgBpodHRwczovL3d3d3cubWljcm9zb2Z0LmNvbTANBgkqhkiG9w0B
# AQEFAASCAQACl8L7C+unJFm3vEKPDqdGEUwbHlkPYxpk6YHeBs5186UQeplDhUh2
# 21Kxqi+9Ic4ZgB80Y51z2Uxox0nyNi2J5WUNLN10iPw/sNO58PO1+zjtvYCx2X/s
# Sn5Xv3FdOM17Lol+rXvi0/jXfNBIfbXgArSpvDA55X6p82A45RtKhaxkVXcodpIQ
# s20r71daqIGQ6fZj0usw5fQXwwqeiVpvM4Y2GilPv7kjckzU4+mF9PJxGmOYrOhZ
# mCELDK7NfsSN9sKOM5k411nMOcCeFe/bNhlhVfWA6PznG7MkiWUXQ/VfDHOO2BQ8
# TNB2K26SEJpn/lwuM3ZAY6Zbxcn39XKkoYIXADCCFvwGCisGAQQBgjcDAwExghbs
# MIIW6AYJKoZIhvcNAQcCoIIW2TCCFtUCAQMxDzANBglghkgBZQMEAgEFADCCAVEG
# CyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEICNZ65qMw+nh6r5rcBwWwCi2etlQ7v1ennGU5ORU7fy+AgZi9nQu
# waUYEzIwMjIwOTAxMDgwMDA1Ljc5OFowBIACAfSggdCkgc0wgcoxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBB
# bWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkREOEMt
# RTMzNy0yRkFFMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oIIRVzCCBwwwggT0oAMCAQICEzMAAAGcD6ZNYdKeSygAAQAAAZwwDQYJKoZIhvcN
# AQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMjExMjAyMTkw
# NTE5WhcNMjMwMjI4MTkwNTE5WjCByjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9u
# czEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046REQ4Qy1FMzM3LTJGQUUxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQDbUioMGV1JFj+s612s02mKu23KPUNs71OjDeJGtxkT
# F9rSWTiuA8XgYkAAi/5+2Ff7Ck7JcKQ9H/XD1OKwg1/bH3E1qO1z8XRy0PlpGhmy
# ilgE7KsOvW8PIZCf243KdldgOrxrL8HKiQodOwStyT5lLWYpMsuT2fH8k8oihje4
# TlpWiFPaCKLnFDaAB0Ccy6vIdtHjYB1Ie3iOZPisquL+vNdCx7gOhB8iiTmTdsU8
# OSUpC8tBTeTIYPzmhaxQZd4moNk6qeCJyi7fiW4fyXdHrZ3otmgxxa5pXz5pUUr+
# cEjV+cwIYBMkaY5kHM9c6dEGkgHn0ZDJvdt/54FOdSG61WwHh4+evUhwvXaB4LCM
# ZIdCt5acOfNvtDjV3CHyFOp5AU/qgAwGftHU9brv4EUwcuteEAKH46NufE20l/Wj
# lNUh7gAvt2zKMjO4zXRxCUTh/prBQwXJiUZeFSrEXiOfkuvSlBniyAYYZp5kOnax
# fCKdGYjvr4QLA93vQJ6p2Ox3IHvOdCPaCr8LsKVcFpyp8MEhhJTM+1LwqHJqFDF5
# O1Z9mjbYvm3R9vPhkG+RDLKoTpr7mTgkaTljd9xvm94Obp8BD9Hk4mPi51mtgLiu
# N8/6aZVESVZXtvSuNkD5DnIJQerIy5jaRKW/W2rCe9ngNDJadS7R96GGRl7IIE37
# lwIDAQABo4IBNjCCATIwHQYDVR0OBBYEFLtpCWdTXY5dtddkspy+oxjCA/qyMB8G
# A1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCG
# Tmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUy
# MFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4w
# XAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2Vy
# dHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
# A1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQELBQAD
# ggIBAKcAKqYjGEczTWMs9z0m7Yo23sgqVF3LyK6gOMz7TCHAJN+FvbvZkQ53Vkvr
# ZUd1sE6a9ToGldcJnOmBc6iuhBlpvdN1BLBRO8QSTD1433VTj4XCQd737wND1+eq
# KG3BdjrzbDksEwfG4v57PgrN/T7s7PkEjUGXfIgFQQkr8TQi+/HZZ9kRlNccgeAC
# qlfb4uGPxn5sdhQPoxdMvmC3qG9DONJ5UsS9KtO+bey+ohUTDa9LvEToc4Qzy5fu
# Hj2H1JsmCaKG78nXpfWpwBLBxZYSpfml29onN8jcG7KD8nGSS/76PDlb2GMQsvv+
# Ra0JgL6FtGRGgYmHCpM6zVrf4V/a+SoHcC+tcdGYk2aKU5KOlv+fFE3n024V+z54
# tDAKR9z78rejdCBWqfvy5cBUQ9c5+3unHD08BEp7qP2rgpoD856vNDgEwO77n7EW
# T76nl/IyrbK2kjbHLzUMphFpXKnV1fYWJI2+E/0LHvXFGGqF4OvMBRxbrJVn03T2
# Dy5db6s5TzJzSaQvCrXYqA4HKvstQWkqkpvBHTX8M09+/vyRbVXNxrPdeXw6oD2Q
# 4DksykCFfn8N2j2LdixE9wG5iilv69dzsvHIN/g9A9+thkAQCVb9DUSOTaMIGgsO
# qDYFjhT6ze9lkhHHGv/EEIkxj9l6S4hqUQyWerFkaUWDXcnZMIIHcTCCBVmgAwIB
# AgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0
# IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgyMjI1
# WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCC
# AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzntHIhC3miy9ckeb0O
# 1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+uDZn
# hUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFcUTE3oAo4bo3t
# 1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhiJdxq
# D89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUoveO0hyTD4MmP
# frVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKNiOSW
# rAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXftnIv
# 231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8P0zb
# r17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMYcten
# IPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiER9vcG9H9stQc
# xWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/eKtFtvUeh17a
# j54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3FQEEBQIDAQAB
# MCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4EFgQU
# n6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEEAYI3TIN9AQEw
# QTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9E
# b2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/
# MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJ
# oEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01p
# Y1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYB
# BQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9v
# Q2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38Kq3h
# LB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pkbHzQdTltuw8x
# 5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99qb74p
# y27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3lbYoVSfQJL1A
# oL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1ijbC
# HcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP9pEB
# 9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkkvnNt
# yo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvshVGtqRRFHqfG3
# rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g75LcV
# v7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr4A24
# 5oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHIqzqKOghif9lw
# Y1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAs4wggI3AgEBMIH4oYHQpIHNMIHK
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYDVQQLEx1UaGFsZXMgVFNT
# IEVTTjpERDhDLUUzMzctMkZBRTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAzdlp6t3ws/bnErbm9c0M+9dvU0Cg
# gYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
# JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0B
# AQUFAAIFAOa6p1wwIhgPMjAyMjA5MDExMTM3MDBaGA8yMDIyMDkwMjExMzcwMFow
# dzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5rqnXAIBADAKAgEAAgInOAIB/zAHAgEA
# AgISbzAKAgUA5rv43AIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMC
# oAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUAA4GBAK2l4VBP
# wq36f3vcUijysOCspKbVvNgQyyheFAvc8fRam0eMMq0ax4HlttXXIkHGRZ7qpfvp
# epEFO/749vKpbpzxTTpzYCHUM0Zid5Cg2+zA+5BqSj19JPzpQPybk0qq1yk5RGuv
# 0mJD2vk01oRwbM05IBehnMIx7agVr/WlVargMYIEDTCCBAkCAQEwgZMwfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGcD6ZNYdKeSygAAQAAAZwwDQYJ
# YIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkq
# hkiG9w0BCQQxIgQgLqlNOP3Vr5DiZj1d9s2x6OG0ze7RdsEBY7Zo5+OAK3gwgfoG
# CyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCA3D0WFII0syjoRd/XeEIG0WUIKzzuy
# 6P6hORrb0nqmvDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAABnA+mTWHSnksoAAEAAAGcMCIEIPO8tNGNYhoYn/YEWfIE05Hw1tlC5hFF
# 7xkijqoLGxPqMA0GCSqGSIb3DQEBCwUABIICAJRfX/YftGsU671S3ia+lA4u1RMO
# D1pnuPl3w4edR3T7MWu0Ou2mdg8MleP3Ltbw0VU9GkQ2+XS3BSpKCb5S+UrwVvaE
# Q7h/D+CMndahzWg2yzNVd1GcFzmGk50Ta+VEVlLkmAsoZBCW7BDgXkFvF3CAIhPI
# 1C/3ll3g5+xvASE0CZRr2zL99bML7QfGvOUiPfAwBQ7fBBQbTcBds11p3FbXibpi
# Z68Ep7fHlj6HfHF/d+Nl7TxaxckhT6H00cz03eCo9WiPAF7+TCFssoQU9ag8NhIZ
# wG03fhF9gnMFmY/fEdwa5zPklD7/13SRYFpZFaUy7Xwa83SGCR5T1OMHdwCLQHGo
# h+sjvLpFF4X2+TdvSNoR1VL5qRb2gGPoALaE0eIuiZDKP4wWRaBpLSOZXGyVA2bH
# sbjTGqb1Y4CtFj3U1A9vJD5t//p70CjZfjrF4AbojVL9APXqY165eeHbl8eQaHs5
# 8laWsdVEYUt9qormG2SufQQEXq0KFBfziRKmDU9NGw6Qf85uZi7Vpr3EClboCak4
# udh185cy+6MgU/neAh8R3KW0URMbsXSXHzw9buxjh9W1ymfxK5cYZRT7xwJhrRqU
# cl949D3O8wREeFZ6p90rEPlZii6n5+IyJwnZO4Znupsjyuq52cx2BeBJAgftVm5i
# R7TSoAZTNsrR2HPy
# SIG # End signature block
