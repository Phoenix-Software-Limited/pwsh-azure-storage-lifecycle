# Azure Storage Lifecycle Policy - Pre-Audit Script

A PowerShell tool for analyzing Azure Storage Accounts to assess the impact of implementing lifecycle policies before actual deployment.

## Overview

This script provides detailed analysis of your Azure Storage Account contents, helping you make informed decisions about lifecycle policies by showing:
- Data age distribution across all containers
- Number and size of blobs that would be affected
- Estimated cost savings (monthly and annual)
- Detailed reports in multiple formats

## Features

- 📊 **Age Distribution Analysis** - Categorizes blobs into age groups (0-7 days, 8-30 days, 31-60 days, etc.)
- 💰 **Cost Impact Analysis** - Calculates potential monthly and annual savings
- 📈 **Container-Level Breakdown** - Detailed analysis for each container
- 📄 **Multiple Export Formats** - CSV for detailed data, TXT for executive summaries
- 🎨 **Rich Console Output** - Color-coded, progress-tracked analysis
- ⚡ **Safe & Read-Only** - No modifications to your storage account

## Requirements

- **PowerShell**: 7.0 or higher (recommended) or Windows PowerShell 5.1
- **Azure PowerShell Modules**:
  - `Az.Accounts` (version 2.10.0 or higher)
  - `Az.Storage` (version 5.0.0 or higher)

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

### Basic Usage

```powershell
.\pre-audit-script.ps1 `
    -resourceGroup "myResourceGroup" `
    -storageAccount "mystorageaccount" `
    -retentionDays 90
```

### With Custom Export Path

```powershell
.\pre-audit-script.ps1 `
    -resourceGroup "myResourceGroup" `
    -storageAccount "mystorageaccount" `
    -retentionDays 90 `
    -exportPath "C:\Reports\audit.csv"
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `resourceGroup` | Yes | Name of the resource group containing the storage account |
| `storageAccount` | Yes | Name of the storage account to analyze |
| `retentionDays` | Yes | Proposed retention period in days (blobs older than this will be flagged for deletion) |
| `exportPath` | No | Custom path for CSV export (defaults to `%TEMP%\storage_audit_[timestamp].csv`) |

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
- The script may take time on accounts with millions of blobs
- Consider running during off-peak hours
- Monitor progress via the console output

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

[MIT License](LICENSE) - See LICENSE file for details

## Support

For issues, questions, or contributions, please open an issue in the repository.

## Changelog

### Version 1.0.0
- Initial release
- Container-level analysis
- Age distribution tracking
- Cost savings calculations
- CSV and text report exports

## Acknowledgments

Built for Azure storage administrators and cloud operations teams to make data lifecycle management decisions easier and more informed.
