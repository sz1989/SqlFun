using System;
using System.Management.Automation;
using System.IO;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using System.Collections.Generic;

namespace MyPowerShellModule
{
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

    // Service implementations
    public class FileAnalyzer : IFileAnalyzer
    {
        private readonly ILogger<FileAnalyzer> _logger;
        private readonly IFileSizeFormatter _sizeFormatter;
        private readonly IFileValidator _validator;

        public FileAnalyzer(ILogger<FileAnalyzer> logger, IFileSizeFormatter sizeFormatter, IFileValidator validator)
        {
            _logger = logger;
            _sizeFormatter = sizeFormatter;
            _validator = validator;
        }

        public FileInfoResult AnalyzeFile(string path, bool detailed)
        {
            _logger.LogInformation("Analyzing file: {FilePath}", path);

            var validation = _validator.ValidateFile(path);
            if (!validation.IsValid)
            {
                throw new FileNotFoundException(validation.ErrorMessage);
            }

            var fileInfo = new FileInfo(path);
            
            var result = new FileInfoResult
            {
                Name = fileInfo.Name,
                FullName = fileInfo.FullName,
                Extension = fileInfo.Extension,
                Size = fileInfo.Length,
                CreatedTime = fileInfo.CreationTime,
                ModifiedTime = fileInfo.LastWriteTime,
                AccessedTime = fileInfo.LastAccessTime,
                IsReadOnly = fileInfo.IsReadOnly
            };

            if (detailed)
            {
                result.Attributes = fileInfo.Attributes.ToString();
                result.Directory = fileInfo.DirectoryName;
                result.SizeFormatted = _sizeFormatter.FormatSize(fileInfo.Length);
                
                _logger.LogDebug("Detailed analysis completed for {FileName}, Size: {Size}", 
                    fileInfo.Name, result.SizeFormatted);
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

        public FileValidator(ILogger<FileValidator> logger)
        {
            _logger = logger;
        }

        public ValidationResult ValidateFile(string path)
        {
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
                // Test if we can access the file
                var fileInfo = new FileInfo(path);
                _ = fileInfo.Length; // This will throw if we can't access
                
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

    // Dependency Injection Module Initializer
    public static class ServiceModule
    {
        private static ServiceProvider _serviceProvider;

        public static ServiceProvider GetServiceProvider()
        {
            if (_serviceProvider == null)
            {
                var services = new ServiceCollection();

                // Configure logging
                services.AddLogging(builder =>
                {
                    builder.AddConsole();
                    builder.SetMinimumLevel(LogLevel.Information);
                });

                // Configure configuration
                services.AddSingleton<IConfiguration>(provider =>
                {
                    return new ConfigurationBuilder()
                        .AddInMemoryCollection(new Dictionary<string, string>
                        {
                            {"FileAnalysis:MaxFileSizeMB", "100"},
                            {"FileAnalysis:AllowedExtensions", ".txt,.log,.csv,.json,.xml"}
                        })
                        .Build();
                });

                // Register services
                services.AddTransient<IFileAnalyzer, FileAnalyzer>();
                services.AddSingleton<IFileSizeFormatter, FileSizeFormatter>();
                services.AddTransient<IFileValidator, FileValidator>();

                _serviceProvider = services.BuildServiceProvider();
            }

            return _serviceProvider;
        }

        public static void DisposeServices()
        {
            _serviceProvider?.Dispose();
            _serviceProvider = null;
        }
    }

    // Updated PowerShell Cmdlet with DI
    [Cmdlet(VerbsCommon.Get, "FileInfo")]
    [OutputType(typeof(FileInfoResult))]
    public class GetFileInfoCmdlet : PSCmdlet, IDisposable
    {
        private ServiceProvider _serviceProvider;
        private IFileAnalyzer _fileAnalyzer;
        private ILogger<GetFileInfoCmdlet> _logger;

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

        protected override void BeginProcessing()
        {
            try
            {
                // Initialize DI container
                _serviceProvider = ServiceModule.GetServiceProvider();
                _fileAnalyzer = _serviceProvider.GetRequiredService<IFileAnalyzer>();
                _logger = _serviceProvider.GetRequiredService<ILogger<GetFileInfoCmdlet>>();

                _logger.LogInformation("Get-FileInfo cmdlet initialized with dependency injection");
                WriteVerbose("Starting Get-FileInfo cmdlet execution with DI services");
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
                // Resolve the PowerShell path
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

                // Use injected service to analyze the file
                var result = _fileAnalyzer.AnalyzeFile(resolvedPath, Detailed.IsPresent);

                WriteVerbose($"Successfully analyzed file: {result.Name}");
                if (Detailed.IsPresent && !string.IsNullOrEmpty(result.SizeFormatted))
                {
                    WriteVerbose($"File size: {result.SizeFormatted}");
                }

                WriteObject(result);
            }
            catch (FileNotFoundException ex)
            {
                WriteError(new ErrorRecord(
                    ex,
                    "FileNotFound",
                    ErrorCategory.ObjectNotFound,
                    Path));
            }
            catch (UnauthorizedAccessException ex)
            {
                WriteError(new ErrorRecord(
                    ex,
                    "UnauthorizedAccess",
                    ErrorCategory.PermissionDenied,
                    Path));
            }
            catch (Exception ex)
            {
                _logger?.LogError(ex, "Error processing file: {FilePath}", Path);
                WriteError(new ErrorRecord(
                    ex,
                    "GeneralError",
                    ErrorCategory.NotSpecified,
                    Path));
            }
        }

        protected override void EndProcessing()
        {
            _logger?.LogInformation("Get-FileInfo cmdlet execution completed");
            WriteVerbose("Get-FileInfo cmdlet execution completed");
        }

        public void Dispose()
        {
            // Note: We don't dispose the service provider here as it's shared
            // In a real-world scenario, you might want to use a scoped lifetime
            GC.SuppressFinalize(this);
        }
    }

    // Supporting classes
    public class FileInfoResult
    {
        public string Name { get; set; }
        public string FullName { get; set; }
        public string Extension { get; set; }
        public long Size { get; set; }
        public string SizeFormatted { get; set; }
        public DateTime CreatedTime { get; set; }
        public DateTime ModifiedTime { get; set; }
        public DateTime AccessedTime { get; set; }
        public bool IsReadOnly { get; set; }
        public string Attributes { get; set; }
        public string Directory { get; set; }
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