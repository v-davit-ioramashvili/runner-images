################################################################################
##  File:  Install-Apache.ps1
##  Desc:  Install Apache HTTP Server
##  Supply chain security: Apache - checksum validation
################################################################################

# Stop w3svc service
$w3svcService = Get-Service -Name "w3svc" -ErrorAction SilentlyContinue
if ($w3svcService) {
    Stop-Service $w3svcService
}

# Apache Lounge build pinned in the toolset (the chocolatey package is no longer updated).
# apachelounge.com blocks PowerShell downloads, so the verified archive is served from a mirror.
$apacheToolset = (Get-ToolsetContent).apache
$archivePath = Invoke-DownloadWithRetry $apacheToolset.url

#region Supply chain security
Test-FileChecksum $archivePath -ExpectedSHA256Sum $apacheToolset.checksum
#endregion

# Extract to C:\tools\Apache24
$installDir = "C:\tools"
$apachePath = Join-Path $installDir "Apache24"
$extractPath = Join-Path $env:TEMP_DIR "apache"
Expand-7ZipArchive -Path $archivePath -DestinationPath $extractPath
Move-Item -Path (Join-Path $extractPath "Apache24") -Destination $apachePath
Remove-Item -Path $extractPath -Recurse -Force

# Point server root to the install location
$configPath = Join-Path $apachePath "conf\httpd.conf"
(Get-Content $configPath) -replace '^Define SRVROOT ".*"$', "Define SRVROOT `"$($apachePath -replace '\\', '/')`"" `
    | Set-Content $configPath

# Register Apache service, then stop and disable it
& "$apachePath\bin\httpd.exe" -k install -n Apache
if ($LASTEXITCODE -ne 0) {
    throw "Failed to register Apache service"
}
Stop-Service -Name Apache -ErrorAction SilentlyContinue
Set-Service -Name Apache -StartupType Disabled

# Start w3svc service
$w3svcService = Get-Service -Name "w3svc" -ErrorAction SilentlyContinue
if ($w3svcService) {
    Start-Service $w3svcService
}

# Invoke Pester Tests
Invoke-PesterTests -TestFile "Apache"
