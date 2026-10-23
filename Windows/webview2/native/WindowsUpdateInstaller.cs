using System.Diagnostics;
using System.IO.Compression;
using System.Text.Json;

namespace QuotaView;

internal sealed record WindowsInstallPlan(string Target, string Package, WindowsRelease Release, int ParentId, long ParentStart);

internal static class WindowsUpdateInstaller
{
    internal static void NoLinks(string path)
    {
        for (var item = new DirectoryInfo(Path.GetFullPath(path)); item != null; item = item.Parent)
            if (item.Exists && (item.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Update path contains a symbolic link");
        if (File.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new IOException("Update file is a symbolic link");
    }

    internal static string Child(string root, string relative)
    {
        // Reject Windows aliases/ADS, device names, traversal, rooted and duplicate destinations.
        if (string.IsNullOrEmpty(relative) || relative.Contains('\\') || Path.IsPathRooted(relative) || relative.Split('/').Any(p =>
            p is "" or "." or ".." || p.EndsWith('.') || p.EndsWith(' ') || p.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 ||
            System.Text.RegularExpressions.Regex.IsMatch(p, @"^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)", System.Text.RegularExpressions.RegexOptions.IgnoreCase)))
            throw new InvalidDataException("Unsafe update archive path");
        var full = Path.GetFullPath(Path.Combine(root, relative));
        if (!full.StartsWith(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Update path escapes its directory");
        NoLinks(full);
        return full;
    }

    internal static List<string> Extract(string zipPath, string stage, string version)
    {
        Directory.CreateDirectory(stage); NoLinks(stage);
        using var zip = ZipFile.OpenRead(zipPath);
        var files = new List<string>(); var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        long total = 0;
        if (zip.Entries.Count > 15000) throw new InvalidDataException("Too many update files");
        foreach (var entry in zip.Entries)
        {
            var name = entry.FullName;
            if (name.EndsWith('/')) { Child(stage, name.TrimEnd('/')); continue; }
            var destination = Child(stage, name);
            if (!names.Add(name) || ((entry.ExternalAttributes >> 16) & 0xF000) == 0xA000 || (entry.ExternalAttributes & (int)FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Duplicate or linked update file");
            total = checked(total + entry.Length);
            if (total > 1024L * 1024 * 1024) throw new InvalidDataException("Update is too large to extract");
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            entry.ExtractToFile(destination, false);
            files.Add(name);
        }
        foreach (string required in new[] { "QuotaView.Native.exe", "QuotaView.Native.dll", "QuotaView.Native.runtimeconfig.json", "coreclr.dll", "hostfxr.dll", "app/package.json", "app/backend.js", "app/dist/renderer/index.html" })
            if (!names.Contains(required)) throw new InvalidDataException("Incomplete standalone Windows package: " + required);
        using var identity = JsonDocument.Parse(File.ReadAllText(Child(stage, "app/package.json")));
        if (identity.RootElement.GetProperty("version").GetString() != version) throw new InvalidDataException("Update package version mismatch");
        return files;
    }

    // Only files carried in the verified archive are replaced. User configuration lives outside Target.
    // Keep a journal before each write, so even the write that fails is restored on rollback.
    internal static void Apply(string stage, string target, string backup, IEnumerable<string> files, Action? beforeCommit = null)
    {
        NoLinks(target); NoLinks(backup);
        var journal = new List<(string Name, bool Existed)>();
        try
        {
            foreach (var name in files)
            {
                var source = Child(stage, name); var destination = Child(target, name); var saved = Child(backup, name);
                bool existed = File.Exists(destination);
                if (existed) { Directory.CreateDirectory(Path.GetDirectoryName(saved)!); File.Copy(destination, saved, false); }
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                journal.Add((name, existed));
                File.Copy(source, destination, true);
            }
            beforeCommit?.Invoke();
        }
        catch (Exception error)
        {
            var failures = new List<Exception>();
            foreach (var row in journal.AsEnumerable().Reverse())
            {
                try
                {
                    var destination = Child(target, row.Name);
                    if (row.Existed) File.Copy(Child(backup, row.Name), destination, true);
                    else if (File.Exists(destination)) File.Delete(destination);
                }
                catch (Exception rollbackError) { failures.Add(rollbackError); }
            }
            if (failures.Count > 0) throw new AggregateException("Update failed; backup retained for recovery", new[] { error }.Concat(failures));
            throw;
        }
    }

    internal static int Run(string planPath)
    {
        string job = Path.GetDirectoryName(Path.GetFullPath(planPath))!;
        string log = Path.Combine(job, "result.json");
        WindowsInstallPlan? plan = null;
        bool parentExited = false;
        try
        {
            NoLinks(planPath);
            plan = JsonSerializer.Deserialize<WindowsInstallPlan>(File.ReadAllText(planPath)) ?? throw new InvalidDataException("Missing update plan");
            if (Path.GetFullPath(plan.Package) != Path.Combine(job, "package.zip")) throw new InvalidDataException("Invalid update package path");
            string target = Path.GetFullPath(plan.Target).TrimEnd(Path.DirectorySeparatorChar);
            NoLinks(target);
            if (!File.Exists(Path.Combine(target, "QuotaView.Native.exe")) || target.StartsWith(job, StringComparison.OrdinalIgnoreCase) || job.StartsWith(target + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Invalid update installation directory");
            WindowsUpdatePolicy.Validate(plan.Release, WindowsUpdatePolicy.PublicKey);
            WindowsUpdatePolicy.VerifyPackage(plan.Package, plan.Release);
            var stage = Path.Combine(job, "install-" + Guid.NewGuid().ToString("N"));
            var files = Extract(plan.Package, stage, plan.Release.Version);
            File.WriteAllText(Path.Combine(job, "ready"), "ready");
            using (var parent = GetParent(plan))
            {
                if (parent != null && !parent.WaitForExit(60000)) throw new IOException("QuotaView did not exit; update was not installed");
            }
            parentExited = true;
            // Exclude another QuotaView instance from starting while binaries are being replaced.
            using (var mutex = new Mutex(false, @"Local\QuotaView.WebView2"))
            {
                bool locked;
                try { locked = mutex.WaitOne(10000); } catch (AbandonedMutexException) { locked = true; }
                if (!locked) throw new IOException("Another QuotaView instance is running");
                try { Apply(stage, target, Path.Combine(job, "backup"), files); }
                finally { mutex.ReleaseMutex(); }
            }
            File.WriteAllText(log, JsonSerializer.Serialize(new { ok = true, version = plan.Release.Version, target = plan.Target }));
            Restart(target);
            return 0;
        }
        catch (Exception e)
        {
            File.WriteAllText(log, JsonSerializer.Serialize(new { ok = false, error = e.Message, target = plan?.Target }));
            if (parentExited && plan != null) { try { Restart(plan.Target); } catch { } }
            return 1;
        }
    }
    static Process? GetParent(WindowsInstallPlan plan)
    {
        try
        {
            var process = Process.GetProcessById(plan.ParentId);
            if (process.StartTime.ToUniversalTime().Ticks == plan.ParentStart) return process;
            process.Dispose(); return null;
        }
        catch (ArgumentException) { return null; }
    }
    static void Restart(string target) => Process.Start(new ProcessStartInfo(Path.Combine(target, "QuotaView.Native.exe")) { WorkingDirectory = target, UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden });
}
