   <#
   .SYNOPSIS
       Azure Storage Lifecycle Policy - Pre-Implementation Audit Script
       
       REQUIREMENTS:
       - PowerShell 7.0 or higher (recommended) or Windows PowerShell 5.1
       - Az.Accounts module (version 2.10.0 or higher)
       - Az.Storage module (version 5.0.0 or higher)
       
       INSTALLATION:
       Install the required Azure PowerShell modules by running:
           Install-Module -Name Az.Accounts -MinimumVersion 2.10.0 -Scope CurrentUser -Force
           Install-Module -Name Az.Storage -MinimumVersion 5.0.0 -Scope CurrentUser -Force
       
       Then authenticate to Azure:
           Connect-AzAccount
       
       USAGE:
       Run the script with required parameters:
           .\pre-audit-script.ps1 -resourceGroup "myResourceGroup" -storageAccount "mystorageaccount" -retentionDays 90
       
       Optional: Specify custom export path:
           .\pre-audit-script.ps1 -resourceGroup "myResourceGroup" -storageAccount "mystorageaccount" -retentionDays 90 -exportPath "C:\Reports\audit.csv"
       
       The script will:
       1. Connect to the specified storage account
       2. Analyze all blob containers and their age distribution
       3. Calculate impact of the proposed retention policy
       4. Display detailed console output with cost analysis
       5. Export results to CSV and summary text files
       
   .DESCRIPTION
       Analyses storage account contents to determine impact of lifecycle policies
       Generates detailed report of data age distribution and potential savings
   .PARAMETER resourceGroup
       Name of the resource group containing the storage account
   .PARAMETER storageAccount
       Name of the storage account to analyse
   .PARAMETER retentionDays
       Proposed retention period in days
   .PARAMETER exportPath
       Path to export CSV results (optional)
   #>

   param(
       [Parameter(Mandatory=$true)]
       [string]$resourceGroup,
       
       [Parameter(Mandatory=$true)]
       [string]$storageAccount,
       
       [Parameter(Mandatory=$true)]
       [int]$retentionDays,
       
       [string]$exportPath = "$env:TEMP\storage_audit_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
   )

   # Cost per GB per month for hot tier (adjust based on region)
   $costPerGBMonth = 0.0184  # UK South pricing as example

   Write-Host "==========================================" -ForegroundColor Cyan
   Write-Host "Storage Account Lifecycle Policy Audit" -ForegroundColor Cyan
   Write-Host "==========================================" -ForegroundColor Cyan
   Write-Host "Account: $storageAccount"
   Write-Host "Retention Period: $retentionDays days"
   Write-Host "Report Date: $(Get-Date)"
   Write-Host ""

   # Get storage context
   try {
       $ctx = (Get-AzStorageAccount -ResourceGroupName $resourceGroup `
           -Name $storageAccount -ErrorAction Stop).Context
   }
   catch {
       Write-Error "Failed to access storage account: $_"
       exit 1
   }

   # Get all containers
   $containers = Get-AzStorageContainer -Context $ctx

   # Initialize summary variables
   $totalCurrentSize = 0
   $totalCurrentCount = 0
   $totalDeletionSize = 0
   $totalDeletionCount = 0
   $containerResults = @()

   Write-Host "Analysing containers..." -ForegroundColor Yellow

   foreach ($container in $containers) {
       Write-Progress -Activity "Analysing Storage" -Status "Container: $($container.Name)" `
           -PercentComplete (($containers.IndexOf($container) / $containers.Count) * 100)
       
       $blobs = Get-AzStorageBlob -Container $container.Name -Context $ctx
       
       # Skip if container is empty
       if ($blobs.Count -eq 0) {
           continue
       }
       
       # Calculate container totals
       $containerSize = ($blobs | Measure-Object -Property Length -Sum).Sum
       $containerCount = $blobs.Count
       
       # Age distribution analysis
       $ageGroups = $blobs | Group-Object {
           $age = (Get-Date) - $_.LastModified.DateTime
           if ($age.Days -le 7) { "0-7 days" }
           elseif ($age.Days -le 30) { "8-30 days" }
           elseif ($age.Days -le 60) { "31-60 days" }
           elseif ($age.Days -le 90) { "61-90 days" }
           elseif ($age.Days -le 180) { "91-180 days" }
           elseif ($age.Days -le 365) { "181-365 days" }
           else { "365+ days" }
       }
       
       # Calculate deletion candidates
       $deletionCandidates = $blobs | 
           Where-Object {((Get-Date) - $_.LastModified.DateTime).Days -gt $retentionDays}
       
       $containerDeletionSize = ($deletionCandidates | Measure-Object -Property Length -Sum).Sum
       $containerDeletionCount = $deletionCandidates.Count
       
       # Add to totals
       $totalCurrentSize += $containerSize
       $totalCurrentCount += $containerCount
       $totalDeletionSize += $containerDeletionSize
       $totalDeletionCount += $containerDeletionCount
       
       # Store results for export
       $containerResults += [PSCustomObject]@{
           Container = $container.Name
           TotalBlobCount = $containerCount
           TotalSizeGB = [math]::Round($containerSize / 1GB, 2)
           BlobsToDelete = $containerDeletionCount
           SizeToDeleteGB = [math]::Round($containerDeletionSize / 1GB, 2)
           PercentToDelete = if ($containerCount -gt 0) { 
               [math]::Round(($containerDeletionCount / $containerCount) * 100, 1) 
           } else { 0 }
           EstMonthlySavings = [math]::Round(($containerDeletionSize / 1GB) * $costPerGBMonth, 2)
       }
       
       # Display container summary
       Write-Host ""
       Write-Host "Container: $($container.Name)" -ForegroundColor Green
       Write-Host "  Total Blobs: $containerCount"
       Write-Host "  Total Size: $([math]::Round($containerSize / 1GB, 2)) GB"
       
       if ($ageGroups) {
           Write-Host "  Age Distribution:" -ForegroundColor Gray
           foreach ($group in $ageGroups | Sort-Object Name) {
               $groupSize = ($group.Group | Measure-Object -Property Length -Sum).Sum
               Write-Host "    $($group.Name): $($group.Count) blobs ($([math]::Round($groupSize / 1GB, 2)) GB)"
           }
       }
       
       Write-Host "  Impact of $retentionDays-day retention:" -ForegroundColor Yellow
       Write-Host "    Blobs to delete: $containerDeletionCount"
       Write-Host "    Size to delete: $([math]::Round($containerDeletionSize / 1GB, 2)) GB"
   }

   Write-Progress -Activity "Analysing Storage" -Completed

   # Display summary
   Write-Host ""
   Write-Host "==========================================" -ForegroundColor Cyan
   Write-Host "SUMMARY REPORT" -ForegroundColor Cyan
   Write-Host "==========================================" -ForegroundColor Cyan
   Write-Host "Total Current Storage:"
   Write-Host "  Blob Count: $totalCurrentCount"
   Write-Host "  Total Size: $([math]::Round($totalCurrentSize / 1GB, 2)) GB"
   Write-Host ""
   Write-Host "Impact of $retentionDays-Day Retention Policy:" -ForegroundColor Yellow
   Write-Host "  Blobs to be deleted: $totalDeletionCount"
   Write-Host "  Storage to be freed: $([math]::Round($totalDeletionSize / 1GB, 2)) GB"
   Write-Host "  Percentage of data affected: $([math]::Round(($totalDeletionSize / $totalCurrentSize) * 100, 1))%"
   Write-Host ""
   Write-Host "Cost Analysis:" -ForegroundColor Green
   $monthlySavings = ($totalDeletionSize / 1GB) * $costPerGBMonth
   Write-Host "  Estimated Monthly Savings: £$([math]::Round($monthlySavings, 2))"
   Write-Host "  Estimated Annual Savings: £$([math]::Round($monthlySavings * 12, 2))"
   Write-Host ""

   # Export results to CSV
   if ($containerResults.Count -gt 0) {
       $containerResults | Export-Csv -Path $exportPath -NoTypeInformation
       Write-Host "Detailed results exported to: $exportPath" -ForegroundColor Green
       
       # Also create summary file
       $summaryPath = $exportPath.Replace('.csv', '_summary.txt')
       @"
Storage Account Lifecycle Policy Audit Summary
==============================================
Date: $(Get-Date)
Storage Account: $storageAccount
Resource Group: $resourceGroup
Proposed Retention: $retentionDays days

Current State:
- Total Containers: $($containers.Count)
- Total Blobs: $totalCurrentCount
- Total Size: $([math]::Round($totalCurrentSize / 1GB, 2)) GB

Impact Analysis:
- Blobs to Delete: $totalDeletionCount
- Size to Free: $([math]::Round($totalDeletionSize / 1GB, 2)) GB
- Data Affected: $([math]::Round(($totalDeletionSize / $totalCurrentSize) * 100, 1))%

Cost Savings:
- Monthly: £$([math]::Round($monthlySavings, 2))
- Annual: £$([math]::Round($monthlySavings * 12, 2))

Top Containers by Deletion Size:
$($containerResults | Sort-Object SizeToDeleteGB -Descending | Select-Object -First 5 | Format-Table -AutoSize | Out-String)
"@ | Out-File -FilePath $summaryPath
       
       Write-Host "Summary report saved to: $summaryPath" -ForegroundColor Green
   }

   Write-Host ""
   Write-Host "Audit complete!" -ForegroundColor Cyan
