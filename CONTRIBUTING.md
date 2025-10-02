# Contributing to Azure Storage Lifecycle Scripts

Thank you for considering contributing to this project! This document outlines the process for contributing and the standards we follow.

## How to Contribute

### Reporting Issues

If you find a bug or have a suggestion:

1. **Search existing issues** first to avoid duplicates
2. **Create a new issue** with a clear title and description
3. **Include details**:
   - PowerShell version
   - Azure module versions
   - Steps to reproduce (for bugs)
   - Expected vs actual behavior
   - Error messages or screenshots if applicable

### Submitting Changes

1. **Fork the repository**
2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes** following our coding standards
4. **Test thoroughly** on different scenarios
5. **Commit with clear messages**:
   ```bash
   git commit -m "Add feature: description of what changed"
   ```
6. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```
7. **Create a Pull Request** with a clear description of changes

## Coding Standards

### PowerShell Style Guide

- Use **4 spaces** for indentation (no tabs)
- Use **PascalCase** for function names and parameters
- Use **camelCase** for variables
- Include **comment-based help** for all functions
- Use **approved PowerShell verbs** (Get, Set, New, Remove, etc.)
- Write **descriptive variable names** (avoid single letters except in loops)

### Example:

```powershell
<#
.SYNOPSIS
    Brief description of function
.PARAMETER parameterName
    Description of parameter
#>
function Get-StorageInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$StorageAccountName
    )
    
    # Clear, descriptive comments
    $storageContext = Get-AzStorageAccount -Name $StorageAccountName
    
    return $storageContext
}
```

### Script Requirements

- **Error Handling**: Use try/catch blocks for external calls
- **Input Validation**: Validate all parameters
- **Progress Indication**: Use Write-Progress for long operations
- **Output Formatting**: Use consistent Write-Host colors:
  - Cyan: Headers/titles
  - Green: Success messages
  - Yellow: Warnings/important info
  - Red: Errors (use Write-Error)

### Documentation Standards

- Update **README.md** if you add features or change behavior
- Include **inline comments** for complex logic
- Add **examples** for new functionality
- Update **CHANGELOG.md** with your changes

## Testing Guidelines

Before submitting a PR, test your changes:

1. **Multiple scenarios**:
   - Empty containers
   - Large storage accounts
   - Different retention periods
   - Various Azure regions

2. **Error conditions**:
   - Invalid parameters
   - Missing permissions
   - Network issues

3. **Output validation**:
   - CSV exports correctly
   - Summary reports accurate
   - Console output readable

## Pull Request Process

1. **Update documentation** as needed
2. **Add to CHANGELOG.md** under "Unreleased" section
3. **Ensure tests pass** (manual testing currently)
4. **Request review** from maintainers
5. **Address feedback** promptly
6. **Squash commits** if requested before merge

## Code Review Criteria

Reviewers will check:

- ✅ Code follows PowerShell best practices
- ✅ Changes are well-documented
- ✅ No breaking changes (or properly documented)
- ✅ Error handling is appropriate
- ✅ Performance impact is acceptable
- ✅ Security considerations addressed

## Feature Requests

For new features:

1. **Open an issue first** to discuss the proposal
2. **Wait for feedback** before implementing
3. **Consider backwards compatibility**
4. **Provide use cases** for the feature

## Areas for Contribution

We welcome contributions in:

### Documentation
- Improve README clarity
- Add more examples
- Create video tutorials
- Translate to other languages

### Features
- Support for cool/archive tiers
- Azure CLI version
- JSON output format
- Email report functionality
- Dashboard/visualization
- Batch processing multiple accounts

### Testing
- Automated test suite
- Performance benchmarks
- Edge case handling

### Bug Fixes
- Address open issues
- Improve error messages
- Fix edge cases

## Questions?

Feel free to open an issue for:
- Clarification on contribution process
- Design discussions
- Architecture questions
- Best practice guidance

## Code of Conduct

### Our Standards

- **Be respectful** and inclusive
- **Be constructive** in criticism
- **Focus on the code**, not the person
- **Help others** learn and grow
- **Give credit** where due

### Unacceptable Behavior

- Harassment or discrimination
- Trolling or insulting comments
- Personal attacks
- Publishing private information
- Unprofessional conduct

### Enforcement

Violations may result in:
1. Warning
2. Temporary ban
3. Permanent ban

Report issues to repository maintainers.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Recognition

Contributors will be:
- Listed in CHANGELOG.md
- Mentioned in release notes
- Added to CONTRIBUTORS.md (if created)

Thank you for making this project better! 🎉
