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

[Unreleased]: https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Phoenix-Software-Limited/pwsh-azure-storage-lifecycle/releases/tag/v1.0.0
