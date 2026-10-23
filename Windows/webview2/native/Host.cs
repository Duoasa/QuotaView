using System.Diagnostics;
using System.Text.Json.Nodes;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Win32;
using static QuotaView.NativeBridge;

namespace QuotaView;

internal sealed class Host : Form
{
    internal readonly NativeBridge Bridge;
    internal CoreWebView2Environment Environment2 = null!;
    readonly WebView2 backend = new() { Dock = DockStyle.Fill };
    readonly Dictionary<int, NativeWindow> windows = new();
    NotifyIcon? tray;
    readonly bool isolated;
    bool exiting;
    int deliveryScheduled;
    EventWaitHandle? activation;
    internal static string LogPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "QuotaView WebView2", "host.log");
    internal Host(bool isolated)
    {
        this.isolated = isolated;
        Bridge = new NativeBridge(this);
        Text = "QuotaView backend";
        ShowInTaskbar = false;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Bounds = new Rectangle(-32000, -32000, 16, 16);
        Controls.Add(backend);
        Shown += async (_, _) => { try { await Start(); } catch (Exception e) { Log(e.ToString()); if (!isolated) MessageBox.Show(e is WebView2RuntimeNotFoundException ? "需要 Microsoft Edge WebView2 Runtime。请从 https://developer.microsoft.com/microsoft-edge/webview2/ 安装后重试。" : "QuotaView 启动失败。请查看日志：" + LogPath, "QuotaView", MessageBoxButtons.OK, MessageBoxIcon.Error); Exit(1); } };
        FormClosing += (_, _) => Shutdown();
        SystemEvents.DisplaySettingsChanged += OnDisplays;
        SystemEvents.UserPreferenceChanged += OnTheme;
    }
    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams
    {
        get
        {
            var p = base.CreateParams;
            p.ExStyle |= 0x08000080;
            return p;
        }
    }
    internal void Log(string text)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
            if (File.Exists(LogPath) && new FileInfo(LogPath).Length > 2_000_000)
                File.WriteAllText(LogPath, "");
            File.AppendAllText(LogPath, $"{DateTimeOffset.Now:O} {text}\n");
        }
        catch { }
    }
    internal static void Fatal(Exception error)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
            File.AppendAllText(LogPath, error + "\n");
        }
        catch { }
    }
    async Task Start()
    {
        Log("Starting .NET/WebView2 host");
        var options = new CoreWebView2EnvironmentOptions("--disable-background-timer-throttling --disable-renderer-backgrounding --disable-backgrounding-occluded-windows");
        var profile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "QuotaView WebView2", isolated ? "test-profile" : "profile");
        Environment2 = await CoreWebView2Environment.CreateAsync(null, profile, options);
        await backend.EnsureCoreWebView2Async(Environment2);
        Secure(backend.CoreWebView2, "backend.quotaview.local", "/backend.html", true);
        backend.CoreWebView2.AddHostObjectToScript("native", Bridge);
        backend.CoreWebView2.NavigationCompleted += (_, e) => Log("Backend navigation: " + e.IsSuccess + " " + e.WebErrorStatus);
        backend.CoreWebView2.Navigate("https://backend.quotaview.local/backend.html");
        var report = Environment.GetCommandLineArgs().FirstOrDefault(x => x.StartsWith("--validation-report="))?[20..];
        if (report != null)
            _ = ValidateLive(report);
        if (!isolated)
        {
            activation = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\QuotaView.WebView2.Activate");
            _ = Task.Run(() => { while (!exiting) { try { if (activation.WaitOne(1000)) Post(() => Bridge.Emit(new { id = "app", type = "second-instance" })); } catch (ObjectDisposedException) { return; } } });
        }
    }
    internal void Secure(CoreWebView2 core, string hostname, string document, bool service)
    {
        core.SetVirtualHostNameToFolderMapping(hostname, Bridge.AppRoot, CoreWebView2HostResourceAccessKind.DenyCors);
        var settings = core.Settings;
        settings.AreDefaultContextMenusEnabled = false;
        settings.AreDevToolsEnabled = false;
        settings.AreHostObjectsAllowed = service;
        settings.IsPasswordAutosaveEnabled = false;
        settings.IsGeneralAutofillEnabled = false;
        settings.IsStatusBarEnabled = false;
        settings.IsZoomControlEnabled = false;
        settings.AreBrowserAcceleratorKeysEnabled = false;
        core.NavigationStarting += (_, e) => { if (!Trusted(e.Uri, hostname, document)) e.Cancel = true; };
        core.FrameNavigationStarting += (_, e) => e.Cancel = true;
        core.NewWindowRequested += (_, e) => e.Handled = true;
        core.PermissionRequested += (_, e) => { e.State = CoreWebView2PermissionState.Deny; e.Handled = true; };
        core.DownloadStarting += (_, e) => e.Cancel = true;
        core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
        core.WebResourceRequested += (_, e) =>
        {
            if (!Uri.TryCreate(e.Request.Uri, UriKind.Absolute, out var u) || u.Scheme != "https" || u.Host != hostname)
                e.Response = Environment2.CreateWebResourceResponse(Stream.Null, 403, "Blocked", "Content-Type: text/plain");
        };
        core.ProcessFailed += (_, e) => { Log("WebView process failure: " + e.ProcessFailedKind); if (service) Exit(1); };
    }
    internal static bool Trusted(string source, string host, string document) => Uri.TryCreate(source, UriKind.Absolute, out var u) && u.Scheme == "https" && u.Host == host && u.AbsolutePath == document && u.IsDefaultPort;
    internal void Post(Action action)
    {
        if (!exiting && !IsDisposed)
            BeginInvoke(action);
    }
    internal void ScheduleEvents()
    {
        if (exiting || Interlocked.Exchange(ref deliveryScheduled, 1) != 0)
            return;
        Post(() => { Interlocked.Exchange(ref deliveryScheduled, 0); if (backend.CoreWebView2 != null) backend.CoreWebView2.PostWebMessageAsJson(Bridge.Drain()); if (Bridge.HasEvents) ScheduleEvents(); });
    }
    async Task ValidateLive(string path)
    {
        try
        {
            await Task.Delay(15000);
            var first = windows.Values.First();
            await first.Evaluate("window.quotaView.refresh()");
            var data = await first.Evaluate("window.quotaView.snapshot().then(s=>({taskCount:s.tasks.length,quota:!!s.quotas.codex,providers:Object.fromEntries(Object.entries(s.providers).map(([k,v])=>[k,{enabled:v.enabled,connected:v.connected,message:v.message,quotaError:v.quotaError,hooks:v.hooks,desktop:v.desktop}])),platform:s.platform,settingsLoaded:!!s.settings,bridgeHidden:(()=>{try{return typeof chrome.webview.hostObjects.sync.native==='undefined';}catch{return true;}})()}))");
            await first.Evaluate("window.quotaView.resize({expanded:true,pinned:true}).then(()=>window.quotaView.openSettings())");
            await Task.Delay(1000);
            var views = new JsonArray();
            foreach (var w in windows.Values.ToArray())
                views.Add(await w.Evidence(Path.GetDirectoryName(Path.GetFullPath(path))!));
            File.WriteAllText(path, new JsonObject { ["snapshot"] = data, ["views"] = views }.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));
            Log("Live validation saved");
        }
        catch (Exception e) { Log("Live validation: " + e.Message); File.WriteAllText(path, new JsonObject { ["error"] = e.Message }.ToJsonString()); }
    }
    void OnDisplays(object? sender, EventArgs e) => Post(() => Bridge.Emit(new { id = "screen", type = "changed" }));
    void OnTheme(object? sender, UserPreferenceChangedEventArgs e) => Post(() => Bridge.Emit(new { id = "theme", type = "changed" }));
    internal JsonNode? InvokeNative(string method, JsonArray a)
    {
        switch (method)
        {
            case "app.exit":
                Post(() => Exit(I(a, 0)));
                return null;
            case "app.autostart":
                {
                    using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
                    if (a[0]?["openAtLogin"]?.GetValue<bool>() == true)
                        key.SetValue("QuotaView WebView2", "\"" + Environment.ProcessPath + "\"");
                    else
                        key.DeleteValue("QuotaView WebView2", false);
                    return null;
                }
            case "window.create":
                {
                    int id = I(a, 0);
                    var o = a[1]!.DeepClone();
                    windows[id] = new NativeWindow(this, id, o);
                    return null;
                }
            case "window.reply":
                {
                    var id = I(a, 0);
                    var request = a[1]!.DeepClone();
                    var result = a[2]!.DeepClone();
                    Post(() => { if (windows.TryGetValue(id, out var w)) w.Send(new JsonObject { ["kind"] = "reply", ["id"] = request, ["value"] = result["value"]?.DeepClone(), ["error"] = result["error"]?.DeepClone() }); });
                    return null;
                }
            case "window.send":
                {
                    var id = I(a, 0);
                    var channel = A(a, 1);
                    var value = a[2]?.DeepClone();
                    Post(() => { if (windows.TryGetValue(id, out var w)) w.Send(new { kind = "event", channel, value }); });
                    return null;
                }
            case "screen.all":
                return Node(Displays.All());
            case "screen.cursor":
                return Node(Displays.Cursor());
            case "screen.nearest":
                return Node(Displays.Nearest(a[0]!));
            case "screen.match":
                return Node(Displays.Matching(a[0]!));
            case "screen.dip":
                return Node(Displays.ToDip(a[0]!));
            case "theme.get":
                {
                    using var colors = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                    return Node(new
                    {
                        dark = (int?)colors?.GetValue("AppsUseLightTheme") == 0,
                        transparency = (int?)colors?.GetValue("EnableTransparency") != 0,
                        highContrast = SystemInformation.HighContrast
                    });
                }
            case "theme.set":
                return null;
            case "proxy.settings":
                Bridge.proxySettings = a[0]!.DeepClone().AsObject();
                return null;
            case "tray.create":
                Post(() => { tray?.Dispose(); tray = new NotifyIcon { Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!), Text = "QuotaView Windows", Visible = true }; tray.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) Bridge.Emit(new { id = "tray", type = "click" }); }; tray.DoubleClick += (_, _) => Bridge.Emit(new { id = "tray", type = "double-click" }); });
                return null;
            case "tray.tooltip":
                {
                    var text = A(a, 0);
                    Post(() => { if (tray != null) tray.Text = text[..Math.Min(127, text.Length)]; });
                    return null;
                }
            case "tray.menu":
                {
                    var rows = a[0]!.DeepClone().AsArray();
                    Post(() => { var menu = new ContextMenuStrip(); foreach (var row in rows) { if (S(row, "type") == "separator") { menu.Items.Add(new ToolStripSeparator()); continue; } var id = S(row, "id"); menu.Items.Add(S(row, "label"), null, (_, _) => Bridge.Emit(new { id = "menu", value = id })); } if (tray != null) { tray.ContextMenuStrip?.Dispose(); tray.ContextMenuStrip = menu; } else menu.Dispose(); });
                    return null;
                }
            case "tray.destroy":
                Post(() => { tray?.Dispose(); tray = null; });
                return null;
            case "notification":
                {
                    var o = a[0]!.DeepClone();
                    Post(() => tray?.ShowBalloonTip(5000, S(o, "title"), S(o, "body"), ToolTipIcon.Info));
                    return null;
                }
            case "dialog.error":
                {
                    var title = A(a, 0);
                    var message = A(a, 1);
                    Log(title + ": " + message);
                    if (!isolated)
                        Post(() => MessageBox.Show(message, title, MessageBoxButtons.OK, MessageBoxIcon.Error));
                    return null;
                }
        }
        if (method.StartsWith("window."))
        {
            int id = I(a, 0);
            var args = a.DeepClone().AsArray();
            Post(() => { if (windows.TryGetValue(id, out var w) && !w.IsDisposed) w.Apply(method[7..], args); });
            return null;
        }
        throw new NotSupportedException("Native method: " + method);
    }
    internal async Task<JsonNode?> InvokeAsync(string method, JsonArray a)
    {
        switch (method)
        {
            case "window.load":
                await windows[I(a, 0)].LoadView(A(a, 1), a[2]!.AsObject());
                return null;
            case "window.eval":
                return await windows[I(a, 0)].Evaluate(A(a, 1));
            case "window.capture":
                return await windows[I(a, 0)].Evidence(A(a, 1));
            case "shell.external":
                {
                    var u = new Uri(A(a, 0));
                    if (u.Scheme is not ("https" or "http" or "mailto" or "vscode" or "cursor" or "windsurf"))
                        throw new ArgumentException("Unsupported external URL");
                    Process.Start(new ProcessStartInfo(u.AbsoluteUri) { UseShellExecute = true });
                    return null;
                }
            case "shell.path":
                {
                    var p = Path.GetFullPath(A(a, 0));
                    if (B(a, 1))
                    {
                        var psi = new ProcessStartInfo("explorer.exe") { UseShellExecute = false };
                        psi.Arguments = "/select,\"" + p.Replace("\"", "") + "\"";
                        Process.Start(psi);
                    }
                    else
                    {
                        if (!Directory.Exists(p))
                            throw new DirectoryNotFoundException();
                        Process.Start(new ProcessStartInfo(p) { UseShellExecute = true });
                    }
                    return JsonValue.Create("");
                }
            case "dialog.open":
                {
                    using var dialog = new FolderBrowserDialog { Description = S(a[1], "title"), UseDescriptionForTitle = true };
                    bool ok = dialog.ShowDialog(windows[I(a, 0)]) == DialogResult.OK;
                    return Node(new
                    {
                        canceled = !ok,
                        filePaths = ok ? new[] { dialog.SelectedPath } : Array.Empty<string>()
                    });
                }
            case "dialog.save":
                {
                    using var dialog = new SaveFileDialog { FileName = S(a[1], "defaultPath"), Filter = "JSON files|*.json", AddExtension = true };
                    bool ok = dialog.ShowDialog(windows[I(a, 0)]) == DialogResult.OK;
                    return Node(new
                    {
                        canceled = !ok,
                        filePath = ok ? dialog.FileName : null
                    });
                }
            default:
                throw new NotSupportedException(method);
        }
    }
    internal void WindowClosed(int id)
    {
        windows.Remove(id);
        Bridge.Emit(new
        {
            id = "window-" + id,
            type = "closed"
        });
    }
    internal void Exit(int code)
    {
        Environment.ExitCode = code;
        Shutdown();
        Application.Exit();
    }
    void Shutdown()
    {
        if (exiting)
            return;
        exiting = true;
        SystemEvents.DisplaySettingsChanged -= OnDisplays;
        SystemEvents.UserPreferenceChanged -= OnTheme;
        activation?.Dispose();
        tray?.Dispose();
        Bridge.DisposeResources();
        foreach (var w in windows.Values.ToArray())
            w.Dispose();
        windows.Clear();
        backend.Dispose();
    }
}
