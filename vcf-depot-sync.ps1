<#
================================================================================
Script Name: vcf-depot-sync.ps1
Platform:    Windows Server (PowerShell 5.1 / PowerShell 7+)
Purpose:     Automated weekly synchronization of VMware Cloud Foundation (VCF) 
             9.1.x+ base install binaries, maintenance/express patches, ESXi 9.1 
             x86_64 host updates, and certified OEM vendor add-ons for air-gapped 
             offline depots with vSphere Lifecycle Manager (vLCM) shared repository 
             support.
================================================================================
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$VcfdtBin = "E:\VCF\Tools\vcf-download-tool\bin\vcf-download-tool.bat",

    [Parameter(Mandatory = $false)]
    [string]$DepotStore = "E:\VCF-Depot",

    [Parameter(Mandatory = $false)]
    [string]$AuthFile = "E:\VCF\activation-code.txt",

    # Regex pattern to match all active 9.1.x releases automatically
    [Parameter(Mandatory = $false)]
    [string]$VersionPattern = '^9\.1\.',

    [Parameter(Mandatory = $false)]
    [string]$Sku = "VCF",

    [Parameter(Mandatory = $false)]
    [int]$MinFreeSpaceGB = 50,

    [Parameter(Mandatory = $false)]
    [string]$LogFile = "E:\VCF\Tools\vcf-download-tool\log\vcf-download-sync.log",

    [Parameter(Mandatory = $false)]
    [string]$LockFile = "E:\VCF\Tools\vcf-download-tool\log\vcf-depot-sync.lock"
)

# ------------------------------------------------------------------------------
# Helper Logging Function
# ------------------------------------------------------------------------------
function Write-Log {
    param (
        [string]$Message,
        [string]$Severity = "INFO"
    )
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $FormattedMessage = "[$TimeStamp] [$Severity] $Message"
    Write-Output $FormattedMessage
    Add-Content -Path $LogFile -Value $FormattedMessage -Encoding UTF8
}

# Ensure log directory exists
$LogDir = Split-Path -Path $LogFile -Parent
if (!(Test-Path -Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# ------------------------------------------------------------------------------
# 1. PRIVILEGE VERIFICATION & PRE-FLIGHT CHECKS
# ------------------------------------------------------------------------------
# Verify script is running with elevated Administrator privileges
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$IsAdmin = $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Log "ERROR: This script MUST be executed with elevated Administrator privileges to permit NTFS directory symbolic link creation for the ESXi patch-store. Aborting." -Severity "ERROR"
    exit 1
}

# Concurrency lock control
try {
    $LockStream = [System.IO.File]::Open($LockFile, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
} catch {
    Write-Log "Another instance of vcf-depot-sync is currently active. Exiting." -Severity "WARNING"
    exit 0
}
exit 0
