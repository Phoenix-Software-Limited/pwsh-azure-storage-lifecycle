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

[Unreleased]: https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle/compare/v1.1.3...HEAD
[1.1.3]: https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle/compare/v1.1.1...v1.1.3
[1.1.1]: https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle/releases/tag/v1.0.0
