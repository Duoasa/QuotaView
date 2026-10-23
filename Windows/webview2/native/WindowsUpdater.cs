using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace QuotaView;

internal sealed class WindowsUpdater
{
    readonly NativeBridge bridge;
    readonly string cache = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "QuotaView", "Updates");
    readonly object gate = new();
    JsonObject state = new() { ["available"] = false, ["phase"] = "idle", ["channel"] = "windows", ["feedUrl"] = WindowsUpdatePolicy.FeedUrl };
    WindowsRelease? release;
    CancellationTokenSource? transfer;
    string? job;
    bool busy;

    internal WindowsUpdater(NativeBridge bridge)
    {
        this.bridge = bridge;
        // Surface a previous installation/rollback failure on the next launch.
        if (!Directory.Exists(cache)) return;
        try
        {
            var results = Directory.EnumerateDirectories(cache).Where(p => Guid.TryParseExact(Path.GetFileName(p), "N", out _))
                .Select(p => Path.Combine(p, "result.json")).Where(File.Exists).OrderByDescending(File.GetLastWriteTimeUtc);
            foreach (var file in results)
            {
                WindowsUpdateInstaller.NoLinks(file);
                var last = JsonNode.Parse(File.ReadAllText(file));
                if (!string.Equals(last?["target"]?.ToString()?.TrimEnd('\\', '/'), AppContext.BaseDirectory.TrimEnd('\\', '/'), StringComparison.OrdinalIgnoreCase)) continue;
                if (last?["ok"]?.GetValue<bool>() == false) state["installError"] = last["error"]?.ToString();
                break;
            }
        }
        catch { /* A missing/old result never prevents app startup. */ }
    }
    internal JsonNode Status() => Snapshot();

    JsonNode Snapshot() { lock (gate) return state.DeepClone(); }
    void Set(string phase, string? error = null, int? progress = null)
    {
        lock (gate)
        {
            state["phase"] = phase; state["checking"] = phase == "checking"; state["error"] = error;
            if (progress != null) state["progress"] = progress.Value;
            state["available"] = release != null;
            state["version"] = release?.Version; state["url"] = release?.ReleasePage;
            bridge.Emit(new { id = "updater", value = state.DeepClone() });
        }
    }

    HttpClient Client(TimeSpan timeout)
    {
        var handler = new HttpClientHandler { AllowAutoRedirect = false };
        var proxy = bridge.proxySettings;
        string mode = NativeBridge.S(proxy, "mode");
        if (mode == "direct") handler.UseProxy = false;
        else if (mode == "fixed_servers") handler.Proxy = new WebProxy(NativeBridge.S(proxy, "proxyRules"));
        var client = new HttpClient(handler) { Timeout = timeout };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("QuotaView-Windows/" + BuildIdentity.Version);
        client.DefaultRequestHeaders.CacheControl = new() { NoCache = true };
        return client;
    }

    // GitHub release downloads redirect to their asset CDN. Never send this request to another host or downgrade to HTTP.
    static async Task<HttpResponseMessage> Get(HttpClient client, string url, bool asset, CancellationToken token)
    {
        var uri = new Uri(url);
        for (int attempt = 0; attempt < 5; attempt++)
        {
            if (uri.Scheme != "https" || !uri.IsDefaultPort || uri.UserInfo != "" ||
                !(asset ? uri.Host is "github.com" or "release-assets.githubusercontent.com" or "objects.githubusercontent.com" : uri.AbsoluteUri == WindowsUpdatePolicy.FeedUrl))
                throw new InvalidDataException("Unexpected Windows update redirect");
            var response = await client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, token);
            if ((int)response.StatusCode is 301 or 302 or 303 or 307 or 308)
            {
                var next = response.Headers.Location; response.Dispose();
                if (next == null) throw new IOException("Update redirect has no location");
                uri = new Uri(uri, next); continue;
            }
            if (!response.IsSuccessStatusCode) { int code = (int)response.StatusCode; response.Dispose(); throw new IOException("Windows update HTTP " + code); }
            return response;
        }
        throw new IOException("Too many Windows update redirects");
    }

    internal async Task<JsonNode> Check()
    {
        lock (gate) { if (busy || state["phase"]?.ToString() == "ready") return Snapshot(); busy = true; }
        Set("checking");
        try
        {
            using var client = Client(TimeSpan.FromSeconds(20));
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
            using var response = await Get(client, WindowsUpdatePolicy.FeedUrl, false, timeout.Token);
            await response.Content.LoadIntoBufferAsync(1024 * 1024, timeout.Token);
            var candidate = WindowsUpdatePolicy.ReadFeed(await response.Content.ReadAsStringAsync(timeout.Token), BuildIdentity.Version, WindowsUpdatePolicy.PublicKey);
            lock (gate) { release = candidate; state["checkedAt"] = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(); }
            Set(candidate == null ? "current" : "available");
        }
        catch (Exception e) { Set("error", e.Message); }
        finally { lock (gate) busy = false; }
        return Snapshot();
    }

    internal JsonNode Download()
    {
        WindowsRelease next;
        lock (gate)
        {
            if (busy || release == null || state["phase"]?.ToString() == "ready") return Snapshot();
            busy = true; next = release; transfer = new CancellationTokenSource(TimeSpan.FromMinutes(30));
        }
        Set("downloading", progress: 0);
        _ = DownloadPackage(next, transfer.Token);
        return Snapshot();
    }
    async Task DownloadPackage(WindowsRelease next, CancellationToken token)
    {
        try
        {
            WindowsUpdatePolicy.Validate(next, WindowsUpdatePolicy.PublicKey);
            Directory.CreateDirectory(cache); WindowsUpdateInstaller.NoLinks(cache);
            job = Path.Combine(cache, Guid.NewGuid().ToString("N")); Directory.CreateDirectory(job);
            string partial = Path.Combine(job, "package.partial");
            using var client = Client(Timeout.InfiniteTimeSpan);
            using var response = await Get(client, next.Url, true, token);
            if (response.Content.Headers.ContentLength is long size && size != next.Length) throw new InvalidDataException("Update download size mismatch");
            await using (var source = await response.Content.ReadAsStreamAsync(token))
            await using (var destination = new FileStream(partial, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, true))
            {
                var buffer = new byte[65536]; long count = 0; int progress = -1, read;
                while ((read = await source.ReadAsync(buffer, token)) != 0)
                {
                    count += read;
                    if (count > next.Length) throw new InvalidDataException("Update download exceeds declared size");
                    await destination.WriteAsync(buffer.AsMemory(0, read), token);
                    int percent = (int)(count * 100 / next.Length);
                    if (percent != progress) { progress = percent; Set("downloading", progress: percent); }
                }
            }
            token.ThrowIfCancellationRequested();
            Set("verifying");
            await Task.Run(() => WindowsUpdatePolicy.VerifyPackage(partial, next), token);
            token.ThrowIfCancellationRequested();
            File.Move(partial, Path.Combine(job, "package.zip"));
            Set("ready", progress: 100);
        }
        catch (OperationCanceledException) { RemovePartial(); Set("available"); }
        catch (Exception e) { RemovePartial(); Set("error", e.Message); }
        finally { lock (gate) { transfer?.Dispose(); transfer = null; busy = false; } }
    }
    void RemovePartial()
    {
        if (job != null) { try { File.Delete(WindowsUpdateInstaller.Child(job, "package.partial")); } catch { } }
    }
    internal JsonNode Cancel() { lock (gate) transfer?.Cancel(); return Snapshot(); }

    internal async Task<JsonNode> Install()
    {
        WindowsRelease next; string currentJob;
        lock (gate)
        {
            if (busy || state["phase"]?.ToString() != "ready" || release == null || job == null) return Snapshot();
            busy = true; next = release; currentJob = job;
        }
        Set("installing");
        try
        {
            await Task.Run(() =>
            {
                string target = Path.GetFullPath(AppContext.BaseDirectory);
                WindowsUpdateInstaller.NoLinks(target);
                WindowsUpdatePolicy.Validate(next, WindowsUpdatePolicy.PublicKey);
                WindowsUpdatePolicy.VerifyPackage(Path.Combine(currentJob, "package.zip"), next);
                // Fail before quitting if the portable directory is read-only. Never request elevation.
                string probe = Path.Combine(target, ".quotaview-update-" + Guid.NewGuid().ToString("N"));
                using (File.Create(probe)) { } File.Delete(probe);
                // Run the helper from its own runtime so replacing the app cannot lock its DLLs.
                File.Delete(WindowsUpdateInstaller.Child(currentJob, "ready"));
                string helper = Path.Combine(currentJob, "helper-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(helper);
                foreach (var file in Directory.GetFiles(target))
                {
                    WindowsUpdateInstaller.NoLinks(file);
                    File.Copy(file, Path.Combine(helper, Path.GetFileName(file)), false);
                }
                using var parent = Process.GetCurrentProcess();
                var plan = new WindowsInstallPlan(target, Path.Combine(currentJob, "package.zip"), next, parent.Id, parent.StartTime.ToUniversalTime().Ticks);
                string planPath = Path.Combine(currentJob, "plan.json");
                File.WriteAllText(planPath, JsonSerializer.Serialize(plan));
                var start = new ProcessStartInfo(Path.Combine(helper, "QuotaView.Native.exe")) { UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden, WorkingDirectory = helper };
                start.ArgumentList.Add("--apply-windows-update"); start.ArgumentList.Add(planPath);
                using var process = Process.Start(start) ?? throw new IOException("Unable to start Windows updater");
                var clock = Stopwatch.StartNew();
                while (!File.Exists(Path.Combine(currentJob, "ready")))
                {
                    if (process.HasExited) throw new IOException("Update preparation failed. See " + Path.Combine(currentJob, "result.json"));
                    if (clock.Elapsed > TimeSpan.FromSeconds(90)) { process.Kill(); throw new IOException("Update preparation timed out"); }
                    Thread.Sleep(100);
                }
            });
            // JS calls app.quit after receiving this state, stopping hooks and backend work first.
            Set("restart");
        }
        catch (Exception e) { Set("ready", e.Message); }
        finally { lock (gate) busy = false; }
        return Snapshot();
    }
}
