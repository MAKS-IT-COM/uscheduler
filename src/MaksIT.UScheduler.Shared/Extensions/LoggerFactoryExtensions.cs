using MaksIT.Core.Logging;
using Microsoft.Extensions.Logging;

namespace MaksIT.UScheduler.Shared.Extensions;

public static class LoggerFactoryExtensions
{
    /// <summary>
    /// Creates a logger that logs to a dedicated subfolder based on the file name.
    /// Uses the Folder: prefix pattern from MaksIT.Core.Logging.FileLoggerProvider.
    /// </summary>
    /// <param name="loggerFactory">The logger factory.</param>
    /// <param name="filePath">The file path to extract the folder name from.</param>
    /// <returns>An ILogger instance configured for folder-based logging.</returns>
    public static ILogger CreateFolderLogger(this ILoggerFactory loggerFactory, string filePath)
    {
        var fileName = Path.GetFileNameWithoutExtension(filePath);
        return loggerFactory.CreateLogger($"{LoggerPrefix.Folder}{fileName}");
    }
}
