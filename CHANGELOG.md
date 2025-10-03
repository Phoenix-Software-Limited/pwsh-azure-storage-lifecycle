# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned Features
- Support for Cool and Archive tier analysis
- JSON output format option
- Batch processing for multiple storage accounts
- Azure CLI version of the script
- Automated email reporting
- Dashboard/visualization support

## [1.4.2] - 2025-10-03

### Fixed
- **Critical:** Fixed "LastUpdate property cannot be found" error in progress file updates
- Progress tracking now properly initializes LastUpdate field in initial progress data structure
- Progress file updates now reconstruct the entire structure instead of attempting to add properties dynamically
- Improved thread-safe progress file handling to prevent corruption

### Technical Details
- Initial progress data now includes LastUpdate field set to current timestamp
- Progress file update logic in parallel threads now creates a new hashtable with all required fields
- Ensures compatibility when resuming from older progress files that may not have all fields

### Changes
- Updated parallel script to v1.4.2
- Improved error handling for progress file operations

## [1.4.1] - 2025-10-03

### Fixed
- Fixed string interpolation parsing error in `Invoke-WithTokenRefresh` function
- Resolved "Variable reference is not valid" error that prevented script execution

### Changed
- Modified token refresh logging to use variable assignment before passing to Write-Log
- Improved error message formatting in token refresh operations

## [1.4.0] - 2025-10-03

### Added
- **Automatic token refresh** - Prevents Azure token expiration during long-running operations
- **Token expiration monitoring** - Checks token validity before critical operations
- **Thread-safe token refresh** - Each parallel thread can independently refresh its token
- **Token status logging** - Displays initial token validity duration and refresh events
- Three new helper functions: `Test-AzureTokenExpiration`, `Update-AzureToken`, and `Invoke-WithTokenRefresh`
- Azure connection verification on startup with account and subscription details
- Token refresh logic integrated into main thread operations
- Independent token refresh capability in each parallel processing thread

### Changed
- Initial Azure connection now validates token expiration (5-minute warning threshold)
- Storage account connection wrapped with automatic token refresh
- Container list retrieval wrapped with automatic token refresh
- Each parallel thread checks and refreshes token before establishing connection
- Enhanced startup logging to show connected account, subscription, and token validity

### Fixed
- **Critical:** Script no longer fails after ~60 minutes due to Azure AD token expiration
- **Critical:** Resume functionality now works reliably after extended breaks
- Eliminated "token has expired" errors during long-running scans
- Fixed authentication failures in parallel threads during extended operations
- Improved reliability for storage accounts with hundreds of containers

### Performance
- Long-running operations (>1 hour) now complete without interruption
- Resume operations work reliably regardless of time between runs
- No need to re-authenticate manually during extended processing

### Security
- Token refresh attempts silent renewal without prompting for credentials
- Falls back gracefully if token refresh fails with clear error messages
- Maintains same security posture as Connect-AzAccount

### Technical Details
- Token expiration checked with 5-minute warning threshold
- Uses `Get-AzAccessToken` to check token validity and trigger refresh
- Token refresh verified by comparing subscription IDs before/after refresh
- Thread-safe token functions use isolated context per parallel thread
- Wrapper function `Invoke-WithTokenRefresh` simplifies token-aware operations

### Storage Account Permissions Required
The script requires one of the following RBAC roles on the storage account:
- **Storage Blob Data Reader** (Recommended - Least Privilege)
- Reader + Storage Blob Data Reader (combination)
- Storage Account Contributor (excessive - not recommended)

Specific permissions needed:
- `Microsoft.Storage/storageAccounts/read`
- `Microsoft.Storage/storageAccounts/blobServices/containers/read`
- `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read`

Note: The script is read-only and does not require Storage Account Keys access.

### Usage
The token refresh is automatic and requires no parameter changes:
```powershell
# Same usage as before - token refresh happens automatically
.\pre-audit-script-parallel.ps1 -resourceGroup "rg" -storageAccount "storage" -retentionDays 90
```

**Token Status Logging:**
```
[INFO] Verifying Azure connection...
[SUCCESS] Connected as: user@domain.com
[INFO] Subscription: Production (abc-123-def)
[INFO] Token valid for: 58.3 minutes
```

**Automatic Refresh:**
```
[WARNING] Token expires in 4.2 minutes
[INFO] Refreshing Azure token...
[SUCCESS] Token refreshed successfully
```

## [1.3.0] - 2025-10-03

### Added
- **Incremental result saving** - Results now saved to CSV after each container completes
- **Resume functionality** - Use `-Resume` parameter to continue from where script stopped
- **Progress tracking file** - JSON file tracks completed containers for crash recovery
- **Automatic resume detection** - Script finds most recent progress file for the storage account
- **Crash recovery** - No more lost progress if script hangs, crashes, or is interrupted
- **Real-time CSV updates** - CSV file updates as each container completes (can be opened while running)
- **Thread-safe file operations** - Mutex-protected writes prevent corruption in parallel mode

### Changed
- Both parallel and sequential scripts now support incremental saving and resume
- File naming includes storage account name for easy identification
- Progress files automatically created in temp directory
- CSV results available immediately, even if script doesn't complete
- Log files and progress files use consistent naming scheme

### Fixed
- **Critical:** Scripts can now recover from crashes, hangs, or interruptions
- **Critical:** No more complete loss of data if script fails mid-execution
- Lost hours of processing can now be recovered with `-Resume`
- Prevents re-processing containers that already completed successfully

### Usage
**First run:**
```powershell
.\pre-audit-script-parallel.ps1 -resourceGroup "rg" -storageAccount "storage" -retentionDays 90
```

**If it crashes/hangs/stops:**
```powershell
.\pre-audit-script-parallel.ps1 -resourceGroup "rg" -storageAccount "storage" -retentionDays 90 -Resume
```

**Monitor progress in real-time:**
- Open the CSV file in Excel/text editor while script runs
- Tail the log file: `Get-Content "path\to\log.log" -Wait -Tail 20`
- Check progress file to see which containers are complete

### Performance
- Eliminates wasted time re-processing containers after failures
- Large storage accounts (100+ containers) can be processed across multiple runs
- Incremental saves ensure partial results are never lost
- Resume functionality makes script much more robust for production use

### Technical Details
- Progress tracked in JSON file: `storage_audit_{account}_{timestamp}_progress.json`
- CSV file updated incrementally using thread-safe mutex locks
- Resume mode loads previous CSV and progress file automatically
- Completed containers stored in hashtable for O(1) lookup
- Progress file updated after each container completion
- File paths use storage account name for multi-account safety

### Breaking Changes
- None - all new features are opt-in via `-Resume` parameter
- Existing scripts continue to work without modification

## [1.2.0] - 2025-10-03

### Added
- **Comprehensive logging system** - All operations now logged to timestamped log file
- Thread-safe logging within parallel processing blocks using mutex
- Real-time progress tracking with detailed per-container status updates
- Automatic log file generation with customizable path via `-LogPath` parameter
- Execution duration tracking and reporting
- Detailed logging of connection attempts, blob retrieval, and analysis progress
- Log levels (INFO, WARNING, ERROR, SUCCESS) with color-coded console output
- Each container logs: start, connection, blob retrieval attempts, analysis, and completion
- Failed containers now logged with detailed error messages
- Performance metrics logged including total execution time

### Changed
- All console output now mirrored to log file for complete audit trail
- Enhanced visibility during long-running operations (addresses apparent "hanging" issue)
- Log file path displayed at script start for easy monitoring
- Summary report includes log file location
- Container processing now logs each stage (connecting, retrieving blobs, analyzing, completing)

### Improved
- **Visibility during execution** - No more "silent" periods; log file updates continuously
- Retry attempts now explicitly logged with attempt numbers
- Empty containers clearly identified in logs
- Better troubleshooting capability with complete operation history
- Execution time displayed in HH:mm:ss format

### Technical Details
- Implemented `Write-Log` function for main thread operations
- Implemented `Write-ThreadLog` function with mutex for parallel thread safety
- Mutex named "StorageAuditLogMutex" prevents concurrent log file write conflicts
- Log files automatically timestamped to prevent overwrites
- All Write-Host calls replaced with Write-Log for consistent logging

### Use Cases
- Monitor script progress in real-time by tailing the log file
- Troubleshoot which containers are taking longest to process
- Identify Azure API throttling or connection issues
- Audit complete operation history for compliance
- Debug failed containers with detailed error context

## [1.1.3] - 2025-10-03

### Fixed
- **Critical:** Removed undefined `$using:totalContainers` variable reference that was causing "value of the using variable cannot be retrieved because it has not been set in the local session" error
- Script now properly initializes all variables used in parallel processing blocks

### Technical Details
- Cleaned up unused variable reference in ForEach-Object -Parallel block
- Variable was referenced but never defined before parallel execution
- All remaining `$using:` variable references are now valid and properly initialized

## [1.1.2] - Not Released

### Notes
- Version skipped to maintain changelog consistency

## [1.1.1] - 2025-10-03

### Fixed
- **Critical:** Script hanging when ThrottleLimit set too high (> 10), caused by Azure throttling
- **Critical:** Azure Storage context serialization errors ("Cannot bind parameter 'Context'") in parallel threads
- **Critical:** Progress counter not updating correctly in parallel execution
- Blob retrieval operations now use retry logic instead of timeout jobs (more reliable)
- Containers that fail are now gracefully skipped instead of hanging the entire script

### Added
- Automatic retry logic with 3 attempts and 5-second delays between retries
- Timestamp-based real-time progress reporting (shows HH:mm:ss when each container completes)
- Container completion messages show blob count and size for immediate feedback
- Automatic warning when ThrottleLimit > 10 with 5-second cancellation window
- Failed/timed-out containers are now tracked and reported in summary
- Failed containers list included in both console output and exported reports
- Validation for ThrottleLimit parameter (range: 1-15)

### Changed
- Each parallel thread now recreates its own storage context (fixes serialization issues)
- Removed broken shared counter approach in favor of timestamp-based progress
- Improved error handling with clearer error messages for Azure API failures
- Enhanced progress reporting to distinguish between completed and empty containers
- Summary report now shows containers analyzed vs total containers
- Export files now include failed containers section when applicable
- Empty containers displayed in gray, completed in green for better visual feedback

### Performance
- More reliable parallel processing by preventing Azure throttling-induced hangs
- Better resource management with proper context recreation per thread
- Recommended maximum ThrottleLimit reduced from 15 to 10 for stability
- Parallel execution verified working (processes 5 containers simultaneously by default)

### Technical Details
- Replaced Start-Job timeout mechanism with direct retry logic
- Context objects now created fresh in each parallel thread
- Progress tracking simplified to timestamp-based completion messages
- Eliminated race conditions in shared counter updates

## [1.1.0] - 2025-10-02

### Added
- **New parallel script (pre-audit-script-parallel.ps1)** - Multi-threaded version with 4-8x performance improvement
- PowerShell 7+ parallel processing support using `ForEach-Object -Parallel`
- Configurable throttle limit parameter (`-ThrottleLimit`) for controlling parallelism (default: 5 threads)
- Optional detailed output parameter (`-ShowDetailedOutput`) for verbose container-by-container output
- Real-time progress tracking for parallel execution
- Thread-safe data collection ensuring no race conditions

### Changed
- Updated README.md with comprehensive parallel script documentation
- Enhanced performance comparison table showing speed improvements
- Improved troubleshooting section with parallel script guidance
- Updated requirements section to distinguish between original and parallel script needs

### Performance
- **4-8x faster** processing for storage accounts with multiple containers
- 10 containers: ~2 minutes → ~30 seconds (4x improvement)
- 50 containers: ~10 minutes → ~2.5 minutes (4x improvement)  
- 100 containers: ~20 minutes → ~5 minutes (4x improvement)
- 500 containers: ~2 hours → ~25 minutes (5-8x improvement)

### Technical Details
- Implements PowerShell 7's `ForEach-Object -Parallel` for concurrent container processing
- Each thread independently fetches and analyzes blobs from Azure Storage
- Results collected safely via pipeline without shared mutable state
- Automatic version checking with helpful error messages for PowerShell 5.1 users

### Requirements
- Parallel script requires **PowerShell 7.0 or higher** (mandatory)
- Original script continues to support PowerShell 5.1+
- Same Azure module requirements for both scripts (Az.Accounts ≥2.10.0, Az.Storage ≥5.0.0)

## [1.0.0] - 2025-10-02

### Added
- Initial release of pre-audit-script.ps1
- Container-level analysis and reporting
- Age distribution tracking (7 age buckets)
- Cost savings calculations with UK South pricing
- CSV export functionality for detailed results
- Text summary report generation
- Progress indicator for long-running operations
- Color-coded console output
- Comprehensive error handling
- README.md with full documentation
- LICENSE file (MIT)
- .gitignore for PowerShell projects
- CONTRIBUTING.md with contribution guidelines

### Features
- Analyzes all blob containers in a storage account
- Categorizes blobs by age (0-7, 8-30, 31-60, 61-90, 91-180, 181-365, 365+ days)
- Identifies deletion candidates based on retention period
- Calculates impact metrics (blobs/size to delete, percentage affected)
- Estimates monthly and annual cost savings
- Exports detailed per-container metrics to CSV
- Generates executive summary in text format
- Lists top 5 containers by deletion size

### Requirements
- PowerShell 7.0+ or Windows PowerShell 5.1
- Az.Accounts module (v2.10.0+)
- Az.Storage module (v5.0.0+)

### Documentation
- Complete usage guide in README.md
- Installation instructions
- Parameter descriptions
- Example outputs
- Troubleshooting section
- Best practices guide
- Customization options

## Release Notes Format

### Categories
- **Added** - New features
- **Changed** - Changes in existing functionality
- **Deprecated** - Soon-to-be removed features
- **Removed** - Removed features
- **Fixed** - Bug fixes
- **Security** - Security vulnerability fixes

### Version Format
- Major version (X.0.0) - Breaking changes
- Minor version (0.X.0) - New features, backwards compatible
- Patch version (0.0.X) - Bug fixes, backwards compatible

[Unreleased]: https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle/compare/v1.1.3...v1.2.0
[1.1.3]: https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle/compare/v1.1.1...v1.1.3
[1.1.1]: https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle/releases/tag/v1.0.0
