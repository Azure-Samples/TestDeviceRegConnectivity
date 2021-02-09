<# 
 
.SYNOPSIS
    Test-HybridDevicesInternetConnectivity V2.1 PowerShell script.

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
$ProxyServer="NoProxy"
$winHTTP = netsh winhttp show proxy
$Proxy = $winHTTP | Select-String server
$ProxyServer=$Proxy.ToString().TrimStart("Proxy Server(s) :  ")
$global:Bypass = $winHTTP | Select-String Bypass
$global:Bypass=$global:Bypass.ToString().TrimStart("Bypass List     :  ")

if ($ProxyServer -eq "Direct access (no proxy server)."){
    $ProxyServer="NoProxy"
    Write-Host "Access Type : DIRECT"
}

if ( ($ProxyServer -ne "NoProxy") -and (-not($ProxyServer.StartsWith("http://")))){
    Write-Host "      Access Type : PROXY"
    Write-Host "Proxy Server List :" $ProxyServer
    Write-Host "Proxy Bypass List :" $global:Bypass
    $ProxyServer = "http://" + $ProxyServer
}

$global:login= $global:Bypass.Contains("*.microsoftonline.com") -or $global:Bypass.Contains("login.microsoftonline.com")

$global:device= $global:Bypass.Contains("*.microsoftonline.com") -or $global:Bypass.Contains("*.login.microsoftonline.com") -or $global:Bypass.Contains("device.login.microsoftonline.com")

$global:enterprise= $global:Bypass.Contains("*.windows.net") -or $global:Bypass.Contains("enterpriseregistration.windows.net")

return $ProxyServer
}

Function Test-DeviceRegConnectivity{
$ErrorActionPreference= 'silentlycontinue'
''
$TestFailed=$false

$ProxyServer = checkProxy
''
''
Write-Host "Checking Internet Connectivity..." -ForegroundColor Yellow
if ($ProxyServer -eq "NoProxy"){
    $PSScript = "(Invoke-WebRequest -uri 'login.microsoftonline.com' -UseBasicParsing).StatusCode"
    $TestResult = RunPScript -PSScript $PSScript
    if ($TestResult -eq 200){
        Write-Host "Connection to login.microsoftonline.com .............. Succeeded." -ForegroundColor Green 
    }else{
        $TestFailed=$true
        Write-Host "Connection to login.microsoftonline.com ................. failed." -ForegroundColor Red 
    }
    $PSScript = "(Invoke-WebRequest -uri 'device.login.microsoftonline.com' -UseBasicParsing).StatusCode"
    $TestResult = RunPScript -PSScript $PSScript
    if ($TestResult -eq 200){
        Write-Host "Connection to device.login.microsoftonline.com ......  Succeeded." -ForegroundColor Green 
    }else{
        $TestFailed=$true
        Write-Host "Connection to device.login.microsoftonline.com .......... failed." -ForegroundColor Red 
    }

    $PSScript = "(Invoke-WebRequest -uri 'https://enterpriseregistration.windows.net/microsoft.com/discover?api-version=1.7' -UseBasicParsing -Headers @{'Accept' = 'application/json'; 'ocp-adrs-client-name' = 'dsreg'; 'ocp-adrs-client-version' = '10'}).StatusCode"
    $TestResult = RunPScript -PSScript $PSScript
    if ($TestResult -eq 200){
        Write-Host "Connection to enterpriseregistration.windows.net ..... Succeeded." -ForegroundColor Green 
    }else{
        $TestFailed=$true
        Write-Host "Connection to enterpriseregistration.windows.net ........ failed." -ForegroundColor Red 
    }
}else{
    if ($global:login){
        $PSScript = "(Invoke-WebRequest -uri 'login.microsoftonline.com' -UseBasicParsing).StatusCode"
        $TestResult = RunPScript -PSScript $PSScript
    }else{
        $PSScript = "(Invoke-WebRequest -uri 'login.microsoftonline.com' -UseBasicParsing -Proxy $ProxyServer).StatusCode"
        $TestResult = RunPScript -PSScript $PSScript
    }
    if ($TestResult -eq 200){
        Write-Host "Connection to login.microsoftonline.com .............. Succeeded." -ForegroundColor Green 
    }else{
        $TestFailed=$true
        Write-Host "Connection to login.microsoftonline.com ................. failed." -ForegroundColor Red 
    }

    if ($global:device){
        $PSScript = "(Invoke-WebRequest -uri 'device.login.microsoftonline.com' -UseBasicParsing).StatusCode"
        $TestResult = RunPScript -PSScript $PSScript
    }else{
        $PSScript = "(Invoke-WebRequest -uri 'device.login.microsoftonline.com' -UseBasicParsing -Proxy $ProxyServer).StatusCode"
        $TestResult = RunPScript -PSScript $PSScript
    }
    if ($TestResult -eq 200){
        Write-Host "Connection to device.login.microsoftonline.com ......  Succeeded." -ForegroundColor Green 
    }else{
        $TestFailed=$true
        Write-Host "Connection to device.login.microsoftonline.com .......... failed." -ForegroundColor Red 
    }

    if ($global:enterprise){
        $PSScript = "(Invoke-WebRequest -uri 'https://enterpriseregistration.windows.net/microsoft.com/discover?api-version=1.7' -UseBasicParsing -Headers @{'Accept' = 'application/json'; 'ocp-adrs-client-name' = 'dsreg'; 'ocp-adrs-client-version' = '10'}).StatusCode"
        $TestResult = RunPScript -PSScript $PSScript
    }else{
        $PSScript = "(Invoke-WebRequest -uri 'https://enterpriseregistration.windows.net/microsoft.com/discover?api-version=1.7' -UseBasicParsing -Proxy $ProxyServer -Headers @{'Accept' = 'application/json'; 'ocp-adrs-client-name' = 'dsreg'; 'ocp-adrs-client-version' = '10'}).StatusCode"
        $TestResult = RunPScript -PSScript $PSScript
    }
    if ($TestResult -eq 200){
        Write-Host "Connection to enterpriseregistration.windows.net ..... Succeeded." -ForegroundColor Green 
    }else{
        $TestFailed=$true
        Write-Host "Connection to enterpriseregistration.windows.net ........ failed." -ForegroundColor Red 
    }
}

# If test failed
if ($TestFailed){
    ''
    ''
    Write-Host "Test failed: device is not able to communicate with MS endpoints under system account" -ForegroundColor red -BackgroundColor Black
    ''
    Write-Host "Recommended actions: " -ForegroundColor Yellow
    Write-Host "- Make sure that the device is able to communicate with the above MS endpoints successfully under the system account." -ForegroundColor Yellow
    Write-Host "- If the organization requires access to the internet via an outbound proxy, it is recommended to implement Web Proxy Auto-Discovery (WPAD)." -ForegroundColor Yellow
    Write-Host "- If you don't use WPAD, you can configure proxy settings with GPO by deploying WinHTTP Proxy Settings on your computers beginning with Windows 10 1709." -ForegroundColor Yellow
    Write-Host "- If the organization requires access to the internet via an authenticated outbound proxy, make sure that Windows 10 computers can successfully authenticate to the outbound proxy using the machine context." -ForegroundColor Yellow
}

    ''
    ''
    Write-Host "Script completed successfully." -ForegroundColor Green -BackgroundColor Black
    ''
}

Function PSasAdmin{
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())    $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$global:Bypass=""
$global:login=$false
$global:device=$false
$global:enterprise=$false
if (PSasAdmin){
    # PS running as admin.
    Test-DeviceRegConnectivity
}else{
    ''
    Write-Host "PowerShell is NOT running with elevated privileges" -ForegroundColor Red -BackgroundColor Black
    ''
    Write-Host "Recommended action: This test needs to be running with elevated privileges" -ForegroundColor Yellow -BackgroundColor Black
    ''
    ''
    Write-Host "Script completed successfully." -ForegroundColor Green -BackgroundColor Black
    ''
    exit
}
