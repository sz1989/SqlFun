```
Import-Module .\bin\Debug\net8.0\MyPowerShellModule.dll
Get-FileInfo -Path "C:\temp\myfile.txt" -Detailed -Verbose
```

Dependency Injection Features:

Service Interfaces & Implementations:

IFileAnalyzer - Main file analysis logic
IFileSizeFormatter - File size formatting
IFileValidator - File validation logic


DI Container Setup:

Uses Microsoft.Extensions.DependencyInjection
Configured with logging, configuration, and custom services
Singleton pattern for the service provider


Logging Integration:

Uses Microsoft.Extensions.Logging
Structured logging with different log levels
Console logging provider


Configuration Support:

Uses Microsoft.Extensions.Configuration
In-memory configuration for settings