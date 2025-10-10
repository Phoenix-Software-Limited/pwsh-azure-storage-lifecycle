<#
.SYNOPSIS
    Azure Storage Lifecycle Policy - Pre-Implementation Audit Script (Multi-Threaded Version)
    Version: 1.4.3
    
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
    
    [ValidateRange(1, 15)]
    [int]$ThrottleLimit = 5,
    
    [int]$TimeoutMinutes = 30,
    
    [switch]$ShowDetailedOutput,
    
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
        # Clean path first before processing
        $cleanedExportPath = $exportPath.TrimEnd('\', '"', "'")
        $customExportDir = [System.IO.Path]::GetDirectoryName($cleanedExportPath)
        if ([string]::IsNullOrEmpty([System.IO.Path]::GetFileName($cleanedExportPath))) {
            # It's a directory path
            $customExportDir = $cleanedExportPath
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
    # Clean up path: remove trailing backslashes and any stray quotes from escaping issues
    $LogPath = $LogPath.TrimEnd('\', '"', "'")
    
    # If user provided a directory path, append default filename
    if (Test-Path -Path $LogPath -PathType Container) {
        $LogPath = Join-Path $LogPath "${baseFileName}.log"
    }
    elseif ([string]::IsNullOrEmpty([System.IO.Path]::GetFileName($LogPath))) {
        # Path has no filename component - it's a directory
        $LogPath = Join-Path $LogPath "${baseFileName}.log"
    }
    elseif ([string]::IsNullOrEmpty([System.IO.Path]::GetExtension($LogPath))) {
        # No file extension - assume it's a directory path
        $LogPath = Join-Path $LogPath "${baseFileName}.log"
    }
}

if (-not $userProvidedExportPath) {
    $exportPath = "$env:TEMP\${baseFileName}.csv"
}
else {
    # Clean up path: remove trailing backslashes and any stray quotes from escaping issues
    $exportPath = $exportPath.TrimEnd('\', '"', "'")
    
    # If user provided a directory path, append default filename
    if (Test-Path -Path $exportPath -PathType Container) {
        $exportPath = Join-Path $exportPath "${baseFileName}.csv"
    }
    elseif ([string]::IsNullOrEmpty([System.IO.Path]::GetFileName($exportPath))) {
        # Path has no filename component - it's a directory
        $exportPath = Join-Path $exportPath "${baseFileName}.csv"
    }
    elseif ([string]::IsNullOrEmpty([System.IO.Path]::GetExtension($exportPath))) {
        # No file extension - assume it's a directory path  
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

# Token refresh helper function
function Test-AzureTokenExpiration {
    <#
    .SYNOPSIS
    Checks if Azure token is about to expire
    .DESCRIPTION
    Returns true if token will expire within the next 5 minutes
    #>
    param(
        [int]$WarningMinutes = 5
    )
    
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Log "No Azure context found" -Level "WARNING"
            return $true
        }
        
        # Get token expiration
        $token = Get-AzAccessToken -ErrorAction Stop
        $expiresOn = $token.ExpiresOn.LocalDateTime
        $timeUntilExpiry = $expiresOn - (Get-Date)
        
        if ($timeUntilExpiry.TotalMinutes -le $WarningMinutes) {
            Write-Log "Token expires in $([math]::Round($timeUntilExpiry.TotalMinutes, 1)) minutes" -Level "WARNING"
            return $true
        }
        
        return $false
    }
    catch {
        Write-Log "Error checking token expiration: $_" -Level "WARNING"
        return $true
    }
}

function Update-AzureToken {
    <#
    .SYNOPSIS
    Refreshes Azure authentication token
    .DESCRIPTION
    Attempts to refresh the current Azure session without re-prompting for credentials
    #>
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Log "No Azure context to refresh. Please run Connect-AzAccount" -Level "ERROR"
            throw "No Azure context found"
        }
        
        Write-Log "Refreshing Azure token..." -Level "INFO"
        
        # Store context details
        $subscriptionId = $context.Subscription.Id
        $accountId = $context.Account.Id
        
        # Attempt silent token refresh by getting a new access token
        Get-AzAccessToken -ErrorAction Stop | Out-Null
        
        # Verify the refresh worked
        $newContext = Get-AzContext
        if ($newContext -and $newContext.Subscription.Id -eq $subscriptionId) {
            Write-Log "Token refreshed successfully. Account: $accountId, Subscription: $subscriptionId" -Level "SUCCESS"
            return $true
        }
        else {
            Write-Log "Token refresh verification failed" -Level "WARNING"
            return $false
        }
    }
    catch {
        Write-Log "Failed to refresh token: $_" -Level "ERROR"
        Write-Log "You may need to run Connect-AzAccount again" -Level "WARNING"
        return $false
    }
}

function Invoke-WithTokenRefresh {
    <#
    .SYNOPSIS
    Executes a script block with automatic token refresh if needed
    .DESCRIPTION
    Checks token expiration before execution and refreshes if necessary
    #>
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,
        [string]$OperationName = "Operation"
    )
    
    # Check if token needs refresh
    if (Test-AzureTokenExpiration) {
        $message = "$($OperationName): Token refresh needed"
        Write-Log $message -Level "INFO"
        if (-not (Update-AzureToken)) {
            throw "Failed to refresh Azure token. Please run Connect-AzAccount again."
        }
    }
    
    # Execute the script block
    try {
        & $ScriptBlock
    }
    catch {
        $errorMessage = "$($OperationName) failed: $_"
        Write-Log $errorMessage -Level "ERROR"
        throw
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
Write-Log "(Multi-Threaded Version - v1.4.3)"
Write-Log "=========================================="
Write-Log "Account: $storageAccount"
Write-Log "Resource Group: $resourceGroup"
Write-Log "Retention Period: $retentionDays days"
Write-Log "Parallel Threads: $ThrottleLimit"
Write-Log "Timeout: $TimeoutMinutes minutes per container"
Write-Log "Report Date: $(Get-Date)"
Write-Log "Resume Mode: $(if ($Resume) { 'YES' } else { 'NO' })"
Write-Log "Log File: $LogPath"
Write-Log "CSV Output: $exportPath"
Write-Log "Progress File: $progressFilePath"
Write-Host ""

# Verify Azure connection and token validity
Write-Log "Verifying Azure connection..." -Level "INFO"
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Log "No Azure context found. Please run Connect-AzAccount first." -Level "ERROR"
        exit 1
    }
    
    # Check token expiration and refresh if needed
    $token = Get-AzAccessToken -ErrorAction Stop
    $expiresOn = $token.ExpiresOn.LocalDateTime
    $timeUntilExpiry = $expiresOn - (Get-Date)
    
    Write-Log "Connected as: $($context.Account.Id)" -Level "SUCCESS"
    Write-Log "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -Level "INFO"
    Write-Log "Token valid for: $([math]::Round($timeUntilExpiry.TotalMinutes, 1)) minutes" -Level "INFO"
    
    if ($timeUntilExpiry.TotalMinutes -le 5) {
        Write-Log "Token is about to expire, refreshing..." -Level "WARNING"
        if (-not (Update-AzureToken)) {
            Write-Log "Failed to refresh token. Please run Connect-AzAccount again." -Level "ERROR"
            exit 1
        }
    }
}
catch {
    Write-Log "Azure authentication check failed: $_" -Level "ERROR"
    Write-Log "Please run Connect-AzAccount to authenticate." -Level "ERROR"
    exit 1
}

# Get storage context with token refresh
Write-Log "Connecting to storage account..." -Level "INFO"
try {
    Invoke-WithTokenRefresh -ScriptBlock {
        $script:storageAccountObj = Get-AzStorageAccount -ResourceGroupName $resourceGroup `
            -Name $storageAccount -ErrorAction Stop
        $script:ctx = $script:storageAccountObj.Context
    } -OperationName "Storage Account Connection"
    
    Write-Log "Successfully connected to storage account" -Level "SUCCESS"
}
catch {
    Write-Log "Failed to access storage account: $_" -Level "ERROR"
    exit 1
}

# Get all containers with token refresh
Write-Log "Retrieving container list..." -Level "INFO"
try {
    Invoke-WithTokenRefresh -ScriptBlock {
        $script:containers = Get-AzStorageContainer -Context $ctx
    } -OperationName "Container List Retrieval"
    
    Write-Log "Found $($containers.Count) containers" -Level "SUCCESS"
}
catch {
    Write-Log "Failed to retrieve containers: $_" -Level "ERROR"
    exit 1
}

if ($containers.Count -eq 0) {
    Write-Log "No containers found in storage account." -Level "WARNING"
    exit 0
}

# Load progress data if resuming
$completedContainers = @{}
$processedResults = @()

if ($Resume -and (Test-Path $progressFilePath)) {
    Write-Log "Loading progress from previous run..." -Level "INFO"
    $progressData = Get-Content $progressFilePath | ConvertFrom-Json
    $completedContainers = @{}
    $progressData.CompletedContainers | ForEach-Object { $completedContainers[$_] = $true }
    
    Write-Log "Previously completed: $($completedContainers.Count) containers" -Level "SUCCESS"
    
    # Load existing CSV results
    if (Test-Path $exportPath) {
        $processedResults = Import-Csv $exportPath | ForEach-Object {
            [PSCustomObject]@{
                Container = $_.Container
                TotalBlobCount = [int]$_.TotalBlobCount
                TotalSizeGB = [double]$_.TotalSizeGB
                BlobsToDelete = [int]$_.BlobsToDelete
                SizeToDeleteGB = [double]$_.SizeToDeleteGB
                PercentToDelete = [double]$_.PercentToDelete
                EstMonthlySavings = [double]$_.EstMonthlySavings
                _TotalSize = [double]$_.TotalSizeGB * 1GB
                _DeletionSize = [double]$_.SizeToDeleteGB * 1GB
                _AgeGroups = $null
            }
        }
        Write-Log "Loaded $($processedResults.Count) previously processed results" -Level "SUCCESS"
    }
    
    # Filter to unprocessed containers
    $containers = $containers | Where-Object { -not $completedContainers.ContainsKey($_.Name) }
    Write-Log "Remaining to process: $($containers.Count) containers" -Level "INFO"
    
    if ($containers.Count -eq 0) {
        Write-Log "All containers already processed!" -Level "SUCCESS"
        Write-Log "Use existing results at: $exportPath" -Level "SUCCESS"
        exit 0
    }
}

# Initialize progress tracking
$progressData = @{
    Timestamp = $timestamp
    StorageAccount = $storageAccount
    ResourceGroup = $resourceGroup
    RetentionDays = $retentionDays
    StartTime = (Get-Date).ToString('o')
    LastUpdate = (Get-Date).ToString('o')
    CompletedContainers = @($completedContainers.Keys)
}
$progressData | ConvertTo-Json | Set-Content $progressFilePath

Write-Log "Starting parallel analysis with $ThrottleLimit threads..." -Level "INFO"
Write-Log "Processing containers - progress will be logged as each completes..." -Level "INFO"
Write-Log "Results saved incrementally to: $exportPath" -Level "INFO"
Write-Host ""

# Track progress
$script:failedContainers = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
$script:completedContainers = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
$script:processedCount = 0
$script:totalContainers = $containers.Count
$startTime = Get-Date

# Create CSV header if new file
if (-not (Test-Path $exportPath) -or -not $Resume) {
    "Container,TotalBlobCount,TotalSizeGB,BlobsToDelete,SizeToDeleteGB,PercentToDelete,EstMonthlySavings" | 
        Set-Content $exportPath
}

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
    $completedContainersBag = $using:completedContainers
    $LogPath = $using:LogPath
    $exportPath = $using:exportPath
    $progressFilePath = $using:progressFilePath
    
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
    
    # Thread-safe token refresh function
    function Test-ThreadTokenExpiration {
        param([int]$WarningMinutes = 5)
        try {
            $context = Get-AzContext
            if (-not $context) { return $true }
            
            $token = Get-AzAccessToken -ErrorAction Stop
            $expiresOn = $token.ExpiresOn.LocalDateTime
            $timeUntilExpiry = $expiresOn - (Get-Date)
            
            return ($timeUntilExpiry.TotalMinutes -le $WarningMinutes)
        }
        catch {
            return $true
        }
    }
    
    function Update-ThreadToken {
        try {
            $context = Get-AzContext
            if (-not $context) { throw "No Azure context found" }
            
            # Attempt silent token refresh
            Get-AzAccessToken -ErrorAction Stop | Out-Null
            
            # Verify refresh
            $newContext = Get-AzContext
            return ($newContext -and $newContext.Subscription.Id -eq $context.Subscription.Id)
        }
        catch {
            return $false
        }
    }
    
    $containerName = $container.Name
    Write-ThreadLog "Started processing container: $containerName" -Level "INFO"
    
    try {
        # Check and refresh token if needed before establishing connection
        if (Test-ThreadTokenExpiration) {
            Write-ThreadLog "Container '$containerName': Token refresh needed" -Level "WARNING"
            if (-not (Update-ThreadToken)) {
                throw "Failed to refresh Azure token for thread"
            }
            Write-ThreadLog "Container '$containerName': Token refreshed successfully" -Level "SUCCESS"
        }
        
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
        
        # Save result immediately to CSV (thread-safe with mutex)
        $csvLine = "$containerName,$containerCount,$([math]::Round($containerSize / 1GB, 2)),$containerDeletionCount,$([math]::Round($containerDeletionSize / 1GB, 2)),$($result.PercentToDelete),$($result.EstMonthlySavings)"
        $mutex = New-Object System.Threading.Mutex($false, "StorageAuditCSVMutex")
        try {
            $mutex.WaitOne() | Out-Null
            Add-Content -Path $exportPath -Value $csvLine
            
            # Update progress file
            $completedContainersBag.Add($containerName)
            $currentProgress = Get-Content $progressFilePath | ConvertFrom-Json
            $updatedProgress = @{
                Timestamp = $currentProgress.Timestamp
                StorageAccount = $currentProgress.StorageAccount
                ResourceGroup = $currentProgress.ResourceGroup
                RetentionDays = $currentProgress.RetentionDays
                StartTime = $currentProgress.StartTime
                LastUpdate = (Get-Date).ToString('o')
                CompletedContainers = @($currentProgress.CompletedContainers) + @($containerName)
            }
            $updatedProgress | ConvertTo-Json | Set-Content $progressFilePath
        }
        finally {
            $mutex.ReleaseMutex()
        }
        
        Write-ThreadLog "Container '$containerName': Result saved to CSV" -Level "INFO"
        
        return $result
    }
    catch {
        Write-ThreadLog "Container '$containerName': ERROR - $_" -Level "ERROR"
        Write-Warning "Error processing container '$containerName': $_"
        $failedContainers.Add($containerName)
        return $null
    }
} | Where-Object { $_ -ne $null }

# Combine with previously processed results if resuming
if ($Resume -and $processedResults.Count -gt 0) {
    Write-Log "Combining new results with $($processedResults.Count) previous results..." -Level "INFO"
    $containerResults = @($processedResults) + @($containerResults)
}

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

# Export results to CSV (final consolidated version)
if ($containerResults.Count -gt 0) {
    # Remove internal fields before export
    $exportResults = $containerResults | Select-Object -Property Container, TotalBlobCount, TotalSizeGB, 
        BlobsToDelete, SizeToDeleteGB, PercentToDelete, EstMonthlySavings
    
    # Overwrite with complete sorted results
    $exportResults | Sort-Object Container | Export-Csv -Path $exportPath -NoTypeInformation
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
if ($Resume) {
    Write-Log "Processed $(if ($containers.Count -gt 0) { $containers.Count } else { 0 }) additional containers in this run"
    Write-Log "Total containers in final report: $($containerResults.Count)"
}
else {
    Write-Log "Performance: Processed $($containerResults.Count) of $($containers.Count + $processedResults.Count) containers using $ThrottleLimit parallel threads"
}
Write-Log "Total execution time: $($duration.ToString('hh\:mm\:ss'))"
Write-Log "Log file: $LogPath"
Write-Log "CSV Results: $exportPath"
Write-Log "Progress File: $progressFilePath"
if ($failedContainers.Count -gt 0) {
    Write-Log "WARNING: $($failedContainers.Count) containers failed or timed out. You can resume with -Resume parameter" -Level "WARNING"
}
else {
    Write-Log "TIP: Progress file can be deleted now that all containers completed successfully" -Level "SUCCESS"
}
Write-Log "=========================================="
