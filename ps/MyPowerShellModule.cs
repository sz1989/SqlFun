using System;
using System.Management.Automation;
using System.IO;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using System.Collections.Generic;
using System.Linq;

namespace MyPowerShellModule
{
    // Configuration models
    public class FileAnalysisConfig
    {
        public int MaxFileSizeMB { get; set; } = 100;
        public List<string> AllowedExtensions { get; set; } = new();
        public List<string> BlockedExtensions { get; set; } = new();
        public bool EnableDetailedLogging { get; set; } = false;
        public string DefaultOutputFormat { get; set; } = "Standard";
        public SecurityConfig Security { get; set; } = new();
    }

    public class SecurityConfig
    {
        public bool AllowSystemFiles { get; set; } = false;
        public bool AllowHiddenFiles { get; set; } = true;
        public List<string> RestrictedPaths { get; set; } = new();
    }

    public class LoggingConfig
    {
        public string LogLevel { get; set; } = "Information";
        public bool EnableConsoleLogging { get; set; } = true;
        public bool EnableFileLogging { get; set; } = false;
        public string LogFilePath { get; set; } = "";
    }

    public class AppConfig
    {
        public FileAnalysisConfig FileAnalysis { get; set; } = new();
        public LoggingConfig Logging { get; set; } = new();
    }

    // Service interfaces
    public interface IFileAnalyzer
    {
        FileInfoResult AnalyzeFile(string path, bool detailed);
    }

    public interface IFileSizeFormatter
    {
        string FormatSize(long bytes);
    }

    public interface IFileValidator
    {
        ValidationResult ValidateFile(string path);
    }

    public interface IConfigurationService
    {
        AppConfig GetConfiguration();
        void ReloadConfiguration();
    }

    // Enhanced service implementations
    public class ConfigurationService : IConfigurationService
    {
        private readonly IConfiguration _configuration;
        private readonly ILogger<ConfigurationService> _logger;
        private AppConfig _cachedConfig;

        public ConfigurationService(IConfiguration configuration, ILogger<ConfigurationService> logger)
        {
            _configuration = configuration;
            _logger = logger;
            LoadConfiguration();
        }

        public AppConfig GetConfiguration()
        {
            return _cachedConfig ?? LoadConfiguration();
        }

        public void ReloadConfiguration()
        {
            _cachedConfig = LoadConfiguration();
            _logger.LogInformation("Configuration reloaded successfully");
        }

        private AppConfig LoadConfiguration()
        {
            try
            {
                var config = new AppConfig();
                _configuration.Bind(config);
                
                _logger.LogDebug("Configuration loaded: MaxFileSize={MaxFileSize}MB, AllowedExtensions={ExtensionCount}", 
                    config.FileAnalysis.MaxFileSizeMB, 
                    config.FileAnalysis.AllowedExtensions.Count);
                
                _cachedConfig = config;
                return config;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to load configuration, using defaults");
                return new AppConfig();
            }
        }
    }

    public class FileAnalyzer : IFileAnalyzer
    {
        private readonly ILogger<FileAnalyzer> _logger;
        private readonly IFileSizeFormatter _sizeFormatter;
        private readonly IFileValidator _validator;
        private readonly IConfigurationService _configService;

        public FileAnalyzer(
            ILogger<FileAnalyzer> logger, 
            IFileSizeFormatter sizeFormatter, 
            IFileValidator validator,
            IConfigurationService configService)
        {
            _logger = logger;
            _sizeFormatter = sizeFormatter;
            _validator = validator;
            _configService = configService;
        }

        public FileInfoResult AnalyzeFile(string path, bool detailed)
        {
            var config = _configService.GetConfiguration();
            
            if (config.FileAnalysis.EnableDetailedLogging)
            {
                _logger.LogDebug("Starting detailed analysis for file: {FilePath}", path);
            }
            else
            {
                _logger.LogInformation("Analyzing file: {FilePath}", path);
            }

            var validation = _validator.ValidateFile(path);
            if (!validation.IsValid)
            {
                throw new FileNotFoundException(validation.ErrorMessage);
            }

            var fileInfo = new FileInfo(path);
            
            // Check file size against configuration
            var fileSizeMB = fileInfo.Length / (1024.0 * 1024.0);
            if (fileSizeMB > config.FileAnalysis.MaxFileSizeMB)
            {
                _logger.LogWarning("File size ({SizeMB:F2} MB) exceeds configured maximum ({MaxMB} MB)", 
                    fileSizeMB, config.FileAnalysis.MaxFileSizeMB);
            }

            var result = new FileInfoResult
            {
                Name = fileInfo.Name,
                FullName = fileInfo.FullName,
                Extension = fileInfo.Extension,
                Size = fileInfo.Length,
                CreatedTime = fileInfo.CreationTime,
                ModifiedTime = fileInfo.LastWriteTime,
                AccessedTime = fileInfo.LastAccessTime,
                IsReadOnly = fileInfo.IsReadOnly,
                OutputFormat = config.FileAnalysis.DefaultOutputFormat
            };

            if (detailed)
            {
                result.Attributes = fileInfo.Attributes.ToString();
                result.Directory = fileInfo.DirectoryName;
                result.SizeFormatted = _sizeFormatter.FormatSize(fileInfo.Length);
                result.SizeMB = Math.Round(fileSizeMB, 2);
                result.IsWithinSizeLimit = fileSizeMB <= config.FileAnalysis.MaxFileSizeMB;
                
                if (config.FileAnalysis.EnableDetailedLogging)
                {
                    _logger.LogDebug("Detailed analysis completed - Name: {Name}, Size: {Size}, Format: {Format}", 
                        fileInfo.Name, result.SizeFormatted, result.OutputFormat);
                }
            }

            _logger.LogInformation("File analysis completed successfully");
            return result;
        }
    }

    public class FileSizeFormatter : IFileSizeFormatter
    {
        private readonly ILogger<FileSizeFormatter> _logger;
        private readonly string[] _suffixes = { "B", "KB", "MB", "GB", "TB", "PB" };

        public FileSizeFormatter(ILogger<FileSizeFormatter> logger)
        {
            _logger = logger;
        }

        public string FormatSize(long bytes)
        {
            if (bytes == 0) return "0 B";

            int counter = 0;
            decimal number = bytes;
            
            while (Math.Round(number / 1024) >= 1 && counter < _suffixes.Length - 1)
            {
                number /= 1024;
                counter++;
            }
            
            var result = $"{number:n1} {_suffixes[counter]}";
            _logger.LogTrace("Formatted {Bytes} bytes to {FormattedSize}", bytes, result);
            
            return result;
        }
    }

    public class FileValidator : IFileValidator
    {
        private readonly ILogger<FileValidator> _logger;
        private readonly IConfigurationService _configService;

        public FileValidator(ILogger<FileValidator> logger, IConfigurationService configService)
        {
            _logger = logger;
            _configService = configService;
        }

        public ValidationResult ValidateFile(string path)
        {
            var config = _configService.GetConfiguration();
            
            _logger.LogDebug("Validating file path: {FilePath}", path);

            if (string.IsNullOrWhiteSpace(path))
            {
                return new ValidationResult(false, "File path cannot be null or empty");
            }

            if (!File.Exists(path))
            {
                return new ValidationResult(false, $"File not found: {path}");
            }

            try
            {
                var fileInfo = new FileInfo(path);
                
                // Check restricted paths
                if (config.FileAnalysis.Security.RestrictedPaths.Any(restrictedPath => 
                    path.StartsWith(restrictedPath, StringComparison.OrdinalIgnoreCase)))
                {
                    return new ValidationResult(false, $"Access to path is restricted: {path}");
                }

                // Check system files
                if (!config.FileAnalysis.Security.AllowSystemFiles && 
                    (fileInfo.Attributes & FileAttributes.System) == FileAttributes.System)
                {
                    return new ValidationResult(false, $"System files are not allowed: {path}");
                }

                // Check hidden files
                if (!config.FileAnalysis.Security.AllowHiddenFiles && 
                    (fileInfo.Attributes & FileAttributes.Hidden) == FileAttributes.Hidden)
                {
                    return new ValidationResult(false, $"Hidden files are not allowed: {path}");
                }

                // Check file extension
                var extension = fileInfo.Extension.ToLowerInvariant();
                if (config.FileAnalysis.BlockedExtensions.Contains(extension))
                {
                    return new ValidationResult(false, $"File extension is blocked: {extension}");
                }

                if (config.FileAnalysis.AllowedExtensions.Any() && 
                    !config.FileAnalysis.AllowedExtensions.Contains(extension))
                {
                    return new ValidationResult(false, $"File extension is not in allowed list: {extension}");
                }

                // Test file access
                _ = fileInfo.Length;
                
                _logger.LogDebug("File validation successful");
                return new ValidationResult(true, null);
            }
            catch (UnauthorizedAccessException)
            {
                return new ValidationResult(false, $"Access denied to file: {path}");
            }
            catch (Exception ex)
            {
                return new ValidationResult(false, $"Error accessing file: {ex.Message}");
            }
        }
    }

    // Enhanced Dependency Injection Module
    public static class ServiceModule
    {
        private static ServiceProvider _serviceProvider;

        public static ServiceProvider GetServiceProvider(string configPath = null)
        {
            if (_serviceProvider == null)
            {
                var services = new ServiceCollection();

                // Build configuration from JSON file
                var configuration = BuildConfiguration(configPath);
                services.AddSingleton<IConfiguration>(configuration);

                // Configure logging based on configuration
                var loggingConfig = new LoggingConfig();
                configuration.GetSection("Logging").Bind(loggingConfig);
                
                services.AddLogging(builder =>
                {
                    if (loggingConfig.EnableConsoleLogging)
                    {
                        builder.AddConsole();
                    }

                    // Parse log level from configuration
                    if (Enum.TryParse<LogLevel>(loggingConfig.LogLevel, out var logLevel))
                    {
                        builder.SetMinimumLevel(logLevel);
                    }
                    else
                    {
                        builder.SetMinimumLevel(LogLevel.Information);
                    }
                });

                // Register services
                services.AddSingleton<IConfigurationService, ConfigurationService>();
                services.AddTransient<IFileAnalyzer, FileAnalyzer>();
                services.AddSingleton<IFileSizeFormatter, FileSizeFormatter>();
                services.AddTransient<IFileValidator, FileValidator>();

                _serviceProvider = services.BuildServiceProvider();
            }

            return _serviceProvider;
        }

        private static IConfiguration BuildConfiguration(string configPath = null)
        {
            var builder = new ConfigurationBuilder();

            // Add default configuration
            builder.AddInMemoryCollection(GetDefaultConfiguration());

            // Add JSON configuration file
            var jsonConfigPath = configPath ?? "fileanalysis-config.json";
            
            if (File.Exists(jsonConfigPath))
            {
                builder.AddJsonFile(jsonConfigPath, optional: false, reloadOnChange: true);
            }
            else
            {
                // Create default config file if it doesn't exist
                CreateDefaultConfigFile(jsonConfigPath);
                builder.AddJsonFile(jsonConfigPath, optional: true, reloadOnChange: true);
            }

            // Add environment variables with prefix
            builder.AddEnvironmentVariables("FILEANALYSIS_");

            return builder.Build();
        }

        private static Dictionary<string, string> GetDefaultConfiguration()
        {
            return new Dictionary<string, string>
            {
                {"FileAnalysis:MaxFileSizeMB", "100"},
                {"FileAnalysis:AllowedExtensions:0", ".txt"},
                {"FileAnalysis:AllowedExtensions:1", ".log"},
                {"FileAnalysis:AllowedExtensions:2", ".csv"},
                {"FileAnalysis:AllowedExtensions:3", ".json"},
                {"FileAnalysis:AllowedExtensions:4", ".xml"},
                {"FileAnalysis:EnableDetailedLogging", "false"},
                {"FileAnalysis:DefaultOutputFormat", "Standard"},
                {"FileAnalysis:Security:AllowSystemFiles", "false"},
                {"FileAnalysis:Security:AllowHiddenFiles", "true"},
                {"Logging:LogLevel", "Information"},
                {"Logging:EnableConsoleLogging", "true"},
                {"Logging:EnableFileLogging", "false"}
            };
        }

        private static void CreateDefaultConfigFile(string configPath)
        {
            var defaultConfig = new AppConfig
            {
                FileAnalysis = new FileAnalysisConfig
                {
                    MaxFileSizeMB = 100,
                    AllowedExtensions = new List<string> { ".txt", ".log", ".csv", ".json", ".xml", ".md" },
                    BlockedExtensions = new List<string> { ".exe", ".dll", ".bat", ".cmd" },
                    EnableDetailedLogging = false,
                    DefaultOutputFormat = "Standard",
                    Security = new SecurityConfig
                    {
                        AllowSystemFiles = false,
                        AllowHiddenFiles = true,
                        RestrictedPaths = new List<string> { "C:\\Windows\\System32", "C:\\Program Files" }
                    }
                },
                Logging = new LoggingConfig
                {
                    LogLevel = "Information",
                    EnableConsoleLogging = true,
                    EnableFileLogging = false,
                    LogFilePath = "fileanalysis.log"
                }
            };

            try
            {
                var json = System.Text.Json.JsonSerializer.Serialize(defaultConfig, new System.Text.Json.JsonSerializerOptions 
                { 
                    WriteIndented = true 
                });
                File.WriteAllText(configPath, json);
            }
            catch
            {
                // Ignore errors when creating default config file
            }
        }

        public static void DisposeServices()
        {
            _serviceProvider?.Dispose();
            _serviceProvider = null;
        }
    }

    // Updated PowerShell Cmdlet with JSON Configuration
    [Cmdlet(VerbsCommon.Get, "FileInfo")]
    [OutputType(typeof(FileInfoResult))]
    public class GetFileInfoCmdlet : PSCmdlet, IDisposable
    {
        private ServiceProvider _serviceProvider;
        private IFileAnalyzer _fileAnalyzer;
        private ILogger<GetFileInfoCmdlet> _logger;
        private IConfigurationService _configService;

        [Parameter(
            Mandatory = true,
            Position = 0,
            ValueFromPipeline = true,
            ValueFromPipelineByPropertyName = true,
            HelpMessage = "Path to the file to analyze")]
        [ValidateNotNullOrEmpty]
        public string Path { get; set; }

        [Parameter(
            Mandatory = false,
            HelpMessage = "Include detailed file information")]
        public SwitchParameter Detailed { get; set; }

        [Parameter(
            Mandatory = false,
            HelpMessage = "Path to custom configuration file")]
        public string ConfigPath { get; set; }

        [Parameter(
            Mandatory = false,
            HelpMessage = "Reload configuration from file")]
        public SwitchParameter ReloadConfig { get; set; }

        protected override void BeginProcessing()
        {
            try
            {
                // Initialize DI container with optional config path
                _serviceProvider = ServiceModule.GetServiceProvider(ConfigPath);
                _fileAnalyzer = _serviceProvider.GetRequiredService<IFileAnalyzer>();
                _logger = _serviceProvider.GetRequiredService<ILogger<GetFileInfoCmdlet>>();
                _configService = _serviceProvider.GetRequiredService<IConfigurationService>();

                if (ReloadConfig.IsPresent)
                {
                    _configService.ReloadConfiguration();
                    WriteVerbose("Configuration reloaded from file");
                }

                var config = _configService.GetConfiguration();
                _logger.LogInformation("Get-FileInfo cmdlet initialized - MaxFileSize: {MaxSize}MB, LogLevel: {LogLevel}", 
                    config.FileAnalysis.MaxFileSizeMB, config.Logging.LogLevel);
                
                WriteVerbose($"Starting Get-FileInfo cmdlet with configuration (Max size: {config.FileAnalysis.MaxFileSizeMB}MB)");
            }
            catch (Exception ex)
            {
                WriteError(new ErrorRecord(
                    ex,
                    "DIInitializationError",
                    ErrorCategory.InvalidOperation,
                    null));
            }
        }

        protected override void ProcessRecord()
        {
            try
            {
                string resolvedPath = GetResolvedProviderPathFromPSPath(Path, out ProviderInfo provider).FirstOrDefault();
                
                if (string.IsNullOrEmpty(resolvedPath))
                {
                    WriteError(new ErrorRecord(
                        new FileNotFoundException($"Cannot resolve path '{Path}'"),
                        "PathNotFound",
                        ErrorCategory.ObjectNotFound,
                        Path));
                    return;
                }

                _logger.LogInformation("Processing file: {ResolvedPath}", resolvedPath);

                var result = _fileAnalyzer.AnalyzeFile(resolvedPath, Detailed.IsPresent);

                WriteVerbose($"Successfully analyzed file: {result.Name}");
                if (Detailed.IsPresent)
                {
                    if (!string.IsNullOrEmpty(result.SizeFormatted))
                        WriteVerbose($"File size: {result.SizeFormatted}");
                    if (result.SizeMB.HasValue)
                        WriteVerbose($"Size limit check: {(result.IsWithinSizeLimit ? "PASS" : "EXCEED")}");
                }

                WriteObject(result);
            }
            catch (FileNotFoundException ex)
            {
                WriteError(new ErrorRecord(ex, "FileNotFound", ErrorCategory.ObjectNotFound, Path));
            }
            catch (UnauthorizedAccessException ex)
            {
                WriteError(new ErrorRecord(ex, "UnauthorizedAccess", ErrorCategory.PermissionDenied, Path));
            }
            catch (Exception ex)
            {
                _logger?.LogError(ex, "Error processing file: {FilePath}", Path);
                WriteError(new ErrorRecord(ex, "GeneralError", ErrorCategory.NotSpecified, Path));
            }
        }

        protected override void EndProcessing()
        {
            _logger?.LogInformation("Get-FileInfo cmdlet execution completed");
            WriteVerbose("Get-FileInfo cmdlet execution completed");
        }

        public void Dispose()
        {
            GC.SuppressFinalize(this);
        }
    }

    // Enhanced result class
    public class FileInfoResult
    {
        public string Name { get; set; }
        public string FullName { get; set; }
        public string Extension { get; set; }
        public long Size { get; set; }
        public string SizeFormatted { get; set; }
        public double? SizeMB { get; set; }
        public bool IsWithinSizeLimit { get; set; }
        public DateTime CreatedTime { get; set; }
        public DateTime ModifiedTime { get; set; }
        public DateTime AccessedTime { get; set; }
        public bool IsReadOnly { get; set; }
        public string Attributes { get; set; }
        public string Directory { get; set; }
        public string OutputFormat { get; set; }
    }

    public class ValidationResult
    {
        public bool IsValid { get; }
        public string ErrorMessage { get; }

        public ValidationResult(bool isValid, string errorMessage)
        {
            IsValid = isValid;
            ErrorMessage = errorMessage;
        }
    }
}