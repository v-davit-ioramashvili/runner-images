# Create shells folder
$shellPath = "C:\shells"
New-Item -Path $shellPath -ItemType Directory | Out-Null

if ((Test-IsX64) -or (Test-IsArm64)) {
    # add a wrapper for C:\msys64\usr\bin\bash.exe
    # arm64 images carry the CLANGARM64 prefix, x64 images the UCRT64 one
    # (UCRT64 is the MSYS2-recommended default; MINGW64 is deprecated)
    $msystem = if (Test-IsArm64) { "CLANGARM64" } else { "UCRT64" }
@"
@echo off
setlocal
IF NOT DEFINED MSYS2_PATH_TYPE set MSYS2_PATH_TYPE=strict
IF NOT DEFINED MSYSTEM set MSYSTEM=$msystem
set CHERE_INVOKING=1
C:\msys64\usr\bin\bash.exe -leo pipefail %*
"@ | Out-File -FilePath "$shellPath\msys2bash.cmd" -Encoding ascii
}

# gitbash <--> C:\Program Files\Git\bin\bash.exe
New-Item -ItemType SymbolicLink -Path "$shellPath\gitbash.exe" -Target "$env:ProgramFiles\Git\bin\bash.exe" | Out-Null

# wslbash <--> C:\Windows\System32\bash.exe
New-Item -ItemType SymbolicLink -Path "$shellPath\wslbash.exe" -Target "$env:SystemRoot\System32\bash.exe" | Out-Null
