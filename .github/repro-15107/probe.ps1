# Reports whether this pwsh process takes the TaskbarJumpList path (STARTF_USESHOWWINDOW set and not SW_HIDE)
# and how many gen0 GCs ran during startup. The GC count is read first, before Add-Type allocates.
param([string]$Label)

$gen0AtStart = [GC]::CollectionCount(0)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class StartupInfoProbe {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern void GetStartupInfoW(out STARTUPINFO si);
}
'@

$si = New-Object StartupInfoProbe+STARTUPINFO
[StartupInfoProbe]::GetStartupInfoW([ref]$si)
$jumpList = (($si.dwFlags -band 1) -eq 1) -and ($si.wShowWindow -ne 0)

"PROBE {0}: pwsh={1} dwFlags=0x{2:x} wShowWindow={3} jumpListRuns={4} gen0GCsDuringStartup={5} DOTNET_GCgen0size={6}" -f `
    $Label, $PSVersionTable.PSVersion, $si.dwFlags, $si.wShowWindow, $jumpList, $gen0AtStart, $env:DOTNET_GCgen0size
