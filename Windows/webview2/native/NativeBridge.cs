using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Microsoft.Win32.SafeHandles;

namespace QuotaView;

// This COM object is available ONLY in the private backend WebView, never in
// renderer windows. Renderers receive the allowlisted quotaView message API.
[ComVisible(true), ClassInterface(ClassInterfaceType.AutoDual)]
public sealed partial class NativeBridge
{
    internal readonly Host Host;
    readonly ConcurrentQueue<string> events = new();
    readonly Dictionary<int, FileStream> files = new();
    readonly Dictionary<int, IEnumerator<FileSystemInfo>> directories = new();
    int nextHandle;
    WindowsUpdater? updater;
    internal string AppRoot => Path.Combine(AppContext.BaseDirectory, "app");
    internal string DataRoot
    {
        get;
    }
    internal NativeBridge(Host host)
    {
        Host = host;
        DataRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "QuotaView WebView2");
    }
    public string Request(string json)
    {
        try
        {
            var r = JsonNode.Parse(json)!;
            var v = Invoke(S(r, "method"), r["args"]!.AsArray());
            return new JsonObject { ["value"] = v }.ToJsonString();
        }
        catch (Exception e) { return new JsonObject { ["error"] = e.Message, ["code"] = Code(e) }.ToJsonString(); }
    }
    public string Drain()
    {
        var batch = new List<string>();
        int bytes = 0;
        while (bytes < 2_000_000 && batch.Count < 512 && events.TryDequeue(out var row))
        {
            batch.Add(row);
            bytes += row.Length;
        }
        return "[" + string.Join(',', batch) + "]";
    }
    internal bool HasEvents => !events.IsEmpty;
    internal void Emit(object value)
    {
        events.Enqueue(System.Text.Json.JsonSerializer.Serialize(value));
        Host.ScheduleEvents();
    }
    internal static string S(JsonNode? n, string k, string fallback = "") => n?[k]?.GetValue<string>() ?? fallback;
    internal static string A(JsonArray a, int i, string fallback = "") => a.Count > i && a[i] != null ? a[i]!.ToString() : fallback;
    internal static int I(JsonArray a, int i, int fallback = 0) => a.Count > i && a[i] != null ? a[i]!.GetValue<int>() : fallback;
    internal static bool B(JsonArray a, int i) => a.Count > i && a[i]?.GetValue<bool>() == true;
    internal static JsonNode? Node(object? o) => System.Text.Json.JsonSerializer.SerializeToNode(o);
    static string Code(Exception e) => e.Message == "ESRCH" ? "ESRCH" : e is FileNotFoundException or DirectoryNotFoundException ? "ENOENT" : e is UnauthorizedAccessException ? "EACCES" : e is IOException && ((e.HResult & 65535) == 80 || (e.HResult & 65535) == 183) ? "EEXIST" : e is ArgumentException ? "EINVAL" : "EIO";
    internal JsonNode? Invoke(string method, JsonArray a)
    {
        if (method == "bootstrap")
            return Node(new
            {
                home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                temp = Path.GetTempPath(),
                cwd = AppRoot,
                dataDir = DataRoot,
                version = BuildIdentity.Version,
                locale = CultureInfo.CurrentUICulture.Name,
                osRelease = Environment.OSVersion.Version.ToString(),
                env = Environment.GetEnvironmentVariables().Cast<System.Collections.DictionaryEntry>().ToDictionary(x => x.Key.ToString()!, x => x.Value?.ToString()),
                process = new
                {
                    platform = "win32",
                    arch = "x64",
                    pid = Environment.ProcessId,
                    execPath = Environment.ProcessPath,
                    appRoot = AppRoot,
                    resourcesPath = AppRoot,
                    argv = new[] { Environment.ProcessPath!, "main.cjs" }.Concat(Environment.GetCommandLineArgs().Skip(1)).ToArray()
                }
            });
        if (method == "log")
        {
            Host.Log(A(a, 0));
            return null;
        }
        if (method == "async")
        {
            var id = A(a, 0);
            var op = A(a, 1);
            var args = a[2]!.AsArray().DeepClone().AsArray();
            Host.BeginInvoke(async () => { try { var result = await Async(op, args); Emit(new { id, type = "result", value = result }); } catch (Exception e) { Emit(new { id, type = "result", error = e.Message, code = Code(e) }); } });
            return null;
        }
        if (method == "path")
            return PathOp(a);
        if (method == "hash")
            return JsonValue.Create(Convert.ToBase64String(SHA256.HashData(Convert.FromBase64String(A(a, 1)))));
        if (method.StartsWith("fs."))
            return FileOp(method[3..], a);
        if (method.StartsWith("process."))
            return ProcessOp(method[8..], a);
        if (method.StartsWith("socket.") || method.StartsWith("server."))
            return NetworkOp(method, a);
        return Host.InvokeNative(method, a);
    }
    async Task<JsonNode?> Async(string method, JsonArray args)
    {
        if (method.StartsWith("update."))
        {
            updater ??= new WindowsUpdater(this);
            return method switch
            {
                "update.check" => await updater.Check(),
                "update.status" => updater.Status(),
                "update.download" => updater.Download(),
                "update.cancel" => updater.Cancel(),
                "update.install" => await updater.Install(),
                _ => throw new NotSupportedException(method)
            };
        }
        if (method == "http.fetch")
            return await Fetch(args);
        if (method == "proxy.resolve")
            return await Task.Run(() => ResolveProxy(A(args, 0)));
        return await Host.InvokeAsync(method, args);
    }
    JsonNode? PathOp(JsonArray a)
    {
        var op = A(a, 0);
        var p = a[1]!.AsArray().Select(x => x?.ToString() ?? "").ToArray();
        string result = op switch
        {
            "join" => Path.Combine(p).Replace('/', '\\'),
            "resolve" => Path.GetFullPath(p.Length == 0 ? AppRoot : Path.Combine(p), AppRoot),
            "dirname" => Path.GetDirectoryName(p[0]) ?? ".",
            "basename" => Path.GetFileName(p[0]),
            "extname" => Path.GetExtension(p[0]),
            "normalize" => Path.GetFullPath(p[0], AppRoot),
            "relative" => Path.GetRelativePath(p[0], p[1]),
            "root" => Path.GetPathRoot(p[0]) ?? "",
            _ => throw new ArgumentException(op)
        };
        return JsonValue.Create(result);
    }
    static void NoLink(string p)
    {
        var info = new FileInfo(p);
        if (info.Exists && (info.Attributes & FileAttributes.ReparsePoint) != 0)
            throw new UnauthorizedAccessException("Symbolic links are not allowed for file handles");
    }
    JsonNode Stat(string p, FileStream? stream = null)
    {
        FileSystemInfo info = Directory.Exists(p) ? new DirectoryInfo(p) : new FileInfo(p);
        info.Refresh();
        if (!info.Exists)
            throw new FileNotFoundException("Path not found", p);
        ulong ino = 0;
        uint dev = 0;
        if (stream != null && GetFileInformationByHandle(stream.SafeFileHandle, out var f))
        {
            ino = ((ulong)f.IndexHigh << 32) | f.IndexLow;
            dev = f.Volume;
        }
        else if (info is FileInfo && (info.Attributes & FileAttributes.ReparsePoint) == 0)
        {
            using var h = File.OpenHandle(p, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (GetFileInformationByHandle(h, out f))
            {
                ino = ((ulong)f.IndexHigh << 32) | f.IndexLow;
                dev = f.Volume;
            }
        }
        return Node(new
        {
            kind = info is DirectoryInfo ? "directory" : "file",
            link = (info.Attributes & FileAttributes.ReparsePoint) != 0,
            name = info.Name,
            size = info is FileInfo fi ? fi.Length : 0,
            mtimeMs = new DateTimeOffset(info.LastWriteTimeUtc).ToUnixTimeMilliseconds(),
            ino = ino.ToString(),
            dev,
            mode = 384
        })!;
    }
    JsonNode? FileOp(string op, JsonArray a)
    {
        string p = A(a, 0);
        switch (op)
        {
            case "exists":
                return JsonValue.Create(File.Exists(p) || Directory.Exists(p));
            case "stat":
                return Stat(p);
            case "realpath":
                {
                    FileSystemInfo info = Directory.Exists(p) ? new DirectoryInfo(p) : new FileInfo(p);
                    if (!info.Exists)
                        throw new FileNotFoundException("Path not found", p);
                    return JsonValue.Create(info.ResolveLinkTarget(true)?.FullName ?? Path.GetFullPath(p));
                }
            case "read":
                {
                    NoLink(p);
                    using var s = new FileStream(p, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                    if (s.Length > 32 * 1024 * 1024)
                        throw new IOException("File exceeds read limit");
                    using var m = new MemoryStream();
                    s.CopyTo(m);
                    return JsonValue.Create(Convert.ToBase64String(m.ToArray()));
                }
            case "write":
                {
                    NoLink(p);
                    var mode = S(a.ElementAtOrDefault(2), "flag") == "wx" ? FileMode.CreateNew : FileMode.Create;
                    using var s = new FileStream(p, mode, FileAccess.Write, FileShare.Read);
                    s.Write(Convert.FromBase64String(A(a, 1)));
                    return null;
                }
            case "mkdir":
                Directory.CreateDirectory(p);
                return null;
            case "mkdtemp":
                {
                    var target = p + Guid.NewGuid().ToString("N");
                    Directory.CreateDirectory(target);
                    return JsonValue.Create(target);
                }
            case "rename":
                File.Move(p, A(a, 1), true);
                return null;
            case "unlink":
                if (!File.Exists(p))
                    throw new FileNotFoundException();
                File.Delete(p);
                return null;
            case "copy":
                File.Copy(p, A(a, 1), true);
                return null;
            case "readdir":
                return new JsonArray(new DirectoryInfo(p).EnumerateFileSystemInfos().Take(100000).Select(x => Node(new { name = x.Name, kind = x is DirectoryInfo ? "directory" : "file", link = (x.Attributes & FileAttributes.ReparsePoint) != 0 })).ToArray());
            case "opendir":
                {
                    var id = ++nextHandle;
                    directories[id] = new DirectoryInfo(p).EnumerateFileSystemInfos().GetEnumerator();
                    return JsonValue.Create(id);
                }
            case "dirnext":
                {
                    var it = directories[I(a, 0)];
                    if (!it.MoveNext())
                        return null;
                    var x = it.Current;
                    return Node(new
                    {
                        name = x.Name,
                        kind = x is DirectoryInfo ? "directory" : "file",
                        link = (x.Attributes & FileAttributes.ReparsePoint) != 0
                    });
                }
            case "dirclose":
                if (directories.Remove(I(a, 0), out var it2))
                    it2.Dispose();
                return null;
            case "open":
                {
                    NoLink(p);
                    var id = ++nextHandle;
                    var write = A(a, 1) == "wx";
                    files[id] = new FileStream(p, write ? FileMode.CreateNew : FileMode.Open, write ? FileAccess.ReadWrite : FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                    return JsonValue.Create(id);
                }
            case "fstat":
                return Stat(files[I(a, 0)].Name, files[I(a, 0)]);
            case "fread":
                {
                    var s = files[I(a, 0)];
                    var count = Math.Clamp(I(a, 1), 0, 32 * 1024 * 1024);
                    if (a.Count > 2 && a[2] != null)
                        s.Position = a[2]!.GetValue<long>();
                    var b = new byte[count];
                    var n = s.Read(b);
                    return JsonValue.Create(Convert.ToBase64String(b, 0, n));
                }
            case "fwrite":
                files[I(a, 0)].Write(Convert.FromBase64String(A(a, 1)));
                return null;
            case "fsync":
                files[I(a, 0)].Flush(true);
                return null;
            case "close":
                if (files.Remove(I(a, 0), out var stream))
                    stream.Dispose();
                return null;
            default:
                throw new NotSupportedException("File operation: " + op);
        }
    }
    [StructLayout(LayoutKind.Sequential)]
    struct FileInformation
    {
        public uint Attributes; public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write; public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", SetLastError = true)][return: MarshalAs(UnmanagedType.Bool)] static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInformation info);
    internal void DisposeResources()
    {
        foreach (var f in files.Values)
            f.Dispose();
        files.Clear();
        foreach (var d in directories.Values)
            d.Dispose();
        directories.Clear();
        foreach (var p in processes.Values)
        {
            try
            {
                p.Kill(true);
            }
            catch { }
            p.Dispose();
        }
        processes.Clear();
        foreach (var s in sockets.Values)
            s.Dispose();
        sockets.Clear();
        foreach (var l in servers.Values)
            l.Stop();
        servers.Clear();
    }
}
