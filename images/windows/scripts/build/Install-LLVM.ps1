################################################################################
##  File:  Install-LLVM.ps1
##  Desc:  Install the stable version of llvm and clang compilers
################################################################################

$llvmToolset = (Get-ToolsetContent).llvm

if ($llvmToolset.matchVisualStudio) {
    # The MSVC STL requires the Clang major version that ships with the same Visual Studio release,
    # so install the latest LLVM release of that major version
    $vsClangVersion = Get-VisualStudioClangVersion
    $llvmVersion = "$($vsClangVersion.Major)"
    Write-Host "Visual Studio ships Clang $vsClangVersion, installing the latest LLVM $llvmVersion release"
} else {
    $llvmVersion = $llvmToolset.version
}

if (Test-IsArm64) {
    $installDir = "C:\Program Files\LLVM"
    $releaseVersion = if ($llvmToolset.matchVisualStudio) { "$llvmVersion.*" } else { $llvmVersion }

    Write-Host "Resolve LLVM $releaseVersion ARM64 download URL"
    $downloadUrl = Resolve-GithubReleaseAssetUrl `
        -Repository "llvm/llvm-project" `
        -Version $releaseVersion `
        -UrlMatchPattern "clang*llvm-*-aarch64-pc-windows-msvc.tar.xz"

    Write-Host "Download LLVM $releaseVersion ARM64 archive"
    $archivePath = Invoke-DownloadWithRetry $downloadUrl

    Write-Host "Extract LLVM archive"
    $tarPath = $archivePath -replace '\.xz$'
    Expand-7ZipArchive -Path $archivePath -DestinationPath (Split-Path $archivePath)
    Expand-7ZipArchive -Path $tarPath -DestinationPath $env:TEMP_DIR

    Write-Host "Install LLVM to $installDir"
    $extractedDir = Get-ChildItem -Path $env:TEMP_DIR -Directory -Filter "clang+llvm-*" | Select-Object -First 1
    Move-Item -Path $extractedDir.FullName -Destination $installDir -Force

    Add-MachinePathItem (Join-Path $installDir "bin")
    Update-Environment
} else {
    $latestChocoVersion = Resolve-ChocoPackageVersion -PackageName "llvm" -TargetVersion $llvmVersion
    if (-not $latestChocoVersion) {
        throw "LLVM $llvmVersion is not available on Chocolatey"
    }
    Install-ChocoPackage llvm -ArgumentList '--version', $latestChocoVersion
}

Invoke-PesterTests -TestFile "LLVM"
