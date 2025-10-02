# Azure Storage Lifecycle Policy - Pre-Audit Script

A PowerShell tool for analyzing Azure Storage Accounts to assess the impact of implementing lifecycle policies before actual deployment.

## Overview

This script provides detailed analysis of your Azure Storage Account contents, helping you make informed decisions about lifecycle policies by showing:
- Data age distribution across all containers
- Number and size of blobs that would be affected
- Estimated cost savings (monthly and annual)
- Detailed reports in multiple formats

## Scripts Available

### 📄 pre-audit-script.ps1 (Original)
Sequential processing - works on PowerShell 5.1+

### ⚡ pre-audit-script-parallel.ps1 (Multi-Threaded)
**4-8x faster** parallel processing - requires PowerShell 7.0+
- Processes multiple containers simultaneously
- Configurable thread limit (default: 5)
- Ideal for storage accounts with many containers

## Features

- 📊 **Age Distribution Analysis** - Categorizes blobs into age groups (0-7 days, 8-30 days, 31-60 days, etc.)
- 💰 **Cost Impact Analysis** - Calculates potential monthly and annual savings
- 📈 **Container-Level Breakdown** - Detailed analysis for each container
- 📄 **Multiple Export Formats** - CSV for detailed data, TXT for executive summaries
- 🎨 **Rich Console Output** - Color-coded, progress-tracked analysis
- ⚡ **Safe & Read-Only** - No modifications to your storage account

## Requirements

### For Original Script (pre-audit-script.ps1)
- **PowerShell**: 5.1 or higher
- **Azure Modules**: `Az.Accounts` (≥2.10.0), `Az.Storage` (≥5.0.0)

### For Parallel Script (pre-audit-script-parallel.ps1)
- **PowerShell**: 7.0 or higher (REQUIRED)
- **Azure Modules**: `Az.Accounts` (≥2.10.0), `Az.Storage` (≥5.0.0)

## Installation

### 1. Install Required Modules

```powershell
# Install Az.Accounts module
Install-Module -Name Az.Accounts -MinimumVersion 2.10.0 -Scope CurrentUser -Force

# Install Az.Storage module
Install-Module -Name Az.Storage -MinimumVersion 5.0.0 -Scope CurrentUser -Force
```

### 2. Authenticate to Azure

```powershell
Connect-AzAccount
```

### 3. Clone or Download the Script

```bash
git clone https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle.git
cd pwsh-azure-storage-lifecycle
```

## Usage

### Original Script (Sequential)

```powershell
# Basic usage
.\pre-audit-script.ps1 `
    -resourceGroup "myResourceGroup" `
    -storageAccount "mystorageaccount" `
    -retentionDays 90
```

### Parallel Script (Multi-Threaded - 4-8x Faster)

```powershell
# Basic usage (default: 5 parallel threads)
.\pre-audit-script-parallel.ps1 `
    -resourceGroup "myResourceGroup" `
    -storageAccount "mystorageaccount" `
    -retentionDays 90

# With custom thread limit for even faster processing
.\pre-audit-script-parallel.ps1 `
    -resourceGroup "myResourceGroup" `
    -storageAccount "mystorageaccount" `
    -retentionDays 90 `
    -ThrottleLimit 10

# Force PowerShell 7 and bypass execution policy
pwsh -ExecutionPolicy Bypass -File .\pre-audit-script-parallel.ps1 `
    -resourceGroup "myResourceGroup" `
    -storageAccount "mystorageaccount" `
    -retentionDays 90
```

### With Custom Export Path (Both Scripts)

```powershell
.\pre-audit-script-parallel.ps1 `
    -resourceGroup "myResourceGroup" `
    -storageAccount "mystorageaccount" `
    -retentionDays 90 `
    -exportPath "C:\Reports\audit.csv"
```

## Parameters

| Parameter | Required | Description | Parallel Script Only |
|-----------|----------|-------------|---------------------|
| `resourceGroup` | Yes | Name of the resource group containing the storage account | |
| `storageAccount` | Yes | Name of the storage account to analyze | |
| `retentionDays` | Yes | Proposed retention period in days (blobs older than this will be flagged for deletion) | |
| `exportPath` | No | Custom path for CSV export (defaults to `%TEMP%\storage_audit_[timestamp].csv`) | |
| `ThrottleLimit` | No | Number of containers to process in parallel (default: 5, **max 10 recommended**, range: 1-15) | ✓ |
| `TimeoutMinutes` | No | Timeout in minutes for each container (default: 30). Prevents hanging on Azure throttling | ✓ |
| `ShowDetailedOutput` | No | Display detailed output for each container as processed | ✓ |

## Performance Comparison

| Containers | Original Script | Parallel (5 threads) | Speed Improvement |
|-----------|----------------|---------------------|-------------------|
| 10        | ~2 minutes     | ~30 seconds         | **4x faster** |
| 50        | ~10 minutes    | ~2.5 minutes        | **4x faster** |
| 100       | ~20 minutes    | ~5 minutes          | **4x faster** |
| 500       | ~2 hours       | ~25 minutes         | **5-8x faster** |

**Which script should you use?**
- **Use parallel script** if you have PowerShell 7+ and 10+ containers
- **Use original script** if on PowerShell 5.1 or prefer sequential processing

## Output

The script generates three types of output:

### 1. Console Output
Rich, color-coded analysis displayed in real-time showing:
- Per-container analysis with age distribution
- Impact summary
- Cost savings estimates

### 2. CSV Report
Detailed spreadsheet with columns:
- Container name
- Total blob count and size
- Blobs/size to delete
- Percentage to delete
- Estimated monthly savings

### 3. Summary Text Report
Executive summary including:
- Overall statistics
- Impact analysis
- Cost savings breakdown
- Top 5 containers by deletion size

## Example Output

```
==========================================
Storage Account Lifecycle Policy Audit
==========================================
Account: mystorageaccount
Retention Period: 90 days
Report Date: 02/10/2025 16:42:00

Analysing containers...

Container: backups
  Total Blobs: 1,245
  Total Size: 125.43 GB
  Age Distribution:
    0-7 days: 50 blobs (5.2 GB)
    8-30 days: 120 blobs (12.5 GB)
    31-60 days: 180 blobs (18.9 GB)
    91-180 days: 450 blobs (47.2 GB)
    365+ days: 445 blobs (41.63 GB)
  Impact of 90-day retention:
    Blobs to delete: 895
    Size to delete: 88.83 GB

==========================================
SUMMARY REPORT
==========================================
Total Current Storage:
  Blob Count: 1,245
  Total Size: 125.43 GB

Impact of 90-Day Retention Policy:
  Blobs to be deleted: 895
  Storage to be freed: 88.83 GB
  Percentage of data affected: 70.8%

Cost Analysis:
  Estimated Monthly Savings: £1.63
  Estimated Annual Savings: £19.59

Detailed results exported to: C:\Temp\storage_audit_20250210_164200.csv
Summary report saved to: C:\Temp\storage_audit_20250210_164200_summary.txt

Audit complete!
```

## Use Cases

### Before Implementing Lifecycle Policies
Run this script to understand the impact before applying lifecycle management rules:
- See exactly how much data will be affected
- Identify containers with old data
- Calculate potential savings
- Present findings to stakeholders

### Regular Compliance Audits
Use periodically to:
- Monitor data growth patterns
- Identify storage optimization opportunities
- Track data retention compliance
- Generate reports for management

### Cost Optimization Projects
Essential for:
- Storage cost reduction initiatives
- Cloud spend optimization reviews
- Budget planning and forecasting

## Customization

### Adjusting Cost Calculations
The script uses UK South pricing by default. To adjust for your region, edit line 42:

```powershell
$costPerGBMonth = 0.0184  # Change this to your region's pricing
```

Find your region's pricing at: [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/)

### Custom Age Buckets
To modify age distribution categories, edit the `Group-Object` section (lines 90-98).

## Best Practices

1. **Test on Non-Production First** - Always run on dev/test accounts before production
2. **Review Reports Carefully** - Analyze the age distribution before setting retention policies
3. **Consider Business Requirements** - Align retention days with compliance and business needs
4. **Run Regular Audits** - Schedule periodic audits to track trends
5. **Save Reports** - Keep audit reports for compliance and historical tracking

## Troubleshooting

### "Failed to access storage account"
- Verify you're connected to Azure: `Get-AzContext`
- Ensure you have permissions on the storage account (Reader or higher)
- Check the resource group and storage account names are correct

### "The term 'Get-AzStorageAccount' is not recognized"
- Install/update the Az.Storage module: `Install-Module -Name Az.Storage -Force`

### Performance Issues with Large Storage Accounts
- **Use the parallel script** for storage accounts with many containers
- **Do NOT use ThrottleLimit above 10** - this causes Azure throttling and hangs
- Start with default (5 threads), increase carefully to 8-10 maximum
- If containers timeout, reduce `-ThrottleLimit` to 3-5
- Increase `-TimeoutMinutes` for containers with many blobs
- Consider running during off-peak hours
- Monitor progress via the console output

### Script Hangs or Times Out
If the script hangs at "Get-AzStorageBlob task status" or containers time out:

**Cause:** Using too many parallel threads (> 10) causes Azure to throttle requests

**Solution:**
```powershell
# Reduce throttle limit to 5 or lower
pwsh -ExecutionPolicy Bypass -File .\pre-audit-script-parallel.ps1 `
    -resourceGroup "rg" `
    -storageAccount "sa" `
    -retentionDays 90 `
    -ThrottleLimit 5

# If still timing out, increase timeout and reduce threads
pwsh -ExecutionPolicy Bypass -File .\pre-audit-script-parallel.ps1 `
    -resourceGroup "rg" `
    -storageAccount "sa" `
    -retentionDays 90 `
    -ThrottleLimit 3 `
    -TimeoutMinutes 60
```

**Important:** The script will now automatically skip containers that timeout and continue processing others. Failed containers are listed in the summary.

### "Script requires PowerShell 7.0 or higher"
- The parallel script requires PowerShell 7+
- Install: `winget install Microsoft.PowerShell`
- Or use the original script which supports PowerShell 5.1

### Execution Policy Issues
If you encounter execution policy restrictions:

```powershell
# Option 1: Bypass execution policy for this session only
pwsh -ExecutionPolicy Bypass -File .\pre-audit-script-parallel.ps1 -resourceGroup "rg" -storageAccount "sa" -retentionDays 90

# Option 2: Set execution policy for current user (permanent)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Option 3: Unblock the script file
Unblock-File -Path .\pre-audit-script-parallel.ps1
```

### Ensuring PowerShell 7 is Used
```powershell
# Check current PowerShell version
$PSVersionTable.PSVersion

# Force PowerShell 7 (if installed)
pwsh -File .\pre-audit-script-parallel.ps1 -resourceGroup "rg" -storageAccount "sa" -retentionDays 90

# Combine: Force PowerShell 7 AND bypass execution policy
pwsh -ExecutionPolicy Bypass -File .\pre-audit-script-parallel.ps1 -resourceGroup "rg" -storageAccount "sa" -retentionDays 90
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

[MIT License](LICENSE) - See LICENSE file for details

## Support

For issues, questions, or contributions, please open an issue in the repository.

## Changelog

### Version 1.1.1 (Bug Fix)
- **Fixed:** Script hanging when ThrottleLimit too high (Azure throttling issue)
- Added timeout handling (30 minutes default per container)
- Added validation and warning when ThrottleLimit > 10
- Containers that timeout are now skipped and reported
- Failed containers listed in summary and exported reports
- Improved error handling and progress reporting

### Version 1.1.0
- Added multi-threaded parallel version (4-8x faster)
- Configurable throttle limit for performance tuning
- PowerShell 7+ support for parallel processing

### Version 1.0.0
- Initial release
- Container-level analysis
- Age distribution tracking
- Cost savings calculations
- CSV and text report exports

## Acknowledgments

Built for Azure storage administrators and cloud operations teams to make data lifecycle management decisions easier and more informed.
