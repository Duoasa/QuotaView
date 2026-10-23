using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using static QuotaView.NativeBridge;

namespace QuotaView;

internal sealed class NativeWindow : Form
{
    readonly Host host;
    readonly int id;
    readonly bool overlay;
    readonly WebView2 web = new() { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.Transparent };
    readonly Dictionary<string, TaskCompletionSource<JsonNode?>> evaluations = new();
    static readonly HashSet<string> Channels = new("snapshot inspectCodexHooks dismissTask restoreTasks settings refresh respond configure openSettings resize region external path updates downloadUpdate cancelUpdate installUpdate quit minimize maximize showWindow directory diagnostics".Split(' ').Select(x => "qv:" + x));
    string material = "none";
    JsonArray? shape;
    bool loaded;
    readonly System.Windows.Forms.Timer motionTimer = new() { Interval = 10 };
    Rectangle motionFrom, motionTarget;
    long motionStarted;
    int motionFrames, viewportResizes;
    double maxFrameGap;
    long previousFrame;
    Region? viewportRegion;
    internal NativeWindow(Host host, int id, JsonNode options)
    {
        this.host = host;
        this.id = id;
        overlay = options["transparent"]?.GetValue<bool>() == true;
        Text = "QuotaView Windows · WebView2";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = !overlay;
        TopMost = options["alwaysOnTop"]?.GetValue<bool>() == true;
        BackColor = Color.Black;
        ClientSize = new Size(options["width"]!.GetValue<int>(), options["height"]!.GetValue<int>());
        if (!overlay)
            Location = Screen.FromPoint(Cursor.Position).WorkingArea.Location;
        Controls.Add(web);
        Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!);
        FormClosed += (_, _) => { motionTimer.Dispose(); viewportRegion?.Dispose(); host.WindowClosed(id); };
        motionTimer.Tick += (_, _) => AdvanceMotion();
        DpiChanged += (_, _) => { if (shape != null) ApplyRegion(shape); };
        // Force an HWND before asynchronous WebView2 initialization, without showing it.
        _ = Handle;
        ClientSize = new Size((int)Math.Round(options["width"]!.GetValue<int>() * DeviceDpi / 96d), (int)Math.Round(options["height"]!.GetValue<int>() * DeviceDpi / 96d));
        if (!overlay)
        {
            var area = Screen.FromHandle(Handle).WorkingArea;
            int margin = (int)Math.Round(24 * DeviceDpi / 96d);
            Size = new Size(Math.Min(Width, area.Width - margin), Math.Min(Height, area.Height - margin));
            MinimumSize = new Size(Math.Min((int)(720 * DeviceDpi / 96d), Width), Math.Min((int)(520 * DeviceDpi / 96d), Height));
            Location = new Point(area.Left + (area.Width - Width) / 2, area.Top + (area.Height - Height) / 2);
            MaximizedBounds = new Rectangle(area.X - Screen.FromHandle(Handle).Bounds.X, area.Y - Screen.FromHandle(Handle).Bounds.Y, area.Width, area.Height);
            Resize += (_, _) => { Send(new { kind = "window-state", maximized = WindowState == FormWindowState.Maximized }); host.Bridge.Emit(new { id = "window-" + id, type = "state", maximized = WindowState == FormWindowState.Maximized }); };
        }
    }
    protected override bool ShowWithoutActivation => overlay;
    protected override CreateParams CreateParams
    {
        get
        {
            var p = base.CreateParams;
            if (overlay)
                p.ExStyle |= 0x80;
            return p;
        }
    }
    internal async Task LoadView(string file, JsonObject query)
    {
        var expected = Path.Combine(host.Bridge.AppRoot, "dist", "renderer", "index.html");
        if (!Path.GetFullPath(file).Equals(expected, StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Unexpected renderer");
        await web.EnsureCoreWebView2Async(host.Environment2);
        var core = web.CoreWebView2;
        host.Secure(core, "app.quotaview.local", "/dist/renderer/index.html", false);
        core.WebMessageReceived += Message;
        await core.AddScriptToExecuteOnDocumentCreatedAsync(File.ReadAllText(Path.Combine(host.Bridge.AppRoot, "renderer-bridge.js")));
        var ready = new TaskCompletionSource();
        void Complete(object? s, CoreWebView2NavigationCompletedEventArgs e)
        {
            core.NavigationCompleted -= Complete;
            if (e.IsSuccess)
                ready.TrySetResult();
            else
                ready.TrySetException(new IOException("Renderer navigation: " + e.WebErrorStatus));
        }
        core.NavigationCompleted += Complete;
        string search = string.Join('&', query.Select(x => Uri.EscapeDataString(x.Key) + "=" + Uri.EscapeDataString(x.Value?.ToString() ?? "")));
        core.Navigate("https://app.quotaview.local/dist/renderer/index.html?" + search);
        await ready.Task.WaitAsync(TimeSpan.FromSeconds(25));
        loaded = true;
        host.Log("Loaded renderer " + S(query, "view"));
    }
    void Message(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        if (!Host.Trusted(e.Source, "app.quotaview.local", "/dist/renderer/index.html"))
            return;
        try
        {
            var json = e.WebMessageAsJson;
            if (json.Length > 300_000)
                return;
            var m = JsonNode.Parse(json)!;
            switch (S(m, "kind"))
            {
                case "invoke":
                    if (!Channels.Contains(S(m, "channel")) || m["args"] is not JsonArray args || args.Count > 8 || !int.TryParse(m["id"]?.ToString(), out int request) || request < 1)
                        return;
                    host.Bridge.Emit(new
                    {
                        id = "ipc",
                        window = id,
                        request,
                        channel = S(m, "channel"),
                        args
                    });
                    break;
                case "eval":
                    if (evaluations.Remove(S(m, "id"), out var result))
                    {
                        if (m["error"] != null)
                            result.TrySetException(new Exception(S(m, "error")));
                        else
                            result.TrySetResult(m["value"]?.DeepClone());
                    }
                    break;
                case "drag":
                    if (!overlay)
                    {
                        ReleaseCapture();
                        SendMessage(Handle, 0xA1, 2, 0);
                    }
                    break;
                case "resize-frame":
                    if (!overlay && WindowState == FormWindowState.Normal && int.TryParse(m["edge"]?.ToString(), out int edge) && edge >= 10 && edge <= 17)
                    {
                        ReleaseCapture();
                        SendMessage(Handle, 0xA1, edge, 0);
                    }
                    break;
                case "error":
                    host.Log("Renderer: " + S(m, "message"));
                    host.Bridge.Emit(new
                    {
                        id = "window-" + id,
                        type = "renderer-error",
                        message = S(m, "message")
                    });
                    break;
            }
        }
        catch (Exception error) { host.Log("Rejected renderer message: " + error.Message); }
    }
    internal void Send(object value)
    {
        if (web.CoreWebView2 != null && !IsDisposed)
            web.CoreWebView2.PostWebMessageAsJson(System.Text.Json.JsonSerializer.Serialize(value));
    }
    internal async Task<JsonNode?> Evidence(string folder)
    {
        using var stream = File.Create(Path.Combine(folder, "view-" + id + ".png"));
        await web.CoreWebView2.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, stream);
        using var graphics = CreateGraphics();
        var clip = Region?.GetBounds(graphics) ?? ClientRectangle;
        return Node(new
        {
            id,
            clipBounds = new { x = clip.X, y = clip.Y, width = clip.Width, height = clip.Height },
            visible = Visible,
            bounds = new
            {
                x = Bounds.X,
                y = Bounds.Y,
                width = Width,
                height = Height
            },
            screenTop = Screen.FromRectangle(Bounds).Bounds.Top,
            dpi = DeviceDpi,
            state = WindowState.ToString(),
            workArea = new
            {
                x = Screen.FromHandle(Handle).WorkingArea.X,
                y = Screen.FromHandle(Handle).WorkingArea.Y,
                width = Screen.FromHandle(Handle).WorkingArea.Width,
                height = Screen.FromHandle(Handle).WorkingArea.Height
            },
            clipped = Region != null,
            motion = new { frames = motionFrames, viewportResizes, maxFrameGap, active = motionTimer.Enabled },
            material,
            hostObjectsAllowed = web.CoreWebView2.Settings.AreHostObjectsAllowed
        });
    }
    internal async Task<JsonNode?> Evaluate(string script)
    {
        if (!loaded)
            throw new InvalidOperationException("Renderer not ready");
        string key = Guid.NewGuid().ToString("N");
        var tcs = new TaskCompletionSource<JsonNode?>();
        evaluations[key] = tcs;
        // WebView2's ExecuteScriptAsync does not await promises. Resolve in the
        // document and send a correlated reply back through the private eval route.
        string keyJson = System.Text.Json.JsonSerializer.Serialize(key);
        await web.CoreWebView2.ExecuteScriptAsync("Promise.resolve().then(()=> (" + script + ")).then(value=>chrome.webview.postMessage({kind:'eval',id:" + keyJson + ",value}),error=>chrome.webview.postMessage({kind:'eval',id:" + keyJson + ",error:String(error.stack||error)}));");
        try
        {
            return await tcs.Task.WaitAsync(TimeSpan.FromSeconds(90));
        }
        finally { evaluations.Remove(key); }
    }
    internal void Apply(string op, JsonArray args)
    {
        switch (op)
        {
            case "bounds":
                {
                    var r = Displays.Physical(args[1]!);
                    MoveBounds(r, args.Count > 2 && B(args, 2));
                    break;
                }
            case "top":
                TopMost = B(args, 1);
                break;
            case "material":
                material = A(args, 1);
                SetMaterial();
                break;
            case "background":
                {
                    string color = A(args, 1);
                    web.DefaultBackgroundColor = color == "#00000000" ? Color.Transparent : ColorTranslator.FromHtml(color);
                    if (color != "#00000000")
                        BackColor = ColorTranslator.FromHtml(color);
                    break;
                }
            case "region":
                shape = args[1]!.DeepClone().AsArray();
                ApplyRegion(shape);
                break;
            case "show":
                if (WindowState == FormWindowState.Minimized)
                    WindowState = FormWindowState.Normal;
                if (B(args, 1))
                {
                    Show();
                    Activate();
                }
                else
                {
                    Show();
                    ShowWindow(Handle, 4);
                }
                break;
            case "hide":
                Hide();
                break;
            case "focus":
                Activate();
                break;
            case "state":
                var monitor = Screen.FromHandle(Handle);
                var work = monitor.WorkingArea;
                MaximizedBounds = new Rectangle(work.X - monitor.Bounds.X, work.Y - monitor.Bounds.Y, work.Width, work.Height);
                WindowState = A(args, 1) switch
                {
                    "maximize" => FormWindowState.Maximized,
                    "minimize" => FormWindowState.Minimized,
                    _ => FormWindowState.Normal
                };
                break;
            default:
                throw new NotSupportedException("Window operation: " + op);
        }
    }
    void SetMaterial()
    {
        int kind = material switch
        {
            "mica" => 2,
            "acrylic" => 3,
            _ => 1
        };
        DwmSetWindowAttribute(Handle, 38, ref kind, sizeof(int));
        int dark = 1;
        DwmSetWindowAttribute(Handle, 20, ref dark, sizeof(int));
        var margins = new Margins { Left = -1, Right = -1, Top = -1, Bottom = -1 };
        DwmExtendFrameIntoClientArea(Handle, ref margins);
    }
    void ApplyRegion(JsonArray rows)
    {
        if (rows.Count == 0 || rows.Count > 5000)
            return;
        var region = new Region();
        region.MakeEmpty();
        float scale = DeviceDpi / 96f;
        foreach (var row in rows)
        {
            float x = row!["x"]!.GetValue<float>(), y = row["y"]!.GetValue<float>(), w = row["width"]!.GetValue<float>(), h = row["height"]!.GetValue<float>();
            if (w > 0 && h > 0)
                region.Union(Rectangle.FromLTRB((int)Math.Floor(x * scale), (int)Math.Floor(y * scale), (int)Math.Ceiling((x + w) * scale), (int)Math.Ceiling((y + h) * scale)));
        }
        viewportRegion?.Dispose();
        viewportRegion = region;
        UpdateViewportRegion();
    }
    void MoveBounds(Rectangle target, bool animate)
    {
        motionTimer.Stop();
        motionFrom = Bounds;
        motionTarget = target;
        motionFrames = 0;
        viewportResizes = 0;
        maxFrameGap = 0;
        // Dock.Fill would resize the Chromium swap chain on every native tick.
        // Size the child viewport once, and reveal it through the parent HWND.
        if (overlay) web.Dock = DockStyle.None;
        if (web.Size != target.Size) { web.Size = target.Size; viewportResizes++; }
        if (!animate || !overlay || !Visible || motionFrom == target)
        {
            Bounds = target;
            web.Location = Point.Empty;
            UpdateViewportRegion();
            return;
        }
        web.Location = new Point((Width - web.Width) / 2, 0);
        motionStarted = previousFrame = System.Diagnostics.Stopwatch.GetTimestamp();
        motionTimer.Start();
    }
    void AdvanceMotion()
    {
        long now = System.Diagnostics.Stopwatch.GetTimestamp();
        double elapsed = System.Diagnostics.Stopwatch.GetElapsedTime(motionStarted, now).TotalMilliseconds;
        maxFrameGap = Math.Max(maxFrameGap, System.Diagnostics.Stopwatch.GetElapsedTime(previousFrame, now).TotalMilliseconds);
        previousFrame = now;
        double p = Math.Min(1, elapsed / 280), ease = 1 - Math.Pow(1 - p, 3);
        int Lerp(int a, int b) => (int)Math.Round(a + (b - a) * ease);
        int w = Lerp(motionFrom.Width, motionTarget.Width), h = Lerp(motionFrom.Height, motionTarget.Height);
        int x = Lerp(motionFrom.X + motionFrom.Width / 2, motionTarget.X + motionTarget.Width / 2) - w / 2;
        SetBounds(x, Lerp(motionFrom.Y, motionTarget.Y), w, h);
        web.Location = new Point((Width - web.Width) / 2, 0);
        UpdateViewportRegion();
        motionFrames++;
        if (p >= 1) { motionTimer.Stop(); Bounds = motionTarget; web.Location = Point.Empty; UpdateViewportRegion(); }
    }
    void UpdateViewportRegion()
    {
        if (viewportRegion == null) return;
        var region = viewportRegion.Clone();
        region.Translate(web.Left, web.Top);
        var old = Region;
        Region = region;
        old?.Dispose();
    }
    protected override void WndProc(ref Message m)
    {
        base.WndProc(ref m);
        if (!overlay && m.Msg == 0x84 && WindowState == FormWindowState.Normal && m.Result == 1)
        {
            var p = PointToClient(new Point(unchecked((short)(long)m.LParam), unchecked((short)((long)m.LParam >> 16))));
            int edge = Math.Max(6, DeviceDpi / 16);
            bool l = p.X < edge, r = p.X >= ClientSize.Width - edge, t = p.Y < edge, b = p.Y >= ClientSize.Height - edge;
            m.Result = t ? l ? 13 : r ? 14 : 12 : b ? l ? 16 : r ? 17 : 15 : l ? 10 : r ? 11 : 1;
        }
    }
    [StructLayout(LayoutKind.Sequential)]
    struct Margins
    {
        public int Left, Right, Top, Bottom;
    }
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(nint h, int attribute, ref int value, int size);
    [DllImport("dwmapi.dll")] static extern int DwmExtendFrameIntoClientArea(nint h, ref Margins margins);
    [DllImport("user32.dll")] static extern bool ShowWindow(nint h, int command);
    [DllImport("user32.dll")] static extern bool ReleaseCapture();
    [DllImport("user32.dll")] static extern nint SendMessage(nint h, uint message, nint w, nint l);
}
