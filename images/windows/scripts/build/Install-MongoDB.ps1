####################################################################################
##  File:  Install-MongoDB.ps1
##  Desc:  Install MongoDB
####################################################################################

# Install mongodb package
$toolsetContent = Get-ToolsetContent
$toolsetVersion = $toolsetContent.mongodb.version

# Resolve the latest patch release from the downloads feed rather than the release notes
# page. The feed lists the newest release of each supported branch and is not subject to the
# markup and URL changes that repeatedly broke scraping the docs.
$mongoReleasesUrl = "https://downloads.mongodb.org/current.json"
$mongoReleases = Invoke-RestMethod -Uri $mongoReleasesUrl

$latestVersion = $mongoReleases.versions.version |
    Where-Object { $_ -like "$toolsetVersion.*" } |
    Sort-Object { [version]$_ } -Descending |
    Select-Object -First 1

if (-not $latestVersion) {
    throw "Unable to resolve latest MongoDB $toolsetVersion release from $mongoReleasesUrl"
}

Install-Binary `
    -Url "https://fastdl.mongodb.org/windows/mongodb-windows-x86_64-$latestVersion-signed.msi" `
    -ExtraInstallArgs @('TARGETDIR=C:\PROGRA~1\MongoDB ADDLOCAL=ALL') `
    -ExpectedSubject 'CN="MONGODB, INC.", O="MONGODB, INC.", L=New York, S=New York, C=US'

# Add mongodb to the PATH
$mongoPath = (Get-CimInstance Win32_Service -Filter "Name LIKE 'mongodb'").PathName
$mongoBin = Split-Path -Path $mongoPath.split('"')[1]
Add-MachinePathItem "$mongoBin"

# Wait for mongodb service running
$mongodbService = Get-Service "mongodb"
$mongodbService.WaitForStatus('Running', '00:01:00')

# Stop and disable mongodb service
Stop-Service $mongodbService
$mongodbService | Set-Service -StartupType Disabled

# Install mongodb shell for mongodb
# Query only the latest release: mongosh releases carry ~50 assets each, so paging through
# all of them takes minutes and api.github.com intermittently answers with 504
$mongoshRelease = Invoke-ScriptBlockWithRetry -RetryCount 5 -RetryIntervalSeconds 15 -Command {
    Invoke-RestMethod -Uri "https://api.github.com/repos/mongodb-js/mongosh/releases/latest"
}

$mongoshDownloadUrl = ([string[]] $mongoshRelease.assets.browser_download_url) -like "*/mongosh-*-x64.msi"
if ($mongoshDownloadUrl.Count -ne 1) {
    throw "Expected one mongosh x64 MSI in release $($mongoshRelease.tag_name), found $($mongoshDownloadUrl.Count)"
}
Write-Host "Found download url for mongosh $($mongoshRelease.tag_name): $mongoshDownloadUrl"

Install-Binary -Type MSI `
    -Url $mongoshDownloadUrl `
    -ExtraInstallArgs @('ALLUSERS=1') `
    -ExpectedSubject 'CN="MongoDB, Inc.", O="MongoDB, Inc.", L=New York, S=New York, C=US'


Invoke-PesterTests -TestFile "Databases" -TestName "MongoDB"
