# VCF 9.1+ & ESXi Offline Depot Sync (`vcf-depot-sync.ps1`)

Automated PowerShell script for weekly synchronization of VMware Cloud Foundation (VCF) 9.1+ base install binaries, maintenance/express patches, ESXi 9.1 x86_64 host updates, and certified OEM vendor add-ons for air-gapped offline depots. The script also configures a directory junction to support vSphere Lifecycle Manager (vLCM) shared repositories.

## Key Capabilities

* **Privilege & Pre-Flight Validation:** Verifies elevated Administrator privileges, enforces single-instance execution via a file lock, validates tool and credential paths, creates missing directories, and checks available disk space before starting downloads.
* **ESXi Platform Filtering & Cleanup:** Removes legacy third-party HPE VIB URLs (`https://vibs.hpe.com/index.xml` and `http://vibs.hpe.com/hpe/index.xml`), disables older and unused hypervisor targets (`embeddedEsx-7.0-INTL`, `embeddedEsx-8.0-INTL`, `esxio-8.0-INTL`, `embeddedEsx-9.0-INTL`, `esxio-9.0-INTL`, and `esxio-9.1-INTL`), and exclusively enables standard x86_64 ESXi 9.1 (`embeddedEsx-9.1-INTL`).
* **VCF Metadata & Bundle Sync:** Downloads updated release manifests and HCL compatibility metadata, GA baseline install bundles (`INSTALL`), and component upgrade/express patch bundles (`UPGRADE`).
* **ESXi 9.1 Host Updates & OEM Add-Ons:** Synchronizes ESXi 9.1 metadata catalogs and downloads payload VIBs alongside certified OEM vendor add-ons.
* **vLCM Shared Repository Junction:** Creates an NTFS directory junction at `<DepotStore>\umds-patch-store` pointing to `<DepotStore>\PROD\COMP\ESX_HOST\patch-store` so vLCM can access `/umds-patch-store/hostupdate/`.
* **UTF-8 Logging:** Writes timestamped `INFO`, `WARNING`, and `ERROR` messages to both standard output and a persistent log file.

## Prerequisites

* **Operating System & Shell:** Windows Server running PowerShell 5.1 or PowerShell 7+.
* **Permissions:** Elevated **Administrator** privileges (required to create NTFS directory junctions/symbolic links for the ESXi patch store).
* **VCF Download Tool:** Installed locally (default expected path: `C:\vcfdt\bin\vcf-download-tool.bat`).
* **Activation Code:** Broadcom/VCF depot download activation code stored in a local text file (default expected path: `C:\vcfdt\credentials\activation-code.txt`).
* **Storage:** At least 50 GB of free disk space on the target depot drive by default.

## Parameters

All parameters are optional and fall back to built-in defaults if omitted:

| Parameter | Type | Default Value | Description |
| :--- | :--- | :--- | :--- |
| `-VcfdtBin` | `String` | `C:\vcfdt\bin\vcf-download-tool.bat` | Path to the VCF Download Tool executable. |
| `-DepotStore` | `String` | `D:\vcfdepot` | Destination root folder for the offline depot. |
| `-AuthFile` | `String` | `C:\vcfdt\credentials\activation-code.txt` | Path to the depot download activation code file. |
| `-VcfVersion` | `String` | `9.1.1.0` | Target VCF release version to download. |
| `-Sku` | `String` | `VCF` | Product SKU passed to the download tool. |
| `-MinFreeSpaceGB` | `Int` | `50` | Minimum free disk space (in GB) required on the depot drive. |
| `-LogFile` | `String` | `C:\vcfdt\logs\vcf-download-sync.log` | Path to the output log file. |
| `-LockFile` | `String` | `C:\vcfdt\logs\vcf-depot-sync.lock` | Path to the concurrency lock file. |

## Usage

Run the script from an elevated (**Run as Administrator**) PowerShell session:

```powershell
# Run with default paths and VCF 9.1.1.0
.\vcf-depot-sync.ps1
```

Override defaults as needed for custom storage paths, versions, or disk space thresholds:

```powershell
# Run with custom depot location and 100 GB free-space check
.\vcf-depot-sync.ps1 `
    -DepotStore "E:\vcfdepot" `
    -VcfVersion "9.1.1.0" `
    -MinFreeSpaceGB 100
```

## Exit Codes & Logging

* **Exit Code `0`:** Synchronization completed successfully, or another instance is already running and holds the lock file.
* **Exit Code `1`:** Execution aborted due to missing Administrator privileges, missing executable/credential files, insufficient disk space, or a failed download step.
* **Log Format:** Entries are recorded as `[yyyy-MM-dd HH:mm:ss] [SEVERITY] Message` in UTF-8 encoding.

## License

Dual-licensed under **Apache-2.0 / MIT**.
