   <#
   .SYNOPSIS
       Azure Storage Lifecycle Policy - Pre-Implementation Audit Script
       Version: 1.3.1
       
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
   .PARAMETER LogPath
       Path to log file for detailed progress tracking (optional, auto-generated if not specified)
   .PARAMETER Resume
       Resume from a previous incomplete run using the progress tracking file
   #>

   param(
       [Parameter(Mandatory=$true)]
       [string]$resourceGroup,
       
       [Parameter(Mandatory=$true)]
       [string]$storageAccount,
       
       [Parameter(Mandatory=$true)]
       [int]$retentionDays,
       
       [string]$exportPath = "$env:TEMP\storage_audit_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",
       
       [string]$LogPath = "$env:TEMP\storage_audit_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",
       
       [switch]$Resume
   )

   # Generate consistent file names for resume capability
   $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
   $baseFileName = "storage_audit_${storageAccount}_${timestamp}"
   
   # Determine if user provided custom paths
   $userProvidedExportPath = $PSBoundParameters.ContainsKey('exportPath')
   $userProvidedLogPath = $PSBoundParameters.ContainsKey('LogPath')

   # Override paths if resuming
   if ($Resume) {
       # Determine where to search for progress files
       $searchPaths = @($env:TEMP)
       
       # If user provided export path, also search there
       if ($userProvidedExportPath) {
           $customExportDir = [System.IO.Path]::GetDirectoryName($exportPath.TrimEnd('\'))
           if ([string]::IsNullOrEmpty([System.IO.Path]::GetFileName($exportPath.TrimEnd('\')))) {
               # It's a directory path
               $customExportDir = $exportPath.TrimEnd('\')
           }
           if (-not [string]::IsNullOrEmpty($customExportDir) -and (Test-Path $customExportDir)) {
               $searchPaths += $customExportDir
           }
       }
       
       # Find the most recent progress file for this storage account
       $progressFiles = @()
       foreach ($searchPath in $searchPaths) {
           $progressFiles += Get-ChildItem -Path $searchPath -Filter "storage_audit_${storageAccount}_*_progress.json" -ErrorAction SilentlyContinue
       }
       $progressFiles = $progressFiles | Sort-Object LastWriteTime -Descending
       
       if ($progressFiles -and $progressFiles.Count -gt 0) {
           $progressFile = $progressFiles[0].FullName
           $progressData = Get-Content $progressFile | ConvertFrom-Json
           $baseFileName = [System.IO.Path]::GetFileNameWithoutExtension($progressFile).Replace('_progress', '')
           $timestamp = $progressData.Timestamp
           Write-Host "Resuming from previous run: $baseFileName" -ForegroundColor Cyan
           Write-Host "Progress file found at: $progressFile" -ForegroundColor Cyan
       }
       else {
           Write-Warning "No previous run found for storage account '$storageAccount'. Starting fresh."
           $Resume = $false
       }
   }

   # Set file paths - respect user-provided paths
   if (-not $userProvidedLogPath) {
       $LogPath = "$env:TEMP\${baseFileName}.log"
   }
   else {
       # Remove trailing backslashes that can cause quote escaping issues
       $LogPath = $LogPath.TrimEnd('\')
   }
   
   if (-not $userProvidedExportPath) {
       $exportPath = "$env:TEMP\${baseFileName}.csv"
   }
   else {
       # Remove trailing backslashes that can cause quote escaping issues
       $exportPath = $exportPath.TrimEnd('\')
       
       # If user provided a directory path, append default filename
       if (Test-Path -Path $exportPath -PathType Container) {
           $exportPath = Join-Path $exportPath "${baseFileName}.csv"
       }
       elseif ([string]::IsNullOrEmpty([System.IO.Path]::GetFileName($exportPath))) {
           # Path ends with backslash but doesn't exist yet - it's a directory
           $exportPath = Join-Path $exportPath "${baseFileName}.csv"
       }
   }
   
   # Derive progress file path from export path
   $exportDir = [System.IO.Path]::GetDirectoryName($exportPath)
   $exportBaseName = [System.IO.Path]::GetFileNameWithoutExtension($exportPath)
   $progressFilePath = Join-Path $exportDir "${exportBaseName}_progress.json"

   # Ensure directories exist before attempting to write files
   $logDir = [System.IO.Path]::GetDirectoryName($LogPath)
   if (-not [string]::IsNullOrEmpty($logDir) -and -not (Test-Path $logDir)) {
       New-Item -ItemType Directory -Path $logDir -Force | Out-Null
   }
   if (-not [string]::IsNullOrEmpty($exportDir) -and -not (Test-Path $exportDir)) {
       New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
   }

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

   # Cost per GB per month for hot tier (adjust based on region)
   $costPerGBMonth = 0.0184  # UK South pricing as example

   Write-Log "=========================================="
   Write-Log "Storage Account Lifecycle Policy Audit"
   Write-Log "(Sequential Version - v1.3.1 with Resume)"
   Write-Log "=========================================="
   Write-Log "Account: $storageAccount"
   Write-Log "Resource Group: $resourceGroup"
   Write-Log "Retention Period: $retentionDays days"
   Write-Log "Report Date: $(Get-Date)"
   Write-Log "Resume Mode: $(if ($Resume) { 'YES' } else { 'NO' })"
   Write-Log "Log File: $LogPath"
   Write-Log "CSV Output: $exportPath"
   Write-Log "Progress File: $progressFilePath"
   Write-Host ""

   # Get storage context
   Write-Log "Connecting to storage account..." -Level "INFO"
   try {
       $ctx = (Get-AzStorageAccount -ResourceGroupName $resourceGroup `
           -Name $storageAccount -ErrorAction Stop).Context
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

   # Load progress data if resuming
   $completedContainers = @{}
   $containerResults = @()

   if ($Resume -and (Test-Path $progressFilePath)) {
       Write-Log "Loading progress from previous run..." -Level "INFO"
       $progressData = Get-Content $progressFilePath | ConvertFrom-Json
       $completedContainers = @{}
       $progressData.CompletedContainers | ForEach-Object { $completedContainers[$_] = $true }
       
       Write-Log "Previously completed: $($completedContainers.Count) containers" -Level "SUCCESS"
       
       # Load existing CSV results
       if (Test-Path $exportPath) {
           $containerResults = @(Import-Csv $exportPath | ForEach-Object {
               [PSCustomObject]@{
                   Container = $_.Container
                   TotalBlobCount = [int]$_.TotalBlobCount
                   TotalSizeGB = [double]$_.TotalSizeGB
                   BlobsToDelete = [int]$_.BlobsToDelete
                   SizeToDeleteGB = [double]$_.SizeToDeleteGB
                   PercentToDelete = [double]$_.PercentToDelete
                   EstMonthlySavings = [double]$_.EstMonthlySavings
               }
           })
           Write-Log "Loaded $($containerResults.Count) previously processed results" -Level "SUCCESS"
       }
       
       Write-Log "Remaining to process: $(($containers | Where-Object { -not $completedContainers.ContainsKey($_.Name) }).Count) containers" -Level "INFO"
   }

   # Initialize progress tracking
   $progressData = @{
       Timestamp = $timestamp
       StorageAccount = $storageAccount
       ResourceGroup = $resourceGroup
       RetentionDays = $retentionDays
       StartTime = (Get-Date).ToString('o')
       CompletedContainers = @($completedContainers.Keys)
   }
   $progressData | ConvertTo-Json | Set-Content $progressFilePath

   # Initialize summary variables
   $totalCurrentSize = 0
   $totalCurrentCount = 0
   $totalDeletionSize = 0
   $totalDeletionCount = 0

   # Create CSV header if new file
   if (-not (Test-Path $exportPath) -or -not $Resume) {
       "Container,TotalBlobCount,TotalSizeGB,BlobsToDelete,SizeToDeleteGB,PercentToDelete,EstMonthlySavings" | 
           Set-Content $exportPath
   }

   Write-Log "Starting sequential analysis..." -Level "INFO"
   Write-Log "Results saved incrementally to: $exportPath" -Level "INFO"
   $startTime = Get-Date

   $processedInThisRun = 0
   foreach ($container in $containers) {
       # Skip if already processed
       if ($completedContainers.ContainsKey($container.Name)) {
           continue
       }
       
       $remainingContainers = ($containers | Where-Object { -not $completedContainers.ContainsKey($_.Name) }).Count
       Write-Progress -Activity "Analysing Storage" -Status "Container: $($container.Name) ($processedInThisRun of $remainingContainers remaining)" `
           -PercentComplete (($processedInThisRun / $remainingContainers) * 100)
       
       Write-Log "Started processing container: $($container.Name)" -Level "INFO"
       
       try {
           $blobs = Get-AzStorageBlob -Container $container.Name -Context $ctx
           Write-Log "Container '$($container.Name)': Retrieved $($blobs.Count) blobs" -Level "INFO"
       }
       catch {
           Write-Log "Container '$($container.Name)': Failed to retrieve blobs - $_" -Level "ERROR"
           continue
       }
       
       # Skip if container is empty
       if ($blobs.Count -eq 0) {
           Write-Log "Container '$($container.Name)': Empty container, skipping" -Level "INFO"
           $completedContainers[$container.Name] = $true
           $progressData.CompletedContainers = @($completedContainers.Keys)
           $progressData.LastUpdate = (Get-Date).ToString('o')
           $progressData | ConvertTo-Json | Set-Content $progressFilePath
           continue
       }
       
       Write-Log "Container '$($container.Name)': Analyzing $($blobs.Count) blobs..." -Level "INFO"
       
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
       
       # Create result object
       $result = [PSCustomObject]@{
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
       
       # Save result immediately to CSV
       $csvLine = "$($container.Name),$containerCount,$([math]::Round($containerSize / 1GB, 2)),$containerDeletionCount,$([math]::Round($containerDeletionSize / 1GB, 2)),$($result.PercentToDelete),$($result.EstMonthlySavings)"
       Add-Content -Path $exportPath -Value $csvLine
       
       # Update progress file
       $completedContainers[$container.Name] = $true
       $progressData.CompletedContainers = @($completedContainers.Keys)
       $progressData.LastUpdate = (Get-Date).ToString('o')
       $progressData | ConvertTo-Json | Set-Content $progressFilePath
       
       # Store result in memory for summary
       $containerResults += $result
       
       Write-Log "Container '$($container.Name)': COMPLETED - $containerCount blobs, $([math]::Round($containerSize / 1GB, 2)) GB total, $containerDeletionCount to delete ($([math]::Round($containerDeletionSize / 1GB, 2)) GB)" -Level "SUCCESS"
       
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
       
       $processedInThisRun++
   }

   Write-Progress -Activity "Analysing Storage" -Completed
   
   $endTime = Get-Date
   $duration = $endTime - $startTime
   Write-Log "=========================================="
   Write-Log "Analysis completed"
   Write-Log "Total duration: $($duration.ToString('hh\:mm\:ss'))"
   Write-Log "Containers processed in this run: $processedInThisRun"
   Write-Log "Total containers in results: $($containerResults.Count)"

   # Calculate totals from all results
   $totalCurrentSize = ($containerResults | ForEach-Object { $_.TotalSizeGB * 1GB } | Measure-Object -Sum).Sum
   $totalCurrentCount = ($containerResults | Measure-Object -Property TotalBlobCount -Sum).Sum
   $totalDeletionSize = ($containerResults | ForEach-Object { $_.SizeToDeleteGB * 1GB } | Measure-Object -Sum).Sum
   $totalDeletionCount = ($containerResults | Measure-Object -Property BlobsToDelete -Sum).Sum

   # Display summary
   Write-Log "=========================================="
   Write-Log "SUMMARY REPORT"
   Write-Log "=========================================="
   Write-Log "Total Current Storage:"
   Write-Log "  Containers Analyzed: $($containerResults.Count)"
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

   # Export final consolidated results to CSV
   if ($containerResults.Count -gt 0) {
       $containerResults | Sort-Object Container | Export-Csv -Path $exportPath -NoTypeInformation
       Write-Log "Final consolidated results exported to: $exportPath" -Level "SUCCESS"
       
       # Also create summary file - handle paths without .csv extension
       $exportDir = [System.IO.Path]::GetDirectoryName($exportPath)
       $exportBaseName = [System.IO.Path]::GetFileNameWithoutExtension($exportPath)
       $summaryPath = Join-Path $exportDir "${exportBaseName}_summary.txt"
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
       
       Write-Log "Summary report saved to: $summaryPath" -Level "SUCCESS"
   }

   Write-Log "=========================================="
   Write-Log "AUDIT COMPLETE!" -Level "SUCCESS"
   if ($Resume) {
       Write-Log "Processed $processedInThisRun additional containers in this run"
       Write-Log "Total containers in final report: $($containerResults.Count)"
   }
   else {
       Write-Log "Performance: Processed $($containerResults.Count) containers"
   }
   Write-Log "Total execution time: $($duration.ToString('hh\:mm\:ss'))"
   Write-Log "Log file: $LogPath"
   Write-Log "CSV Results: $exportPath"
   Write-Log "Progress File: $progressFilePath"
   Write-Log "TIP: Progress file can be deleted now that all containers completed successfully" -Level "SUCCESS"
   Write-Log "=========================================="
