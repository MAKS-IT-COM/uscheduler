namespace MaksIT.UScheduler.Shared.Helpers;

/// <summary>
/// Resolves relative and absolute paths. Relative paths are resolved against a base directory;
/// absolute (rooted) paths are returned unchanged.
/// </summary>
public static class PathHelper
{
    /// <summary>
    /// Resolves a path against the application base directory.
    /// If the path is null, empty, or already rooted (absolute), returns it unchanged.
    /// </summary>
    /// <param name="path">The path to resolve.</param>
    /// <returns>The fully resolved absolute path, or the original value if rooted/null/empty.</returns>
    public static string ResolvePath(string path)
    {
        return ResolvePath(path, AppDomain.CurrentDomain.BaseDirectory);
    }

    /// <summary>
    /// Resolves a path against the specified base directory.
    /// If the path is null, empty, or already rooted (absolute), returns it unchanged.
    /// </summary>
    /// <param name="path">The path to resolve.</param>
    /// <param name="baseDirectory">The base directory for relative path resolution.</param>
    /// <returns>The fully resolved absolute path, or the original path if rooted/null/empty or base is null/empty.</returns>
    public static string ResolvePath(string path, string baseDirectory)
    {
        if (string.IsNullOrEmpty(path) || Path.IsPathRooted(path))
            return path;

        if (string.IsNullOrEmpty(baseDirectory))
            return path;

        return Path.GetFullPath(Path.Combine(baseDirectory, path));
    }
}
