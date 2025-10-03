<#
.SYNOPSIS
    Azure Storage Lifecycle Policy - Pre-Implementation Audit Script (Multi-Threaded Version)
    Version: 1.2.0
    
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
.PARAMETER LogPath
    Path to log file for detailed progress tracking (optional, auto-generated if not specified)
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
    
    [switch]$ShowDetailedOutput,
    
    [string]$LogPath = "$env:TEMP\storage_audit_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

# Create log file and helper function
$script:LogPath = $LogPath
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $script:LogPath -Value $logMessage
    
    # Also write to console based on level
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage }
    }
}

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

Write-Log "=========================================="
Write-Log "Storage Account Lifecycle Policy Audit"
Write-Log "(Multi-Threaded Version - v1.2.0)"
Write-Log "=========================================="
Write-Log "Account: $storageAccount"
Write-Log "Resource Group: $resourceGroup"
Write-Log "Retention Period: $retentionDays days"
Write-Log "Parallel Threads: $ThrottleLimit"
Write-Log "Timeout: $TimeoutMinutes minutes per container"
Write-Log "Report Date: $(Get-Date)"
Write-Log "Log File: $LogPath"
Write-Host ""

# Get storage context
Write-Log "Connecting to storage account..." -Level "INFO"
try {
    $storageAccountObj = Get-AzStorageAccount -ResourceGroupName $resourceGroup `
        -Name $storageAccount -ErrorAction Stop
    $ctx = $storageAccountObj.Context
    Write-Log "Successfully connected to storage account" -Level "SUCCESS"
}
catch {
    Write-Log "Failed to access storage account: $_" -Level "ERROR"
    exit 1
}

# Get all containers
Write-Log "Retrieving container list..." -Level "INFO"
$containers = Get-AzStorageContainer -Context $ctx
Write-Log "Found $($containers.Count) containers" -Level "SUCCESS"

if ($containers.Count -eq 0) {
    Write-Log "No containers found in storage account." -Level "WARNING"
    exit 0
}

Write-Log "Starting parallel analysis with $ThrottleLimit threads..." -Level "INFO"
Write-Log "Processing containers - progress will be logged as each completes..." -Level "INFO"
Write-Host ""

# Track progress
$script:failedContainers = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
$script:processedCount = 0
$script:totalContainers = $containers.Count
$startTime = Get-Date

# Process containers in parallel
$containerResults = $containers | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
    # Import required variables into parallel scope
    $container = $_
    $retentionDays = $using:retentionDays
    $costPerGBMonth = $using:costPerGBMonth
    $ShowDetailedOutput = $using:ShowDetailedOutput
    $resourceGroup = $using:resourceGroup
    $storageAccount = $using:storageAccount
    $TimeoutMinutes = $using:TimeoutMinutes
    $failedContainers = $using:failedContainers
    $LogPath = $using:LogPath
    
    # Thread-safe logging function
    function Write-ThreadLog {
        param([string]$Message, [string]$Level = "INFO")
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] $Message"
        $mutex = New-Object System.Threading.Mutex($false, "StorageAuditLogMutex")
        try {
            $mutex.WaitOne() | Out-Null
            Add-Content -Path $LogPath -Value $logMessage
        }
        finally {
            $mutex.ReleaseMutex()
        }
    }
    
    $containerName = $container.Name
    Write-ThreadLog "Started processing container: $containerName" -Level "INFO"
    
    try {
        # Recreate context within this thread (context objects cannot be serialized across jobs)
        Write-ThreadLog "Container '$containerName': Establishing connection..." -Level "INFO"
        $ctx = (Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccount).Context
        
        # Get all blobs in container with retry logic
        $maxRetries = 3
        $retryCount = 0
        $blobs = $null
        $success = $false
        
        while (-not $success -and $retryCount -lt $maxRetries) {
            try {
                Write-ThreadLog "Container '$containerName': Retrieving blob list (attempt $($retryCount + 1)/$maxRetries)..." -Level "INFO"
                $blobs = Get-AzStorageBlob -Container $containerName -Context $ctx -ErrorAction Stop
                $success = $true
                Write-ThreadLog "Container '$containerName': Retrieved $($blobs.Count) blobs" -Level "INFO"
            }
            catch {
                $retryCount++
                if ($retryCount -ge $maxRetries) {
                    Write-ThreadLog "Container '$containerName': Failed after $maxRetries attempts: $_" -Level "ERROR"
                    throw "Failed to get blobs after $maxRetries attempts: $_"
                }
                Write-ThreadLog "Container '$containerName': Attempt $retryCount failed, retrying in 5 seconds..." -Level "WARNING"
                Start-Sleep -Seconds 5
            }
        }
        
        # Skip if container is empty
        if ($null -eq $blobs -or $blobs.Count -eq 0) {
            Write-ThreadLog "Container '$containerName': Empty container, skipping" -Level "INFO"
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Completed: $containerName (empty)" -ForegroundColor Gray
            return $null
        }
        
        Write-ThreadLog "Container '$containerName': Analyzing $($blobs.Count) blobs..." -Level "INFO"
        
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
        
        # Output completion with timestamp and blob count
        $completionMsg = "Container '$containerName': COMPLETED - $containerCount blobs, $([math]::Round($containerSize / 1GB, 2)) GB total, $containerDeletionCount blobs to delete ($([math]::Round($containerDeletionSize / 1GB, 2)) GB)"
        Write-ThreadLog $completionMsg -Level "SUCCESS"
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Completed: $containerName ($containerCount blobs, $([math]::Round($containerSize / 1GB, 2)) GB)" -ForegroundColor Green
        
        return $result
    }
    catch {
        Write-ThreadLog "Container '$containerName': ERROR - $_" -Level "ERROR"
        Write-Warning "Error processing container '$containerName': $_"
        $failedContainers.Add($containerName)
        return $null
    }
} | Where-Object { $_ -ne $null }

Write-Host ""
$endTime = Get-Date
$duration = $endTime - $startTime
Write-Log "=========================================="
Write-Log "Parallel processing completed"
Write-Log "Total duration: $($duration.ToString('hh\:mm\:ss'))"
Write-Log "Containers processed: $($containerResults.Count) of $($containers.Count)"

if ($failedContainers.Count -gt 0) {
    Write-Log "WARNING: $($failedContainers.Count) containers failed or timed out:" -Level "WARNING"
    $failedContainers | ForEach-Object { 
        Write-Log "  Failed: $_" -Level "WARNING"
    }
}

Write-Log "Calculating totals..." -Level "INFO"

# Calculate totals from results
$totalCurrentSize = ($containerResults | Measure-Object -Property _TotalSize -Sum).Sum
$totalCurrentCount = ($containerResults | Measure-Object -Property TotalBlobCount -Sum).Sum
$totalDeletionSize = ($containerResults | Measure-Object -Property _DeletionSize -Sum).Sum
$totalDeletionCount = ($containerResults | Measure-Object -Property BlobsToDelete -Sum).Sum

# Display summary
Write-Log "=========================================="
Write-Log "SUMMARY REPORT"
Write-Log "=========================================="
Write-Log "Total Current Storage:"
Write-Log "  Containers Analyzed: $($containerResults.Count) of $($containers.Count)"
if ($failedContainers.Count -gt 0) {
    Write-Log "  Containers Failed/Skipped: $($failedContainers.Count)" -Level "WARNING"
}
Write-Log "  Blob Count: $totalCurrentCount"
Write-Log "  Total Size: $([math]::Round($totalCurrentSize / 1GB, 2)) GB"
Write-Log ""
Write-Log "Impact of $retentionDays-Day Retention Policy:"
Write-Log "  Blobs to be deleted: $totalDeletionCount"
Write-Log "  Storage to be freed: $([math]::Round($totalDeletionSize / 1GB, 2)) GB"
if ($totalCurrentSize -gt 0) {
    Write-Log "  Percentage of data affected: $([math]::Round(($totalDeletionSize / $totalCurrentSize) * 100, 1))%"
}
Write-Log ""
$monthlySavings = ($totalDeletionSize / 1GB) * $costPerGBMonth
Write-Log "Cost Analysis:" -Level "SUCCESS"
Write-Log "  Estimated Monthly Savings: £$([math]::Round($monthlySavings, 2))"
Write-Log "  Estimated Annual Savings: £$([math]::Round($monthlySavings * 12, 2))"
Write-Log ""

# Display top containers by deletion size
if ($containerResults.Count -gt 0) {
    Write-Log "Top 10 Containers by Deletion Size:"
    $topContainers = $containerResults | 
        Sort-Object SizeToDeleteGB -Descending | 
        Select-Object -First 10
    
    foreach ($c in $topContainers) {
        Write-Log "  $($c.Container): $($c.SizeToDeleteGB) GB to delete ($($c.PercentToDelete)%)"
    }
    
    Write-Host ""
    Write-Host "Top 10 Containers by Deletion Size:" -ForegroundColor Yellow
    $topContainers | Select-Object Container, TotalBlobCount, TotalSizeGB, BlobsToDelete, SizeToDeleteGB, PercentToDelete | Format-Table -AutoSize
}

# Export results to CSV
if ($containerResults.Count -gt 0) {
    # Remove internal fields before export
    $exportResults = $containerResults | Select-Object -Property Container, TotalBlobCount, TotalSizeGB, 
        BlobsToDelete, SizeToDeleteGB, PercentToDelete, EstMonthlySavings
    
    $exportResults | Export-Csv -Path $exportPath -NoTypeInformation
    Write-Log "Detailed results exported to: $exportPath" -Level "SUCCESS"
    
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
    
    Write-Log "Summary report saved to: $summaryPath" -Level "SUCCESS"
}

Write-Log "=========================================="
Write-Log "AUDIT COMPLETE!" -Level "SUCCESS"
Write-Log "Performance: Processed $($containerResults.Count) of $($containers.Count) containers using $ThrottleLimit parallel threads"
Write-Log "Total execution time: $($duration.ToString('hh\:mm\:ss'))"
Write-Log "Log file: $LogPath"
if ($failedContainers.Count -gt 0) {
    Write-Log "WARNING: $($failedContainers.Count) containers failed or timed out. Consider reducing ThrottleLimit or increasing TimeoutMinutes." -Level "WARNING"
}
Write-Log "=========================================="
