using System;
using System.Collections.Generic;
using System.IO;
using Xunit;
using FluentAssertions;
using AutoFixture;
using AutoFixture.Xunit2;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using Moq;
using MyPowerShellModule;
using Microsoft.Extensions.DependencyInjection;

namespace MyPowerShellModule.Tests
{
    // Custom AutoData attributes for consistent test data generation
    public class AutoMoqDataAttribute : AutoDataAttribute
    {
        public AutoMoqDataAttribute() : base(() => new Fixture().Customize(new AutoMoqCustomization()))
        {
        }
    }

    public class InlineAutoMoqDataAttribute : InlineAutoDataAttribute
    {
        public InlineAutoMoqDataAttribute(params object[] values) : base(new AutoMoqDataAttribute(), values)
        {
        }
    }

    // Custom fixture customization for our domain
    public class AutoMoqCustomization : ICustomization
    {
        public void Customize(IFixture fixture)
        {
            fixture.Customize<FileInfoResult>(c => c
                .With(x => x.Size, () => fixture.Create<int>() % 1000000) // Reasonable file sizes
                .With(x => x.CreatedTime, () => DateTime.Now.AddDays(-fixture.Create<int>() % 365))
                .With(x => x.ModifiedTime, () => DateTime.Now.AddDays(-fixture.Create<int>() % 30))
                .With(x => x.AccessedTime, () => DateTime.Now.AddDays(-fixture.Create<int>() % 7)));

            fixture.Customize<FileAnalysisConfig>(c => c
                .With(x => x.MaxFileSizeMB, () => fixture.Create<int>() % 500 + 1)
                .With(x => x.AllowedExtensions, () => new List<string> { ".txt", ".log", ".csv" })
                .With(x => x.BlockedExtensions, () => new List<string> { ".exe", ".dll" }));
        }
    }

    // File Size Formatter Tests
    public class FileSizeFormatterTests
    {
        private readonly IFixture _fixture;
        private readonly Mock<ILogger<FileSizeFormatter>> _mockLogger;
        private readonly FileSizeFormatter _formatter;

        public FileSizeFormatterTests()
        {
            _fixture = new Fixture();
            _mockLogger = new Mock<ILogger<FileSizeFormatter>>();
            _formatter = new FileSizeFormatter(_mockLogger.Object);
        }

        [Theory]
        [InlineData(0, "0 B")]
        [InlineData(512, "512.0 B")]
        [InlineData(1024, "1.0 KB")]
        [InlineData(1536, "1.5 KB")]
        [InlineData(1048576, "1.0 MB")]
        [InlineData(1073741824, "1.0 GB")]
        [InlineData(2147483648, "2.0 GB")]
        public void FormatSize_WithVariousBytes_ShouldFormatCorrectly(long bytes, string expected)
        {
            // Act
            var result = _formatter.FormatSize(bytes);

            // Assert
            result.Should().Be(expected);
        }

        [Theory]
        [AutoMoqData]
        public void FormatSize_WithLargeRandomValue_ShouldNotThrow(long bytes)
        {
            // Arrange
            var positiveBytes = Math.Abs(bytes);

            // Act
            Action act = () => _formatter.FormatSize(positiveBytes);

            // Assert
            act.Should().NotThrow();
        }

        [Fact]
        public void FormatSize_ShouldLogTrace()
        {
            // Arrange
            const long testBytes = 1024;

            // Act
            _formatter.FormatSize(testBytes);

            // Assert
            _mockLogger.Verify(
                x => x.Log(
                    LogLevel.Trace,
                    It.IsAny<EventId>(),
                    It.Is<It.IsAnyType>((v, t) => v.ToString().Contains("Formatted")),
                    It.IsAny<Exception>(),
                    It.IsAny<Func<It.IsAnyType, Exception, string>>()),
                Times.Once);
        }
    }

    // Configuration Service Tests
    public class ConfigurationServiceTests
    {
        private readonly IFixture _fixture;
        private readonly Mock<ILogger<ConfigurationService>> _mockLogger;
        private readonly Mock<IConfiguration> _mockConfiguration;

        public ConfigurationServiceTests()
        {
            _fixture = new Fixture().Customize(new AutoMoqCustomization());
            _mockLogger = new Mock<ILogger<ConfigurationService>>();
            _mockConfiguration = new Mock<IConfiguration>();
        }

        [Theory]
        [AutoMoqData]
        public void GetConfiguration_WhenCalled_ShouldReturnConfiguration(
            FileAnalysisConfig fileConfig,
            LoggingConfig loggingConfig)
        {
            // Arrange
            SetupMockConfiguration(fileConfig, loggingConfig);
            var service = new ConfigurationService(_mockConfiguration.Object, _mockLogger.Object);

            // Act
            var result = service.GetConfiguration();

            // Assert
            result.Should().NotBeNull();
            result.FileAnalysis.Should().BeEquivalentTo(fileConfig);
            result.Logging.Should().BeEquivalentTo(loggingConfig);
        }

        [Fact]
        public void GetConfiguration_WhenConfigurationBindingFails_ShouldReturnDefaultConfig()
        {
            // Arrange
            _mockConfiguration.Setup(x => x.Bind(It.IsAny<object>()))
                .Throws(new InvalidOperationException("Binding failed"));
            var service = new ConfigurationService(_mockConfiguration.Object, _mockLogger.Object);

            // Act
            var result = service.GetConfiguration();

            // Assert
            result.Should().NotBeNull();
            result.Should().BeOfType<AppConfig>();
            _mockLogger.Verify(
                x => x.Log(
                    LogLevel.Error,
                    It.IsAny<EventId>(),
                    It.Is<It.IsAnyType>((v, t) => v.ToString().Contains("Failed to load configuration")),
                    It.IsAny<Exception>(),
                    It.IsAny<Func<It.IsAnyType, Exception, string>>()),
                Times.Once);
        }

        [Theory]
        [AutoMoqData]
        public void ReloadConfiguration_WhenCalled_ShouldLogReload(
            FileAnalysisConfig fileConfig,
            LoggingConfig loggingConfig)
        {
            // Arrange
            SetupMockConfiguration(fileConfig, loggingConfig);
            var service = new ConfigurationService(_mockConfiguration.Object, _mockLogger.Object);

            // Act
            service.ReloadConfiguration();

            // Assert
            _mockLogger.Verify(
                x => x.Log(
                    LogLevel.Information,
                    It.IsAny<EventId>(),
                    It.Is<It.IsAnyType>((v, t) => v.ToString().Contains("Configuration reloaded")),
                    It.IsAny<Exception>(),
                    It.IsAny<Func<It.IsAnyType, Exception, string>>()),
                Times.Once);
        }

        private void SetupMockConfiguration(FileAnalysisConfig fileConfig, LoggingConfig loggingConfig)
        {
            _mockConfiguration.Setup(x => x.Bind(It.IsAny<AppConfig>()))
                .Callback<object>(config =>
                {
                    if (config is AppConfig appConfig)
                    {
                        appConfig.FileAnalysis = fileConfig;
                        appConfig.Logging = loggingConfig;
                    }
                });
        }
    }

    // File Validator Tests
    public class FileValidatorTests
    {
        private readonly IFixture _fixture;
        private readonly Mock<ILogger<FileValidator>> _mockLogger;
        private readonly Mock<IConfigurationService> _mockConfigService;
        private readonly FileValidator _validator;
        private readonly string _tempFilePath;

        public FileValidatorTests()
        {
            _fixture = new Fixture().Customize(new AutoMoqCustomization());
            _mockLogger = new Mock<ILogger<FileValidator>>();
            _mockConfigService = new Mock<IConfigurationService>();
            _validator = new FileValidator(_mockLogger.Object, _mockConfigService.Object);
            
            // Create a temporary file for testing
            _tempFilePath = Path.GetTempFileName();
            File.WriteAllText(_tempFilePath, "Test content");
        }

        [Fact]
        public void ValidateFile_WithNullPath_ShouldReturnInvalid()
        {
            // Arrange
            SetupDefaultConfiguration();

            // Act
            var result = _validator.ValidateFile(null);

            // Assert
            result.IsValid.Should().BeFalse();
            result.ErrorMessage.Should().Contain("cannot be null or empty");
        }

        [Fact]
        public void ValidateFile_WithEmptyPath_ShouldReturnInvalid()
        {
            // Arrange
            SetupDefaultConfiguration();

            // Act
            var result = _validator.ValidateFile("");

            // Assert
            result.IsValid.Should().BeFalse();
            result.ErrorMessage.Should().Contain("cannot be null or empty");
        }

        [Fact]
        public void ValidateFile_WithNonExistentFile_ShouldReturnInvalid()
        {
            // Arrange
            SetupDefaultConfiguration();
            var nonExistentPath = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());

            // Act
            var result = _validator.ValidateFile(nonExistentPath);

            // Assert
            result.IsValid.Should().BeFalse();
            result.ErrorMessage.Should().Contain("File not found");
        }

        [Fact]
        public void ValidateFile_WithValidFile_ShouldReturnValid()
        {
            // Arrange
            SetupDefaultConfiguration();

            // Act
            var result = _validator.ValidateFile(_tempFilePath);

            // Assert
            result.IsValid.Should().BeTrue();
            result.ErrorMessage.Should().BeNull();
        }

        [Theory]
        [InlineAutoMoqData(".exe")]
        [InlineAutoMoqData(".dll")]
        public void ValidateFile_WithBlockedExtension_ShouldReturnInvalid(string blockedExtension)
        {
            // Arrange
            var config = _fixture.Create<AppConfig>();
            config.FileAnalysis.BlockedExtensions = new List<string> { blockedExtension };
            _mockConfigService.Setup(x => x.GetConfiguration()).Returns(config);

            var testFile = Path.ChangeExtension(_tempFilePath, blockedExtension);
            File.Move(_tempFilePath, testFile);

            // Act
            var result = _validator.ValidateFile(testFile);

            // Assert
            result.IsValid.Should().BeFalse();
            result.ErrorMessage.Should().Contain("extension is blocked");

            // Cleanup
            File.Delete(testFile);
        }

        [Theory]
        [InlineAutoMoqData(".txt")]
        [InlineAutoMoqData(".log")]
        public void ValidateFile_WithAllowedExtension_ShouldReturnValid(string allowedExtension)
        {
            // Arrange
            var config = _fixture.Create<AppConfig>();
            config.FileAnalysis.AllowedExtensions = new List<string> { allowedExtension };
            config.FileAnalysis.BlockedExtensions = new List<string>();
            _mockConfigService.Setup(x => x.GetConfiguration()).Returns(config);

            var testFile = Path.ChangeExtension(_tempFilePath, allowedExtension);
            File.Move(_tempFilePath, testFile);

            // Act
            var result = _validator.ValidateFile(testFile);

            // Assert
            result.IsValid.Should().BeTrue();

            // Cleanup
            File.Delete(testFile);
        }

        [Fact]
        public void ValidateFile_WithRestrictedPath_ShouldReturnInvalid()
        {
            // Arrange
            var config = _fixture.Create<AppConfig>();
            var restrictedPath = Path.GetDirectoryName(_tempFilePath);
            config.FileAnalysis.Security.RestrictedPaths = new List<string> { restrictedPath };
            _mockConfigService.Setup(x => x.GetConfiguration()).Returns(config);

            // Act
            var result = _validator.ValidateFile(_tempFilePath);

            // Assert
            result.IsValid.Should().BeFalse();
            result.ErrorMessage.Should().Contain("Access to path is restricted");
        }

        private void SetupDefaultConfiguration()
        {
            var config = _fixture.Create<AppConfig>();
            config.FileAnalysis.AllowedExtensions = new List<string>();
            config.FileAnalysis.BlockedExtensions = new List<string>();
            config.FileAnalysis.Security.RestrictedPaths = new List<string>();
            config.FileAnalysis.Security.AllowSystemFiles = true;
            config.FileAnalysis.Security.AllowHiddenFiles = true;
            _mockConfigService.Setup(x => x.GetConfiguration()).Returns(config);
        }

        public void Dispose()
        {
            if (File.Exists(_tempFilePath))
                File.Delete(_tempFilePath);
        }
    }

    // File Analyzer Tests
    public class FileAnalyzerTests
    {
        private readonly IFixture _fixture;
        private readonly Mock<ILogger<FileAnalyzer>> _mockLogger;
        private readonly Mock<IFileSizeFormatter> _mockSizeFormatter;
        private readonly Mock<IFileValidator> _mockValidator;
        private readonly Mock<IConfigurationService> _mockConfigService;
        private readonly FileAnalyzer _analyzer;
        private readonly string _tempFilePath;

        public FileAnalyzerTests()
        {
            _fixture = new Fixture().Customize(new AutoMoqCustomization());
            _mockLogger = new Mock<ILogger<FileAnalyzer>>();
            _mockSizeFormatter = new Mock<IFileSizeFormatter>();
            _mockValidator = new Mock<IFileValidator>();
            _mockConfigService = new Mock<IConfigurationService>();
            _analyzer = new FileAnalyzer(_mockLogger.Object, _mockSizeFormatter.Object, 
                _mockValidator.Object, _mockConfigService.Object);

            // Create a temporary file for testing
            _tempFilePath = Path.GetTempFileName();
            File.WriteAllText(_tempFilePath, "Test content for file analysis");
        }

        [Theory]
        [AutoMoqData]
        public void AnalyzeFile_WithValidFile_ShouldReturnFileInfo(AppConfig config)
        {
            // Arrange
            config.FileAnalysis.MaxFileSizeMB = 100;
            _mockConfigService.Setup(x => x.GetConfiguration()).Returns(config);
            _mockValidator.Setup(x => x.ValidateFile(_tempFilePath))
                .Returns(new ValidationResult(true, null));
            _mockSizeFormatter.Setup(x => x.FormatSize(It.IsAny<long>()))
                .Returns("25.0 B");

            // Act
            var result = _analyzer.AnalyzeFile(_tempFilePath, detailed: false);

            // Assert
            result.Should().NotBeNull();
            result.Name.Should().Be(Path.GetFileName(_tempFilePath));
            result.FullName.Should().Be(_tempFilePath);
            result.Size.Should().BeGreaterThan(0);
            result.OutputFormat.Should().Be(config.FileAnalysis.DefaultOutputFormat);
        }

        [Theory]
        [AutoMoqData]
        public void AnalyzeFile_WithDetailedFlag_ShouldIncludeDetailedInfo(AppConfig config)
        {
            // Arrange
            config.FileAnalysis.MaxFileSizeMB = 100;
            _mockConfigService.Setup(x => x.GetConfiguration()).Returns(config);
            _mockValidator.Setup(x => x.ValidateFile(_tempFilePath))
                .Returns(new ValidationResult(true, null));
            _mockSizeFormatter.Setup(x => x.FormatSize(It.IsAny<long>()))
                .Returns("25.0 B");

            // Act
            var result = _analyzer.AnalyzeFile(_tempFilePath, detailed: true);

            // Assert
            result.Should().NotBeNull();
            result.SizeFormatted.Should().Be("25.0 B");
            result.SizeMB.Should().HaveValue();
            result.IsWithinSizeLimit.Should().BeTrue();
            result.Attributes.Should().NotBeNullOrEmpty();
            result.Directory.Should().NotBeNullOrEmpty();

            _mockSizeFormatter.Verify(x => x.FormatSize(It.IsAny<long>()), Times.Once);
        }

        [Theory]
        [AutoMoqData]
        public void AnalyzeFile_WithInvalidFile_ShouldThrowException(AppConfig config)
        {
            // Arrange
            var errorMessage = "File validation failed";
            _mockConfigService.Setup(x => x.GetConfiguration()).Returns(config);
            _mockValidator.Setup(x => x.ValidateFile(_tempFilePath))
                .Returns(new ValidationResult(false, errorMessage));

            // Act
            Action act = () => _analyzer.AnalyzeFile(_tempFilePath, detailed: false);

            // Assert
            act.Should().Throw<FileNotFoundException>()
                .WithMessage(errorMessage);
        }

        [Theory]
        [AutoMoqData]
        public void AnalyzeFile_WithLargeFile_ShouldLogWarning(AppConfig config)
        {
            // Arrange
            config.FileAnalysis.MaxFileSizeMB = 1; // Very small limit
            config.FileAnalysis.EnableDetailedLogging = false;
            _mockConfigService.Setup(x => x.GetConfiguration()).Returns(config);
            _mockValidator.Setup(x => x.ValidateFile(_tempFilePath))
                .Returns(new ValidationResult(true, null));

            // Act
            var result = _analyzer.AnalyzeFile(_tempFilePath, detailed: false);

            // Assert
            result.Should().NotBeNull();
            _mockLogger.Verify(
                x => x.Log(
                    LogLevel.Warning,
                    It.IsAny<EventId>(),
                    It.Is<It.IsAnyType>((v, t) => v.ToString().Contains("exceeds configured maximum")),
                    It.IsAny<Exception>(),
                    It.IsAny<Func<It.IsAnyType, Exception, string>>()),
                Times.Once);
        }

        [Theory]
        [AutoMoqData]
        public void AnalyzeFile_WithDetailedLoggingEnabled_ShouldLogDebugInfo(AppConfig config)
        {
            // Arrange
            config.FileAnalysis.EnableDetailedLogging = true;
            _mockConfigService.Setup(x => x.GetConfiguration()).Returns(config);
            _mockValidator.Setup(x => x.ValidateFile(_tempFilePath))
                .Returns(new ValidationResult(true, null));
            _mockSizeFormatter.Setup(x => x.FormatSize(It.IsAny<long>()))
                .Returns("25.0 B");

            // Act
            var result = _analyzer.AnalyzeFile(_tempFilePath, detailed: true);

            // Assert
            result.Should().NotBeNull();
            _mockLogger.Verify(
                x => x.Log(
                    LogLevel.Debug,
                    It.IsAny<EventId>(),
                    It.Is<It.IsAnyType>((v, t) => v.ToString().Contains("Starting detailed analysis")),
                    It.IsAny<Exception>(),
                    It.IsAny<Func<It.IsAnyType, Exception, string>>()),
                Times.Once);
        }

        public void Dispose()
        {
            if (File.Exists(_tempFilePath))
                File.Delete(_tempFilePath);
        }
    }

    // Integration Tests
    public class ServiceModuleIntegrationTests
    {
        [Fact]
        public void GetServiceProvider_ShouldRegisterAllServices()
        {
            // Act
            using var serviceProvider = ServiceModule.GetServiceProvider();

            // Assert
            serviceProvider.Should().NotBeNull();
            
            var fileAnalyzer = serviceProvider.GetService<IFileAnalyzer>();
            var sizeFormatter = serviceProvider.GetService<IFileSizeFormatter>();
            var validator = serviceProvider.GetService<IFileValidator>();
            var configService = serviceProvider.GetService<IConfigurationService>();

            fileAnalyzer.Should().NotBeNull();
            fileAnalyzer.Should().BeOfType<FileAnalyzer>();
            
            sizeFormatter.Should().NotBeNull();
            sizeFormatter.Should().BeOfType<FileSizeFormatter>();
            
            validator.Should().NotBeNull();
            validator.Should().BeOfType<FileValidator>();
            
            configService.Should().NotBeNull();
            configService.Should().BeOfType<ConfigurationService>();
        }

        [Fact]
        public void GetServiceProvider_WithCustomConfigPath_ShouldUseCustomConfiguration()
        {
            // Arrange
            var customConfigPath = Path.GetTempFileName();
            var customConfig = new AppConfig
            {
                FileAnalysis = new FileAnalysisConfig
                {
                    MaxFileSizeMB = 999,
                    DefaultOutputFormat = "CustomFormat"
                }
            };

            var json = System.Text.Json.JsonSerializer.Serialize(customConfig, 
                new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(customConfigPath, json);

            try
            {
                // Act
                using var serviceProvider = ServiceModule.GetServiceProvider(customConfigPath);
                var configService = serviceProvider.GetRequiredService<IConfigurationService>();
                var config = configService.GetConfiguration();

                // Assert
                config.FileAnalysis.MaxFileSizeMB.Should().Be(999);
                config.FileAnalysis.DefaultOutputFormat.Should().Be("CustomFormat");
            }
            finally
            {
                if (File.Exists(customConfigPath))
                    File.Delete(customConfigPath);
            }
        }
    }

    // Validation Result Tests
    public class ValidationResultTests
    {
        [Theory]
        [AutoMoqData]
        public void ValidationResult_WithValidParameters_ShouldSetProperties(bool isValid, string errorMessage)
        {
            // Act
            var result = new ValidationResult(isValid, errorMessage);

            // Assert
            result.IsValid.Should().Be(isValid);
            result.ErrorMessage.Should().Be(errorMessage);
        }

        [Fact]
        public void ValidationResult_WithSuccessfulValidation_ShouldHaveNoError()
        {
            // Act
            var result = new ValidationResult(true, null);

            // Assert
            result.IsValid.Should().BeTrue();
            result.ErrorMessage.Should().BeNull();
        }

        [Theory]
        [AutoMoqData]
        public void ValidationResult_WithFailedValidation_ShouldHaveError(string errorMessage)
        {
            // Act
            var result = new ValidationResult(false, errorMessage);

            // Assert
            result.IsValid.Should().BeFalse();
            result.ErrorMessage.Should().Be(errorMessage);
        }
    }

    // FileInfoResult Tests
    public class FileInfoResultTests
    {
        private readonly IFixture _fixture;

        public FileInfoResultTests()
        {
            _fixture = new Fixture().Customize(new AutoMoqCustomization());
        }

        [Theory]
        [AutoMoqData]
        public void FileInfoResult_ShouldBeCreatedWithAutoFixture(FileInfoResult result)
        {
            // Assert
            result.Should().NotBeNull();
            result.Name.Should().NotBeNullOrEmpty();
            result.Size.Should().BeGreaterOrEqualTo(0);
            result.CreatedTime.Should().BeBefore(DateTime.Now);
            result.ModifiedTime.Should().BeBefore(DateTime.Now);
            result.AccessedTime.Should().BeBefore(DateTime.Now);
        }

        [Fact]
        public void FileInfoResult_AllProperties_ShouldBeSettable()
        {
            // Arrange
            var result = new FileInfoResult();
            var testData = _fixture.Create<FileInfoResult>();

            // Act
            result.Name = testData.Name;
            result.FullName = testData.FullName;
            result.Extension = testData.Extension;
            result.Size = testData.Size;
            result.SizeFormatted = testData.SizeFormatted;
            result.SizeMB = testData.SizeMB;
            result.IsWithinSizeLimit = testData.IsWithinSizeLimit;
            result.CreatedTime = testData.CreatedTime;
            result.ModifiedTime = testData.ModifiedTime;
            result.AccessedTime = testData.AccessedTime;
            result.IsReadOnly = testData.IsReadOnly;
            result.Attributes = testData.Attributes;
            result.Directory = testData.Directory;
            result.OutputFormat = testData.OutputFormat;

            // Assert
            result.Should().BeEquivalentTo(testData);
        }
    }
}