<#
.SYNOPSIS
    Azure Storage Lifecycle Policy - Pre-Implementation Audit Script (Multi-Threaded Version)
    Version: 1.1.1
    
    REQUIREMENTS:
    - PowerShell 7.0 or higher (REQUIRED for parallel processing)
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
        .\pre-audit-script-parallel.ps1 -resourceGroup "myResourceGroup" -storageAccount "mystorageaccount" -retentionDays 90
    
    Optional: Specify custom export path and parallelism:
        .\pre-audit-script-parallel.ps1 -resourceGroup "myResourceGroup" -storageAccount "mystorageaccount" -retentionDays 90 -exportPath "C:\Reports\audit.csv" -ThrottleLimit 5
    
    The script will:
    1. Connect to the specified storage account
    2. Analyze all blob containers in parallel for maximum efficiency
    3. Calculate impact of the proposed retention policy
    4. Display detailed console output with cost analysis
    5. Export results to CSV and summary text files
    
    PERFORMANCE IMPROVEMENTS:
    - Processes multiple containers simultaneously using PowerShell 7 parallel processing
    - Significantly faster for storage accounts with many containers
    - Configurable throttle limit to control resource usage (default: 5, max recommended: 10)
    - Thread-safe data collection
    - Timeout handling to prevent hanging on Azure throttling
    
.DESCRIPTION
    Analyses storage account contents to determine impact of lifecycle policies
    Generates detailed report of data age distribution and potential savings
    Uses parallel processing for optimal performance
.PARAMETER resourceGroup
    Name of the resource group containing the storage account
.PARAMETER storageAccount
    Name of the storage account to analyse
.PARAMETER retentionDays
    Proposed retention period in days
.PARAMETER exportPath
    Path to export CSV results (optional)
.PARAMETER ThrottleLimit
    Maximum number of containers to process in parallel (default: 5, max recommended: 10)
    WARNING: Values above 10 may cause Azure throttling and script hangs
.PARAMETER TimeoutMinutes
    Timeout in minutes for processing each container (default: 30)
.PARAMETER ShowDetailedOutput
    Display detailed output for each container (default: false for cleaner output in parallel mode)
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$resourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$storageAccount,
    
    [Parameter(Mandatory=$true)]
    [int]$retentionDays,
    
    [string]$exportPath = "$env:TEMP\storage_audit_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",
    
    [ValidateRange(1, 15)]
    [int]$ThrottleLimit = 5,
    
    [int]$TimeoutMinutes = 30,
    
    [switch]$ShowDetailedOutput
)

# Verify PowerShell 7+ for parallel support
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "This script requires PowerShell 7.0 or higher for parallel processing. Current version: $($PSVersionTable.PSVersion)"
    Write-Host "Please use the original pre-audit-script.ps1 for PowerShell 5.1 compatibility, or upgrade to PowerShell 7+" -ForegroundColor Yellow
    exit 1
}

# Warn if throttle limit is too high
if ($ThrottleLimit -gt 10) {
    Write-Warning "ThrottleLimit of $ThrottleLimit may cause Azure throttling. Recommended maximum is 10."
    Write-Host "Press Ctrl+C to cancel, or wait 5 seconds to continue..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
}

# Cost per GB per month for hot tier (adjust based on region)
$costPerGBMonth = 0.0184  # UK South pricing as example

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Storage Account Lifecycle Policy Audit" -ForegroundColor Cyan
Write-Host "(Multi-Threaded Version)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Account: $storageAccount"
Write-Host "Retention Period: $retentionDays days"
Write-Host "Parallel Threads: $ThrottleLimit"
Write-Host "Timeout: $TimeoutMinutes minutes per container"
Write-Host "Report Date: $(Get-Date)"
Write-Host ""

# Get storage context
try {
    $storageAccountObj = Get-AzStorageAccount -ResourceGroupName $resourceGroup `
        -Name $storageAccount -ErrorAction Stop
    $ctx = $storageAccountObj.Context
}
catch {
    Write-Error "Failed to access storage account: $_"
    exit 1
}

# Get all containers
Write-Host "Retrieving container list..." -ForegroundColor Yellow
$containers = Get-AzStorageContainer -Context $ctx

if ($containers.Count -eq 0) {
    Write-Host "No containers found in storage account." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($containers.Count) containers. Starting parallel analysis..." -ForegroundColor Yellow
Write-Host ""

# Track progress
$script:processedCount = 0
$script:totalContainers = $containers.Count
$script:failedContainers = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

# Process containers in parallel
$containerResults = $containers | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
    # Import required variables into parallel scope
    $container = $_
    $retentionDays = $using:retentionDays
    $costPerGBMonth = $using:costPerGBMonth
    $ShowDetailedOutput = $using:ShowDetailedOutput
    $ctx = $using:ctx
    $processedCount = $using:processedCount
    $totalContainers = $using:totalContainers
    $TimeoutMinutes = $using:TimeoutMinutes
    $failedContainers = $using:failedContainers
    
    $containerName = $container.Name
    
    try {
        # Create a script block for the blob retrieval with timeout
        $getBlobsScript = {
            param($ContainerName, $Context)
            try {
                $blobs = Get-AzStorageBlob -Container $ContainerName -Context $Context -ErrorAction Stop
                return $blobs
            }
            catch {
                throw "Failed to get blobs: $_"
            }
        }
        
        # Execute with timeout using Start-Job (more reliable than runspaces for Azure cmdlets)
        $job = Start-Job -ScriptBlock $getBlobsScript -ArgumentList $containerName, $ctx
        
        # Wait for job with timeout
        $timeoutSeconds = $TimeoutMinutes * 60
        $completed = Wait-Job -Job $job -Timeout $timeoutSeconds
        
        if ($null -eq $completed) {
            # Job timed out
            Stop-Job -Job $job
            Remove-Job -Job $job -Force
            Write-Warning "Container '$containerName' timed out after $TimeoutMinutes minutes (possible Azure throttling). Skipping..."
            $failedContainers.Add($containerName)
            return $null
        }
        
        # Get the results
        $blobs = Receive-Job -Job $job
        Remove-Job -Job $job
        
        # Check if job had errors
        if ($job.State -eq 'Failed') {
            Write-Warning "Container '$containerName' failed: $($job.ChildJobs[0].JobStateInfo.Reason.Message)"
            $failedContainers.Add($containerName)
            return $null
        }
        
        # Skip if container is empty
        if ($null -eq $blobs -or $blobs.Count -eq 0) {
            $null = ([ref]$processedCount).Value++
            $percent = [math]::Round((([ref]$processedCount).Value / $totalContainers) * 100, 0)
            Write-Host "Progress: $percent% ($($([ref]$processedCount).Value)/$totalContainers) - Completed: $containerName (empty)" -ForegroundColor Gray
            return $null
        }
        
        # Calculate container totals
        $containerSize = ($blobs | Measure-Object -Property Length -Sum).Sum
        $containerCount = $blobs.Count
        
        # Age distribution analysis
        $currentDate = Get-Date
        $ageGroups = $blobs | Group-Object {
            $age = $currentDate - $_.LastModified.DateTime
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
            Where-Object {($currentDate - $_.LastModified.DateTime).Days -gt $retentionDays}
        
        $containerDeletionSize = ($deletionCandidates | Measure-Object -Property Length -Sum).Sum
        $containerDeletionCount = $deletionCandidates.Count
        
        # Create result object
        $result = [PSCustomObject]@{
            Container = $containerName
            TotalBlobCount = $containerCount
            TotalSizeGB = [math]::Round($containerSize / 1GB, 2)
            BlobsToDelete = $containerDeletionCount
            SizeToDeleteGB = [math]::Round($containerDeletionSize / 1GB, 2)
            PercentToDelete = if ($containerCount -gt 0) { 
                [math]::Round(($containerDeletionCount / $containerCount) * 100, 1) 
            } else { 0 }
            EstMonthlySavings = [math]::Round(($containerDeletionSize / 1GB) * $costPerGBMonth, 2)
            # Include additional data for detailed output
            _TotalSize = $containerSize
            _DeletionSize = $containerDeletionSize
            _AgeGroups = $ageGroups
        }
        
        # Display detailed output if requested
        if ($ShowDetailedOutput) {
            Write-Host ""
            Write-Host "Container: $containerName" -ForegroundColor Green
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
        
        # Update progress counter
        $null = ([ref]$processedCount).Value++
        $percent = [math]::Round((([ref]$processedCount).Value / $totalContainers) * 100, 0)
        Write-Host "Progress: $percent% ($($([ref]$processedCount).Value)/$totalContainers) - Completed: $containerName" -ForegroundColor Gray
        
        return $result
    }
    catch {
        Write-Warning "Error processing container '$containerName': $_"
        $failedContainers.Add($containerName)
        return $null
    }
} | Where-Object { $_ -ne $null }

Write-Host ""
if ($failedContainers.Count -gt 0) {
    Write-Host "WARNING: $($failedContainers.Count) containers failed or timed out:" -ForegroundColor Yellow
    $failedContainers | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host ""
}

Write-Host "Container analysis complete. Calculating totals..." -ForegroundColor Yellow

# Calculate totals from results
$totalCurrentSize = ($containerResults | Measure-Object -Property _TotalSize -Sum).Sum
$totalCurrentCount = ($containerResults | Measure-Object -Property TotalBlobCount -Sum).Sum
$totalDeletionSize = ($containerResults | Measure-Object -Property _DeletionSize -Sum).Sum
$totalDeletionCount = ($containerResults | Measure-Object -Property BlobsToDelete -Sum).Sum

# Display summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SUMMARY REPORT" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Total Current Storage:"
Write-Host "  Containers Analyzed: $($containerResults.Count) of $($containers.Count)"
if ($failedContainers.Count -gt 0) {
    Write-Host "  Containers Failed/Skipped: $($failedContainers.Count)" -ForegroundColor Yellow
}
Write-Host "  Blob Count: $totalCurrentCount"
Write-Host "  Total Size: $([math]::Round($totalCurrentSize / 1GB, 2)) GB"
Write-Host ""
Write-Host "Impact of $retentionDays-Day Retention Policy:" -ForegroundColor Yellow
Write-Host "  Blobs to be deleted: $totalDeletionCount"
Write-Host "  Storage to be freed: $([math]::Round($totalDeletionSize / 1GB, 2)) GB"
if ($totalCurrentSize -gt 0) {
    Write-Host "  Percentage of data affected: $([math]::Round(($totalDeletionSize / $totalCurrentSize) * 100, 1))%"
}
Write-Host ""
Write-Host "Cost Analysis:" -ForegroundColor Green
$monthlySavings = ($totalDeletionSize / 1GB) * $costPerGBMonth
Write-Host "  Estimated Monthly Savings: £$([math]::Round($monthlySavings, 2))"
Write-Host "  Estimated Annual Savings: £$([math]::Round($monthlySavings * 12, 2))"
Write-Host ""

# Display top containers by deletion size
if ($containerResults.Count -gt 0) {
    Write-Host "Top 10 Containers by Deletion Size:" -ForegroundColor Yellow
    $containerResults | 
        Sort-Object SizeToDeleteGB -Descending | 
        Select-Object -First 10 Container, TotalBlobCount, TotalSizeGB, BlobsToDelete, SizeToDeleteGB, PercentToDelete |
        Format-Table -AutoSize
}

# Export results to CSV
if ($containerResults.Count -gt 0) {
    # Remove internal fields before export
    $exportResults = $containerResults | Select-Object -Property Container, TotalBlobCount, TotalSizeGB, 
        BlobsToDelete, SizeToDeleteGB, PercentToDelete, EstMonthlySavings
    
    $exportResults | Export-Csv -Path $exportPath -NoTypeInformation
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
Processing Mode: Multi-threaded (Throttle Limit: $ThrottleLimit)
Timeout: $TimeoutMinutes minutes per container

Current State:
- Total Containers: $($containers.Count)
- Containers Analyzed: $($containerResults.Count)
$(if ($failedContainers.Count -gt 0) { "- Containers Failed/Skipped: $($failedContainers.Count)" })
- Total Blobs: $totalCurrentCount
- Total Size: $([math]::Round($totalCurrentSize / 1GB, 2)) GB

Impact Analysis:
- Blobs to Delete: $totalDeletionCount
- Size to Free: $([math]::Round($totalDeletionSize / 1GB, 2)) GB
$(if ($totalCurrentSize -gt 0) { "- Data Affected: $([math]::Round(($totalDeletionSize / $totalCurrentSize) * 100, 1))%" })

Cost Savings:
- Monthly: £$([math]::Round($monthlySavings, 2))
- Annual: £$([math]::Round($monthlySavings * 12, 2))

Top Containers by Deletion Size:
$($containerResults | Sort-Object SizeToDeleteGB -Descending | Select-Object -First 10 | Format-Table -AutoSize | Out-String)

$(if ($failedContainers.Count -gt 0) { @"
Failed/Skipped Containers:
$($failedContainers -join "`n")
"@ })
"@ | Out-File -FilePath $summaryPath
    
    Write-Host "Summary report saved to: $summaryPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "Audit complete!" -ForegroundColor Cyan
Write-Host "Performance: Processed $($containerResults.Count) of $($containers.Count) containers using $ThrottleLimit parallel threads" -ForegroundColor Green
if ($failedContainers.Count -gt 0) {
    Write-Host "WARNING: $($failedContainers.Count) containers failed or timed out. Consider reducing ThrottleLimit or increasing TimeoutMinutes." -ForegroundColor Yellow
}
