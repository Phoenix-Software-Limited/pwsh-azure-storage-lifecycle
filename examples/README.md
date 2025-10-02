# Usage Examples

This directory contains practical examples of using the Azure Storage Lifecycle Pre-Audit Script in various scenarios.

## Example 1: Basic Audit with 90-Day Retention

**Scenario**: You want to analyze a production storage account to see the impact of a 90-day retention policy.

```powershell
# Connect to Azure
Connect-AzAccount

# Run the audit
.\pre-audit-script.ps1 `
    -resourceGroup "prod-rg-westeurope" `
    -storageAccount "prodstorageacct001" `
    -retentionDays 90
```

**Expected Output**:
- Console report showing all containers
- CSV file in `%TEMP%` directory
- Summary text file with top containers

---

## Example 2: Conservative 180-Day Retention

**Scenario**: Testing a more conservative retention policy for compliance reasons.

```powershell
.\pre-audit-script.ps1 `
    -resourceGroup "compliance-rg" `
    -storageAccount "compliancestorage" `
    -retentionDays 180
```

**Use Case**: Organizations with strict data retention requirements that need to keep data longer.

---

## Example 3: Aggressive 30-Day Retention

**Scenario**: Temporary data storage with aggressive cleanup for cost optimization.

```powershell
.\pre-audit-script.ps1 `
    -resourceGroup "dev-rg" `
    -storageAccount "devtempstorage" `
    -retentionDays 30
```

**Use Case**: Development/test environments where data becomes stale quickly.

---

## Example 4: Custom Export Path

**Scenario**: Saving reports to a specific network location for documentation.

```powershell
.\pre-audit-script.ps1 `
    -resourceGroup "audit-rg" `
    -storageAccount "auditstorageacct" `
    -retentionDays 90 `
    -exportPath "\\fileserver\reports\storage-audit-$(Get-Date -Format 'yyyy-MM-dd').csv"
```

**Use Case**: Centralized report storage for compliance or management review.

---

## Example 5: Multiple Storage Accounts

**Scenario**: Auditing multiple storage accounts in sequence.

```powershell
# Define storage accounts to audit
$storageAccounts = @(
    @{RG = "prod-rg-1"; Account = "prodstore1"; Retention = 90},
    @{RG = "prod-rg-2"; Account = "prodstore2"; Retention = 90},
    @{RG = "archive-rg"; Account = "archivestore"; Retention = 365}
)

# Create reports directory
$reportDir = "C:\AuditReports\$(Get-Date -Format 'yyyy-MM-dd')"
New-Item -Path $reportDir -ItemType Directory -Force

# Loop through and audit each account
foreach ($sa in $storageAccounts) {
    Write-Host "`n=== Auditing $($sa.Account) ===" -ForegroundColor Cyan
    
    .\pre-audit-script.ps1 `
        -resourceGroup $sa.RG `
        -storageAccount $sa.Account `
        -retentionDays $sa.Retention `
        -exportPath "$reportDir\$($sa.Account)_audit.csv"
    
    Start-Sleep -Seconds 2  # Brief pause between accounts
}

Write-Host "`nAll audits complete! Reports saved to: $reportDir" -ForegroundColor Green
```

**Use Case**: Monthly audits across your entire Azure environment.

---

## Example 6: Different Retention Periods Comparison

**Scenario**: Compare the impact of different retention periods on the same storage account.

```powershell
$storageRG = "analysis-rg"
$storageAccount = "analysisstorage"
$retentionPeriods = @(30, 60, 90, 180, 365)
$reportDir = "C:\RetentionAnalysis"

New-Item -Path $reportDir -ItemType Directory -Force

foreach ($days in $retentionPeriods) {
    Write-Host "`n=== Testing $days-day retention ===" -ForegroundColor Yellow
    
    .\pre-audit-script.ps1 `
        -resourceGroup $storageRG `
        -storageAccount $storageAccount `
        -retentionDays $days `
        -exportPath "$reportDir\retention_${days}days.csv"
}

Write-Host "`nAnalysis complete! Compare the reports in: $reportDir" -ForegroundColor Green
```

**Use Case**: Data-driven decision making for optimal retention period.

---

## Example 7: Scheduled Monthly Audit

**Scenario**: Create a scheduled task to run monthly audits automatically.

### Script: `monthly-audit.ps1`

```powershell
# Monthly Audit Script
param(
    [string]$resourceGroup = "prod-rg",
    [string]$storageAccount = "prodstorage",
    [int]$retentionDays = 90
)

# Set up logging
$logPath = "C:\AuditLogs\monthly-audit-$(Get-Date -Format 'yyyy-MM').log"
Start-Transcript -Path $logPath

try {
    Write-Host "Starting monthly storage audit - $(Get-Date)"
    
    # Connect to Azure (assumes managed identity or stored credentials)
    Connect-AzAccount -Identity
    
    # Run audit
    $exportPath = "C:\AuditReports\Monthly\storage-audit-$(Get-Date -Format 'yyyy-MM-dd').csv"
    
    .\pre-audit-script.ps1 `
        -resourceGroup $resourceGroup `
        -storageAccount $storageAccount `
        -retentionDays $retentionDays `
        -exportPath $exportPath
    
    Write-Host "Audit completed successfully!"
}
catch {
    Write-Error "Audit failed: $_"
    # Optionally send alert email
}
finally {
    Stop-Transcript
}
```

### Windows Task Scheduler Setup:

```powershell
# Create scheduled task
$action = New-ScheduledTaskAction `
    -Execute 'pwsh.exe' `
    -Argument '-File "C:\Scripts\monthly-audit.ps1"'

$trigger = New-ScheduledTaskTrigger `
    -Weekly `
    -WeeksInterval 4 `
    -DaysOfWeek Monday `
    -At 2am

$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName "Monthly Storage Audit" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Description "Monthly audit of Azure storage lifecycle impact"
```

---

## Example 8: Pre-Production Validation

**Scenario**: Before implementing lifecycle policies in production, test on a copy of the data.

```powershell
# Step 1: Audit production to understand impact
Write-Host "Step 1: Auditing production storage..." -ForegroundColor Cyan

.\pre-audit-script.ps1 `
    -resourceGroup "prod-rg" `
    -storageAccount "prodstorage" `
    -retentionDays 90 `
    -exportPath "C:\Validation\prod-audit.csv"

# Step 2: Review results
Write-Host "`nStep 2: Review the audit results before proceeding" -ForegroundColor Yellow
Write-Host "Check: C:\Validation\prod-audit.csv" -ForegroundColor Yellow
Read-Host "Press Enter when ready to continue"

# Step 3: If satisfied, document the decision
$decision = Read-Host "Proceed with lifecycle policy? (yes/no)"

if ($decision -eq "yes") {
    Write-Host "`nLifecycle policy approved for implementation" -ForegroundColor Green
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Implement policy in Azure Portal or via ARM template"
    Write-Host "2. Monitor impact for first week"
    Write-Host "3. Run audit again after 30 days to verify"
}
else {
    Write-Host "`nImplementation cancelled. Review audit results and adjust retention period." -ForegroundColor Red
}
```

---

## Example 9: Cost Optimization Report for Management

**Scenario**: Generate an executive summary for management review.

```powershell
# Audit multiple tiers
$accounts = @(
    @{Name = "Hot Tier Storage"; RG = "prod-rg"; Account = "prodhotstorage"},
    @{Name = "Backup Storage"; RG = "backup-rg"; Account = "backupstorage"},
    @{Name = "Archive Storage"; RG = "archive-rg"; Account = "archivestorage"}
)

$reportPath = "C:\ExecutiveReports\Storage-Optimization-$(Get-Date -Format 'yyyy-MM-dd').txt"
$retentionDays = 90

# Header
@"
==================================================
STORAGE COST OPTIMIZATION ANALYSIS
==================================================
Date: $(Get-Date -Format "MMMM dd, yyyy")
Analyst: $env:USERNAME
Retention Period Analyzed: $retentionDays days

EXECUTIVE SUMMARY
==================================================
"@ | Out-File -FilePath $reportPath

$totalSavings = 0

foreach ($account in $accounts) {
    Write-Host "`nAnalyzing: $($account.Name)" -ForegroundColor Cyan
    
    $csvPath = "$env:TEMP\$($account.Account)_temp.csv"
    
    .\pre-audit-script.ps1 `
        -resourceGroup $account.RG `
        -storageAccount $account.Account `
        -retentionDays $retentionDays `
        -exportPath $csvPath
    
    # Extract savings from CSV
    $data = Import-Csv $csvPath
    $accountSavings = ($data | Measure-Object -Property EstMonthlySavings -Sum).Sum
    $totalSavings += $accountSavings
    
    # Add to report
    @"

$($account.Name):
- Storage Account: $($account.Account)
- Estimated Monthly Savings: £$([math]::Round($accountSavings, 2))
- Estimated Annual Savings: £$([math]::Round($accountSavings * 12, 2))
"@ | Out-File -FilePath $reportPath -Append
}

# Summary
@"

TOTAL COST OPTIMIZATION OPPORTUNITY
Total Monthly Savings: £$([math]::Round($totalSavings, 2))
Total Annual Savings: £$([math]::Round($totalSavings * 12, 2))

RECOMMENDATION
Implement lifecycle policies with $retentionDays-day retention
across all storage accounts to realize these savings.

"@ | Out-File -FilePath $reportPath -Append

Write-Host "`nExecutive report generated: $reportPath" -ForegroundColor Green
```

**Use Case**: Presenting cost optimization opportunities to leadership.

---

## Example 10: Integration with Azure Automation

**Scenario**: Running the script as an Azure Automation Runbook.

### Runbook Script:

```powershell
<#
.SYNOPSIS
    Azure Automation Runbook for Storage Lifecycle Audits
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$false)]
    [int]$RetentionDays = 90,
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountForReports = "reportsstorage",
    
    [Parameter(Mandatory=$false)]
    [string]$ReportContainer = "audit-reports"
)

# Authenticate using Managed Identity
Connect-AzAccount -Identity

# Download script from storage or use inline
$scriptContent = @'
# Paste the content of pre-audit-script.ps1 here
'@

# Create temporary script file
$tempScript = "$env:TEMP\audit-script.ps1"
$scriptContent | Out-File -FilePath $tempScript

# Run the audit
$reportPath = "$env:TEMP\audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

& $tempScript `
    -resourceGroup $ResourceGroupName `
    -storageAccount $StorageAccountName `
    -retentionDays $RetentionDays `
    -exportPath $reportPath

# Upload report to storage account
$ctx = (Get-AzStorageAccount -ResourceGroupName "reports-rg" `
    -Name $StorageAccountForReports).Context

Set-AzStorageBlobContent `
    -File $reportPath `
    -Container $ReportContainer `
    -Blob "audit-reports/$(Get-Date -Format 'yyyy-MM')/$(Split-Path $reportPath -Leaf)" `
    -Context $ctx `
    -Force

Write-Output "Audit complete. Report uploaded to blob storage."

# Cleanup
Remove-Item $tempScript, $reportPath -ErrorAction SilentlyContinue
```

---

## Tips for Effective Usage

### 1. **Start Conservative**
Begin with longer retention periods (180+ days) and gradually decrease as you understand your data patterns.

### 2. **Run Multiple Scenarios**
Test 30, 60, 90, 180, and 365-day retention periods to find the optimal balance.

### 3. **Document Decisions**
Keep audit reports as documentation for compliance and future reference.

### 4. **Schedule Regular Audits**
Run monthly or quarterly to track data growth and optimization opportunities.

### 5. **Consider Data Types**
Different containers may need different retention periods:
- Logs: 30-90 days
- Backups: 180-365 days
- Archives: 365+ days
- Application data: Varies by compliance requirements

### 6. **Review Before Implementation**
Always review the age distribution and understand what data will be deleted before implementing policies.

### 7. **Test in Non-Production First**
Validate your retention settings on dev/test environments before applying to production.

## Troubleshooting Common Scenarios

### Large Storage Accounts
For accounts with millions of blobs:
```powershell
# Run during off-peak hours
.\pre-audit-script.ps1 `
    -resourceGroup "large-rg" `
    -storageAccount "largestorageacct" `
    -retentionDays 90 | Tee-Object -FilePath "audit-progress.log"
```

### Multiple Subscriptions
```powershell
$subscriptions = Get-AzSubscription

foreach ($sub in $subscriptions) {
    Set-AzContext -SubscriptionId $sub.Id
    
    # Run audits for this subscription
    $storageAccounts = Get-AzStorageAccount
    
    foreach ($sa in $storageAccounts) {
        Write-Host "Auditing: $($sa.StorageAccountName) in $($sub.Name)"
        # Run audit...
    }
}
```

## Additional Resources

- [Azure Storage Lifecycle Management](https://docs.microsoft.com/azure/storage/blobs/lifecycle-management-overview)
- [Azure Storage Pricing](https://azure.microsoft.com/pricing/details/storage/blobs/)
- [Blob Storage Tiers](https://docs.microsoft.com/azure/storage/blobs/access-tiers-overview)

---

For more information, see the main [README.md](../README.md) in the repository root.
