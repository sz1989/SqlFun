```
Import-Module .\bin\Debug\net8.0\MyPowerShellModule.dll
Get-FileInfo -Path "C:\temp\myfile.txt" -Detailed -Verbose

# Use default configuration
Get-FileInfo -Path "C:\temp\myfile.txt" -Detailed

# Use custom configuration file
Get-FileInfo -Path "C:\temp\myfile.txt" -ConfigPath "custom-config.json"

# Reload configuration during execution
Get-FileInfo -Path "C:\temp\myfile.txt" -ReloadConfig -Detailed

# Environment variable override
$env:FILEANALYSIS_FileAnalysis__MaxFileSizeMB = "50"
Get-FileInfo -Path "C:\temp\myfile.txt"
```

```
# Restore packages
dotnet restore

# Run all tests
dotnet test

# Run with coverage
dotnet test --collect:"XPlat Code Coverage"

# Run specific test class
dotnet test --filter ClassName=FileAnalyzerTests

# Run with verbose output
dotnet test --logger:console;verbosity=detailed
```

# Dependency Injection Features:

## Service Interfaces & Implementations:

IFileAnalyzer - Main file analysis logic
IFileSizeFormatter - File size formatting
IFileValidator - File validation logic


# DI Container Setup:

Uses Microsoft.Extensions.DependencyInjection
Configured with logging, configuration, and custom services
Singleton pattern for the service provider

# Logging Integration:

## Uses Microsoft.Extensions.Logging
## Structured logging with different log levels
## Console logging provider

## Configuration Support:

Uses Microsoft.Extensions.Configuration
In-memory configuration for settings