<#
================================================================================
Script Name: vcf-depot-sync.ps1
Platform:    Windows Server (PowerShell 5.1 / PowerShell 7+)
Purpose:     Automated weekly synchronization of VMware Cloud Foundation (VCF) 
             9.1.x base install binaries, maintenance/express patches, ESXi 9.1 
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

    # Minimum VCF version to sync (prevents downloading obsolete older releases like 9.1.0.0)
    [Parameter(Mandatory = $false)]
    [string]$MinVcfVersion = "9.1.1.0",

    # Upper major version boundary regex (keeps sync constrained to 9.1.x family)
    [Parameter(Mandatory = $false)]
    [string]$VersionPattern = '^9\.1\.',

    [Parameter(Mandatory = $false)]
    [string]$Sku = "VCF",

    # Configures CEIP non-interactively to prevent interactive terminal prompt hangs
    [Parameter(Mandatory = $false)]
    [bool]$EnableCeip = $false,

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

Write-Log "============================================================"
Write-Log "Starting VCF 9.1.x & ESXi Weekly Depot Sync on Windows Server"
Write-Log "============================================================"

# Verify VCF Download Tool executable exists
if (!(Test-Path -Path $VcfdtBin)) {
    Write-Log "ERROR: VCF Download Tool executable not found at: $VcfdtBin" -Severity "ERROR"
    $LockStream.Close()
    exit 1
}

# Verify activation code file exists
if (!(Test-Path -Path $AuthFile)) {
    Write-Log "ERROR: Activation code file not found at: $AuthFile" -Severity "ERROR"
    $LockStream.Close()
    exit 1
}

# Verify depot directory exists or create it
if (!(Test-Path -Path $DepotStore)) {
    Write-Log "Depot directory $DepotStore does not exist. Creating..."
    New-Item -ItemType Directory -Path $DepotStore -Force | Out-Null
}

# Storage space pre-check
$DepotDrive = (Get-Item $DepotStore).PSDrive.Name + ":"
$Disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$DepotDrive'"
$FreeGB = [math]::Round($Disk.FreeSpace / 1GB, 2)
if ($FreeGB -lt $MinFreeSpaceGB) {
    Write-Log "ERROR: Insufficient disk space on drive ${DepotDrive}. Available: ${FreeGB}GB, Required: ${MinFreeSpaceGB}GB." -Severity "ERROR"
    $LockStream.Close()
    exit 1
}
Write-Log "Storage pre-check passed. Available space on ${DepotDrive}: ${FreeGB}GB."

# Helper to execute tool commands and track exit code
function Invoke-ToolCommand {
    param (
        [string]$Description,
        [string[]]$Arguments,
        [bool]$IgnoreFailure = $false
    )
    Write-Log $Description
    & $VcfdtBin $Arguments *>> $LogFile
    if ($LASTEXITCODE -ne 0) {
        if ($IgnoreFailure) {
            Write-Log "Notice: Optional command completed with non-zero exit code ${LASTEXITCODE} (may indicate no packages of this type exist): $VcfdtBin $($Arguments -join ' ')" -Severity "WARNING"
            return $true
        } else {
            Write-Log "Command failed with exit code ${LASTEXITCODE}: $VcfdtBin $($Arguments -join ' ')" -Severity "ERROR"
            return $false
        }
    }
    return $true
}

# ------------------------------------------------------------------------------
# 2. NON-INTERACTIVE CEIP & ESXi PLATFORM CONFIGURATION
# ------------------------------------------------------------------------------
# Configure CEIP non-interactively to suppress interactive console prompt stalls
if ($EnableCeip) {
    Write-Log "Configuring Customer Experience Improvement Program (CEIP): Enabled"
    & $VcfdtBin ceip enable *>> $LogFile
} else {
    Write-Log "Configuring Customer Experience Improvement Program (CEIP): Disabled"
    & $VcfdtBin ceip disable *>> $LogFile
}

Write-Log "[1/6] Configuring ESXi repository platforms and cleaning legacy depot URLs..."

# Prune any stale or unreachable third-party URLs previously added to persistent config
& $VcfdtBin esx configuration --remove-url "https://vibs.hpe.com/index.xml" *>> $LogFile
& $VcfdtBin esx configuration --remove-url "http://vibs.hpe.com/hpe/index.xml" *>> $LogFile

# Disable legacy and unused hypervisor platforms
$DisabledHosts = @(
    "embeddedEsx-7.0-INTL",
    "embeddedEsx-8.0-INTL",
    "esxio-8.0-INTL",
    "embeddedEsx-9.0-INTL",
    "esxio-9.0-INTL",
    "esxio-9.1-INTL"
)
foreach ($Target in $DisabledHosts) {
    & $VcfdtBin esx configuration --disable-host $Target *>> $LogFile
}

# Exclusively enable standard x86_64 ESXi 9.1 platform
& $VcfdtBin esx configuration --enable-host embeddedEsx-9.1-INTL *>> $LogFile

# ------------------------------------------------------------------------------
# 3. DOWNLOAD VCF METADATA (HCL & COMPATIBILITY)
# ------------------------------------------------------------------------------
$MetaSuccess = Invoke-ToolCommand -Description "[2/6] Downloading updated release manifests and compatibility metadata..." `
    -Arguments @("metadata", "download", "--depot-store", $DepotStore, "--depot-download-activation-code-file", $AuthFile)
if (-not $MetaSuccess) {
    Write-Log "Metadata download encountered errors. Review log above." -Severity "ERROR"
    $LockStream.Close()
    exit 1
}

# ------------------------------------------------------------------------------
# 4. RESILIENT DYNAMIC VERSION DISCOVERY (>= MinVcfVersion)
# ------------------------------------------------------------------------------
$ManifestPath = Join-Path -Path $DepotStore -ChildPath "PROD\metadata\manifest\v1\vcfManifest.json"
$DiscoveredVersions = @()

if (Test-Path -Path $ManifestPath) {
    try {
        $ManifestRaw = Get-Content -Path $ManifestPath -Raw
        $ManifestJson = $ManifestRaw | ConvertFrom-Json
        
        # Primary check: .releases property
        $CandidateReleases = if ($ManifestJson.releases) { $ManifestJson.releases } 
                             elseif ($ManifestJson.vcfReleases) { $ManifestJson.vcfReleases } 
                             else { @() }

        if ($CandidateReleases.Count -gt 0) {
            $DiscoveredVersions = $CandidateReleases | 
                Where-Object { 
                    $_.version -match $VersionPattern -and 
                    ([version]$_.version -ge [version]$MinVcfVersion) 
                } | 
                ForEach-Object { $_.version } | 
                Sort-Object -Unique
        } else {
            # Regex extraction fallback directly from raw JSON
            $Matches = [regex]::Matches($ManifestRaw, '"version"\s*:\s*"(9\.1\.\d+\.\d+)"')
            $DiscoveredVersions = $Matches | 
                ForEach-Object { $_.Groups[1].Value } | 
                Where-Object { [version]$_ -ge [version]$MinVcfVersion } | 
                Sort-Object -Unique
        }

        Write-Log "Dynamically discovered active VCF releases: $($DiscoveredVersions -join ', ')"
    } catch {
        Write-Log "Warning: Manifest parsing exception: $_. Falling back to default list." -Severity "WARNING"
    }
}

# Fallback safety list
if ($DiscoveredVersions.Count -eq 0) {
    $DiscoveredVersions = @("9.1.1.0", "9.1.2.0")
    Write-Log "Using fallback version list: $($DiscoveredVersions -join ', ')" -Severity "WARNING"
}

# ------------------------------------------------------------------------------
# 5. DOWNLOAD BINARIES FOR ALL DISCOVERED RELEASES
# ------------------------------------------------------------------------------
foreach ($Ver in $DiscoveredVersions) {
    # 5a. Base Install Bundles (Tolerates releases that only provide UPGRADE packages)
    Invoke-ToolCommand -Description "[3/6] Downloading VCF $Ver base install bundles (GA baseline if available)..." `
        -Arguments @("binaries", "download", "--sku", $Sku, "--vcf-version", $Ver, "--type", "INSTALL", "--depot-download-activation-code-file", $AuthFile, "--depot-store", $DepotStore) `
        -IgnoreFailure $true

    # 5b. Upgrade and Express Patch Bundles (Mandatory)
    $PatchSuccess = Invoke-ToolCommand -Description "[4/6] Downloading VCF $Ver component upgrade and patch bundles..." `
        -Arguments @("binaries", "download", "--sku", $Sku, "--vcf-version", $Ver, "--type", "UPGRADE", "--depot-download-activation-code-file", $AuthFile, "--depot-store", $DepotStore)
    if (-not $PatchSuccess) {
        Write-Log "VCF $Ver component upgrade binaries download encountered errors. Review log above." -Severity "ERROR"
        $LockStream.Close()
        exit 1
    }
}

# ------------------------------------------------------------------------------
# 6. DOWNLOAD ESXi 9.1 METADATA & HOST PATCHES (WITH CERTIFIED VENDOR ADD-ONS)
# ------------------------------------------------------------------------------
# Step 6a: Explicitly sync ESX metadata
$EsxMetaSuccess = Invoke-ToolCommand -Description "[5/6] Downloading ESXi 9.1 host update metadata and catalog indices..." `
    -Arguments @("esx", "metadata", "--depot-store", $DepotStore, "--depot-download-activation-code-file", $AuthFile)

# Step 6b: Download the ESXi 9.1 payload VIBs & certified OEM vendor add-ons
$EsxDownloadSuccess = Invoke-ToolCommand -Description "[6/6] Downloading ESXi 9.1 host patches and vendor add-ons..." `
    -Arguments @("esx", "download", "--depot-store", $DepotStore, "--depot-download-activation-code-file", $AuthFile)

if (-not ($EsxMetaSuccess -and $EsxDownloadSuccess)) {
    Write-Log "CRITICAL: ESXi patch/metadata download encountered errors. Check administrative privileges and permissions." -Severity "ERROR"
    $LockStream.Close()
    exit 1
}

# ------------------------------------------------------------------------------
# 7. UMDS DIRECTORY JUNCTION CREATION FOR vLCM
# ------------------------------------------------------------------------------
# vLCM expects the UMDS patch store to be exposed under /umds-patch-store/hostupdate/
$EsxPatchStorePath = Join-Path -Path $DepotStore -ChildPath "PROD\COMP\ESX_HOST\patch-store"
$UmdsJunctionPath   = Join-Path -Path $DepotStore -ChildPath "umds-patch-store"
if (Test-Path -Path $EsxPatchStorePath) {
    if (!(Test-Path -Path $UmdsJunctionPath)) {
        Write-Log "Creating Directory Junction for vLCM: $UmdsJunctionPath -> $EsxPatchStorePath"
        New-Item -ItemType Junction -Path $UmdsJunctionPath -Target $EsxPatchStorePath | Out-Null
    }
} else {
    Write-Log "WARNING: Expected patch store path was not found: $EsxPatchStorePath" -Severity "WARNING"
}

# ------------------------------------------------------------------------------
# 8. COMPLETION STATUS
# ------------------------------------------------------------------------------
Write-Log "[+] SUCCESS: VCF components for $($DiscoveredVersions -join ', '), ESXi 9.1, and certified vendor add-ons successfully synced."
$LockStream.Close()
exit 0
