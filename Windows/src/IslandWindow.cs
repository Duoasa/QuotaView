using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace QuotaView.Windows
{
    internal sealed class IslandWindow : Window
    {
        const double CompactWidth = 340, ExpandedWidth = 680;
        readonly LocalSessions source;
        readonly string stateDirectory;
        readonly Grid root = new Grid();
        readonly System.Windows.Shapes.Path shell = new System.Windows.Shapes.Path();
        readonly Grid chrome = new Grid();
        readonly Grid header = new Grid();
        readonly ScrollViewer scroll = new ScrollViewer();
        readonly StackPanel body = new StackPanel();
        readonly DockPanel footer = new DockPanel();
        readonly TextBlock connection = Label("正在连接", 10, "#7F7F85");
        readonly DispatcherTimer pollTimer = new DispatcherTimer();
        readonly DispatcherTimer motionTimer = new DispatcherTimer();
        readonly DispatcherTimer hoverTimer = new DispatcherTimer();
        readonly DispatcherTimer closeTimer = new DispatcherTimer();
        readonly List<ActivityOrb> orbs = new List<ActivityOrb>();
        readonly HashSet<string> archived = new HashSet<string>();
        readonly Stopwatch clock = Stopwatch.StartNew();
        readonly Forms.NotifyIcon tray;
        LocalSnapshot snapshot = new LocalSnapshot();
        bool expanded, busy, closing, pinned, reduced, usage, settings;
        string detailId = "", fingerprint = "";
        double anchorX, anchorY;
        bool positionReady;

        public IslandWindow(LocalSessions source, string stateDirectory, bool initialExpanded)
        {
            this.source = source; this.stateDirectory = stateDirectory; expanded = initialExpanded;
            Title = "QuotaView Windows · 开发预览";
            Width = expanded ? ExpandedWidth : CompactWidth; Height = expanded ? 180 : 30;
            WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
            AllowsTransparency = true; Background = Brushes.Transparent; Topmost = true;
            ShowInTaskbar = false; ShowActivated = false;
            FontFamily = new FontFamily("Segoe UI, Microsoft YaHei UI"); UseLayoutRounding = true;
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
            AutomationProperties.SetName(this, "QuotaView Windows 灵动岛");
            LoadPreferences();
            Resources = (ResourceDictionary)XamlReader.Parse(@"<ResourceDictionary xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>
<Style TargetType='Button'><Setter Property='Foreground' Value='#99999F'/><Setter Property='Background' Value='Transparent'/><Setter Property='BorderThickness' Value='0'/><Setter Property='Padding' Value='8,4'/><Setter Property='Cursor' Value='Hand'/><Setter Property='FontSize' Value='12'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Button'><Border x:Name='B' Background='{TemplateBinding Background}' CornerRadius='5' Padding='{TemplateBinding Padding}'><ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/></Border><ControlTemplate.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter TargetName='B' Property='Background' Value='#202024'/><Setter Property='Foreground' Value='#EEEEF0'/></Trigger><Trigger Property='IsPressed' Value='True'><Setter TargetName='B' Property='Background' Value='#303036'/></Trigger><Trigger Property='IsKeyboardFocused' Value='True'><Setter TargetName='B' Property='Background' Value='#303036'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style TargetType='ScrollBar'><Setter Property='Width' Value='5'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='ScrollBar'><Track x:Name='PART_Track' IsDirectionReversed='True'><Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType='Thumb'><Border Background='#38383F' CornerRadius='2'/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb></Track></ControlTemplate></Setter.Value></Setter></Style>
</ResourceDictionary>");
            shell.Fill = Brushes.Black;
            root.Children.Add(shell);
            root.Children.Add(chrome);
            chrome.RowDefinitions.Add(new RowDefinition { Height = new GridLength(36) });
            chrome.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            chrome.RowDefinitions.Add(new RowDefinition { Height = new GridLength(40) });
            header.Margin = new Thickness(28, 0, 28, 0); chrome.Children.Add(header);
            scroll.Content = body; scroll.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
            scroll.HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled;
            scroll.Margin = new Thickness(28, 8, 28, 0); Grid.SetRow(scroll, 1); chrome.Children.Add(scroll);
            footer.Margin = new Thickness(32, 0, 28, 7); Grid.SetRow(footer, 2); chrome.Children.Add(footer);
            Content = root;
            SizeChanged += delegate { UpdateGeometry(); if (positionReady) { Left = anchorX - ActualWidth / 2; Top = anchorY; } };
            SourceInitialized += delegate
            {
                var handle = new WindowInteropHelper(this).Handle;
                int style = GetWindowLong(handle, -20);
                SetWindowLong(handle, -20, style | 0x08000000 | 0x00000080); // NOACTIVATE, TOOLWINDOW
                var hwnd = HwndSource.FromHwnd(handle); hwnd.AddHook(WindowProc);
                CenterOnScreen();
            };
            root.MouseEnter += delegate { closeTimer.Stop(); if (!expanded) { hoverTimer.Stop(); hoverTimer.Start(); } };
            root.MouseLeave += delegate { hoverTimer.Stop(); if (!pinned && detailId.Length == 0 && !settings && !usage) { closeTimer.Stop(); closeTimer.Start(); } };
            root.MouseRightButtonUp += delegate { ShowMenu(); };
            header.MouseLeftButtonUp += delegate(object sender, MouseButtonEventArgs e) { if (!expanded && !(e.OriginalSource is Button)) { SetExpanded(true); e.Handled = true; } };
            PreviewKeyDown += delegate(object sender, KeyEventArgs e) { if (e.Key == Key.Escape) { Escape(); e.Handled = true; } };
            hoverTimer.Interval = TimeSpan.FromMilliseconds(180); hoverTimer.Tick += delegate { hoverTimer.Stop(); SetExpanded(true); };
            closeTimer.Interval = TimeSpan.FromMilliseconds(1000); closeTimer.Tick += delegate { closeTimer.Stop(); if (!IsMouseOver && !pinned) SetExpanded(false); };
            pollTimer.Interval = TimeSpan.FromSeconds(2); pollTimer.Tick += async delegate { await Refresh(); };
            motionTimer.Interval = TimeSpan.FromMilliseconds(50); motionTimer.Tick += delegate
            {
                if (!IsVisible || reduced || !SystemParameters.ClientAreaAnimation) return;
                foreach (var orb in orbs) if (orb.Active) { orb.Phase = clock.Elapsed.TotalSeconds; orb.InvalidateVisual(); }
            };
            tray = new Forms.NotifyIcon { Icon = System.Drawing.SystemIcons.Application, Text = "QuotaView Windows · 开发预览", Visible = true };
            var menu = new Forms.ContextMenuStrip();
            menu.Items.Add("展开灵动岛", null, delegate { Dispatcher.BeginInvoke(new Action(delegate { Show(); CenterOnScreen(); SetExpanded(true); })); });
            menu.Items.Add("设置", null, delegate { Dispatcher.BeginInvoke(new Action(delegate { settings = true; detailId = ""; usage = false; SetExpanded(true); Render(true); })); });
            menu.Items.Add("退出", null, delegate { Dispatcher.BeginInvoke(new Action(Close)); });
            tray.ContextMenuStrip = menu;
            tray.MouseClick += delegate(object sender, Forms.MouseEventArgs e) { if (e.Button == Forms.MouseButtons.Left) Dispatcher.BeginInvoke(new Action(delegate { Show(); SetExpanded(!expanded); })); };
            Loaded += async delegate { Render(true); pollTimer.Start(); motionTimer.Start(); await Refresh(); };
            Closing += delegate { closing = true; pollTimer.Stop(); motionTimer.Stop(); hoverTimer.Stop(); closeTimer.Stop(); tray.Visible = false; tray.Dispose(); SavePreferences(); };
        }

        async Task Refresh()
        {
            if (busy || closing) return; busy = true;
            try
            {
                LocalSnapshot result = await Task.Run(() => source.Poll());
                if (closing) return;
                snapshot = result; Render(false);
                // Small diagnostics receipt confirms the actual running data path.
                File.WriteAllText(System.IO.Path.Combine(stateDirectory, "runtime-status.txt"),
                    "baseline=v0.7.7-build.1\nprocess=" + Process.GetCurrentProcess().Id + "\nupdated=" + DateTime.UtcNow.ToString("O") +
                    "\nsource_available=" + snapshot.Available + "\nsessions=" + snapshot.Sessions.Count(s => s.Kind == "user") +
                    "\nactive=" + snapshot.Sessions.Count(s => s.Kind == "user" && s.Active) + "\n");
            }
            catch (IOException) { connection.Text = "无法写入开发版运行状态"; }
            finally { busy = false; }
        }
        List<Session> VisibleSessions() { return snapshot.Sessions.Where(s => s.Kind == "user" && !archived.Contains(s.Id)).Take(12).ToList(); }
        void Render(bool force)
        {
            var sessions = VisibleSessions();
            string next = expanded + "/" + usage + "/" + settings + "/" + detailId + "/" + snapshot.Status + "/" + string.Join("|", snapshot.Sessions.Select(s => s.Id + ":" + s.Revision + ":" + s.StatusLabel + ":" + s.Title));
            if (!force && next == fingerprint) return; fingerprint = next;
            orbs.Clear(); header.Children.Clear(); header.ColumnDefinitions.Clear(); body.Children.Clear(); footer.Children.Clear();
            chrome.RowDefinitions[0].Height = new GridLength(expanded ? 36 : 30);
            chrome.RowDefinitions[2].Height = new GridLength(expanded ? 40 : 0);
            scroll.Visibility = footer.Visibility = expanded ? Visibility.Visible : Visibility.Collapsed;
            if (!expanded) { CompactHeader(sessions); return; }
            ExpandedHeader(sessions);
            if (settings) SettingsPage();
            else if (usage) UsagePage();
            else if (detailId.Length > 0)
            {
                var selected = sessions.FirstOrDefault(s => s.Id == detailId);
                if (selected != null) DetailPage(selected); else { detailId = ""; TaskList(sessions); }
            }
            else TaskList(sessions);
            Footer();
            double pageHeight = settings ? 310 : usage ? 270 : detailId.Length > 0 ? 340 : sessions.Count == 0 ? 116 : sessions.Sum(s => 68 + (snapshot.Sessions.Any(c => c.ParentId == s.Id && c.Kind == "child") ? 28 : 0));
            double maximum = Math.Min(560, SystemParameters.WorkArea.Height - 70);
            AnimateSize(Math.Min(ExpandedWidth, SystemParameters.WorkArea.Width - 24), Math.Min(maximum, 36 + 8 + pageHeight + 40));
        }
        void CompactHeader(List<Session> sessions)
        {
            header.Margin = new Thickness(25, 0, 25, 0);
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(22) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var current = sessions.FirstOrDefault(s => s.Active) ?? sessions.FirstOrDefault();
            if (current != null && current.Active) { var orb = Orb(current, 18); header.Children.Add(orb); }
            else
            {
                var q = LatestQuota(true); var value = Label(q != null && q.Remaining.HasValue ? Math.Round(q.Remaining.Value) + "%" : "—", 10, "#A7A7AB");
                value.ToolTip = "最近本地记录中的剩余额度"; header.Children.Add(value);
            }
            var title = Label(current != null && current.Active ? current.Title : snapshot.Available ? "就绪" : "QuotaView", 12, "#E8E8EC");
            title.TextAlignment = TextAlignment.Center; title.Margin = new Thickness(12, 0, 12, 0); title.TextTrimming = TextTrimming.CharacterEllipsis;
            Grid.SetColumn(title, 1); header.Children.Add(title);
            var count = Label(sessions.Count == 0 ? "Codex" : sessions.Count + " 会话", 10, "#87878E"); Grid.SetColumn(count, 2); header.Children.Add(count);
            ToolTip = "悬停或点击展开 · 右键菜单";
        }
        void ExpandedHeader(List<Session> sessions)
        {
            ToolTip = null; header.Margin = new Thickness(28, 0, 28, 0);
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var tabs = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            if (detailId.Length > 0 || settings)
                tabs.Children.Add(Button("‹  返回", "返回任务列表", delegate { detailId = ""; settings = usage = false; Render(true); }));
            else
            {
                var tasks = Button("任务  " + sessions.Count, "查看任务", delegate { usage = false; Render(true); });
                tasks.Foreground = Brush(usage ? "#77777E" : "#EBEBEE"); tabs.Children.Add(tasks);
                var use = Button("用量", "查看本地用量快照", delegate { usage = true; Render(true); }); use.Foreground = Brush(usage ? "#EBEBEE" : "#77777E"); tabs.Children.Add(use);
            }
            header.Children.Add(tabs);
            var identity = Label("WINDOWS PREVIEW", 9, "#525259"); identity.HorizontalAlignment = HorizontalAlignment.Center;
            identity.ToolTip = "基于 v0.7.7-build.1 的 Windows 最小实现"; Grid.SetColumn(identity, 1); header.Children.Add(identity);
            var controls = new StackPanel { Orientation = Orientation.Horizontal };
            controls.Children.Add(Button(pinned ? "●" : "○", pinned ? "取消固定展开" : "固定展开", delegate { pinned = !pinned; SavePreferences(); Render(true); }));
            controls.Children.Add(Button("⌃", "收起灵动岛", delegate { SetExpanded(false); }));
            Grid.SetColumn(controls, 2); header.Children.Add(controls);
        }
        void TaskList(List<Session> sessions)
        {
            if (sessions.Count == 0)
            {
                var box = new StackPanel { Margin = new Thickness(8, 23, 8, 24), HorizontalAlignment = HorizontalAlignment.Center };
                box.Children.Add(Label("等待 Codex 任务", 14, "#DDDDDF"));
                var info = Label(snapshot.Available ? "开始或继续一个本地任务，它会出现在这里。" : "请确认 Codex 已运行，并开始一个本地任务。", 11, "#77777E"); info.Margin = new Thickness(0, 10, 0, 0); box.Children.Add(info); body.Children.Add(box); return;
            }
            foreach (var session in sessions)
            {
                var group = new StackPanel { Margin = new Thickness(0, 0, 0, 8) };
                group.Children.Add(Card(session, true));
                var children = snapshot.Sessions.Where(c => c.Kind == "child" && c.ParentId == session.Id).Take(6).ToList();
                if (children.Count > 0)
                {
                    var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(12, 0, 8, 0) };
                    foreach (var child in children)
                    {
                        var name = Label("●  " + child.Title + " · " + child.StatusLabel, 10, "#8B8B92"); name.MaxWidth = 180; name.TextTrimming = TextTrimming.CharacterEllipsis; name.Margin = new Thickness(0, 0, 16, 0); row.Children.Add(name);
                    }
                    group.Children.Add(new Border { Height = 28, Background = Brush("#0D0D0F"), CornerRadius = new CornerRadius(0, 0, 10, 10), Child = row });
                }
                body.Children.Add(group);
            }
        }
        FrameworkElement Card(Session session, bool clickable)
        {
            var frame = new Border { Background = Brush("#0C0C0E"), BorderBrush = Brush(session.Status == "completed" ? "#4A7059" : "#181818"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(10), Height = 60, Padding = new Thickness(10, 0, 10, 0) };
            var grid = new Grid(); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(34) }); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.Children.Add(Orb(session, 28));
            var text = new Grid { Margin = new Thickness(12, 9, 0, 9) };
            text.RowDefinitions.Add(new RowDefinition()); text.RowDefinitions.Add(new RowDefinition());
            var top = new DockPanel { LastChildFill = true };
            var metadata = Label((session.Model.Length > 0 ? session.Model : "Codex") + (session.Effort.Length > 0 ? " · " + session.Effort : ""), 10, "#777780");
            metadata.MaxWidth = 170; metadata.TextTrimming = TextTrimming.CharacterEllipsis; metadata.Margin = new Thickness(12, 0, 0, 0); DockPanel.SetDock(metadata, Dock.Right); top.Children.Add(metadata);
            var title = Label(session.Title, 13, "#EAEAED"); title.FontWeight = FontWeights.SemiBold; title.TextTrimming = TextTrimming.CharacterEllipsis; top.Children.Add(title); text.Children.Add(top);
            var bottom = new DockPanel { LastChildFill = true };
            var tokens = Label((session.TotalTokens.HasValue ? FormatTokens(session.TotalTokens.Value) : "—") + " tokens", 10, "#73737B"); tokens.ToolTip = "会话累计 Token"; tokens.Margin = new Thickness(12, 0, 0, 0); DockPanel.SetDock(tokens, Dock.Right); bottom.Children.Add(tokens);
            var operation = new TextBlock { VerticalAlignment = VerticalAlignment.Center, FontSize = 11, TextTrimming = TextTrimming.CharacterEllipsis };
            operation.Inlines.Add(new System.Windows.Documents.Run(session.StatusLabel + "  ") { Foreground = StateBrush(session.Status) });
            operation.Inlines.Add(new System.Windows.Documents.Run(session.Operation) { Foreground = Brush("#82828A") });
            bottom.Children.Add(operation); Grid.SetRow(bottom, 1); text.Children.Add(bottom); Grid.SetColumn(text, 1); grid.Children.Add(text); frame.Child = grid;
            AutomationProperties.SetName(frame, session.Title + "，" + session.StatusLabel);
            if (clickable)
            {
                frame.Cursor = Cursors.Hand; frame.Focusable = true; frame.ToolTip = "查看任务详情";
                Action open = delegate { detailId = session.Id; usage = settings = false; Render(true); scroll.ScrollToTop(); };
                frame.MouseLeftButtonUp += delegate { open(); };
                frame.KeyDown += delegate(object sender, KeyEventArgs e) { if (e.Key == Key.Enter || e.Key == Key.Space) { open(); e.Handled = true; } };
                frame.MouseEnter += delegate { frame.Background = Brush("#151518"); };
                frame.MouseLeave += delegate { frame.Background = Brush("#0C0C0E"); };
            }
            return frame;
        }
        void DetailPage(Session session)
        {
            body.Children.Add(Card(session, false));
            var statusRow = new DockPanel { Margin = new Thickness(8, 16, 8, 12) };
            if (session.Terminal)
            {
                var archive = Button("归档", "仅在本次运行中隐藏此卡片", delegate { archived.Add(session.Id); detailId = ""; Render(true); }); DockPanel.SetDock(archive, Dock.Right); statusRow.Children.Add(archive);
            }
            statusRow.Children.Add(Label(session.Status == "completed" ? "完成结果" : "公开进展", 12, "#C7C7CF")); body.Children.Add(statusRow);
            string text = session.Status == "completed" && session.Result.Length > 0 ? session.Result : session.PublicText;
            if (text.Length == 0) text = session.Status == "waiting" ? "此任务正在等待你的回复。请回到 Codex 完成确认。" : "尚未收到公开进展。";
            var result = new TextBox { Text = text, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, Foreground = Brush("#B3B3BA"), Background = Brushes.Transparent, BorderThickness = new Thickness(0), FontSize = 13, Margin = new Thickness(8, 0, 8, 10), Padding = new Thickness(0), MaxHeight = 210, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            AutomationProperties.SetName(result, "任务公开内容"); body.Children.Add(result);
            if (session.Status == "waiting") { var notice = Label("当前预览为只读观察，请在 Codex 中操作。", 11, "#E6A859"); notice.Margin = new Thickness(8, 6, 0, 6); body.Children.Add(notice); }
        }
        QuotaWindow LatestQuota(bool primary)
        {
            return snapshot.Sessions.Select(s => primary ? s.Primary : s.Secondary).Where(q => q != null).OrderByDescending(q => q.Observed).FirstOrDefault();
        }
        void UsagePage()
        {
            var title = Label("额度与用量", 18, "#E5E5E9"); title.Margin = new Thickness(8, 10, 0, 16); body.Children.Add(title);
            QuotaRow("主要额度窗口", LatestQuota(true)); QuotaRow("次要额度窗口", LatestQuota(false));
            long total = snapshot.Sessions.Where(s => s.Kind == "user" && s.TotalTokens.HasValue).Sum(s => s.TotalTokens.Value);
            var amount = Label("已读取会话累计  " + (snapshot.Sessions.Any(s => s.Kind == "user" && s.TotalTokens.HasValue) ? FormatTokens(total) : "—") + " tokens", 12, "#A6A6AE"); amount.Margin = new Thickness(8, 10, 0, 8); body.Children.Add(amount);
            var footnote = Label("额度来自最近的本地记录，可能滞后；不代表实时账户查询。", 10, "#686871"); footnote.Margin = new Thickness(8, 0, 0, 0); footnote.TextWrapping = TextWrapping.Wrap; body.Children.Add(footnote);
        }
        void QuotaRow(string title, QuotaWindow quota)
        {
            var box = new StackPanel { Margin = new Thickness(8, 0, 8, 16) };
            var row = new DockPanel();
            var number = Label(quota != null && quota.Remaining.HasValue ? Math.Round(quota.Remaining.Value) + "% 剩余" : "—", 16, "#DBDBE0"); DockPanel.SetDock(number, Dock.Right); row.Children.Add(number);
            row.Children.Add(Label(title + (quota != null && quota.Minutes.HasValue ? " · " + WindowDuration(quota.Minutes.Value) : ""), 12, "#A7A7AF")); box.Children.Add(row);
            var track = new Grid { Height = 5, Margin = new Thickness(0, 10, 0, 7) }; track.Children.Add(new Border { Background = Brush("#202026"), CornerRadius = new CornerRadius(2.5) });
            if (quota != null && quota.Remaining.HasValue)
            {
                var fill = new Border { HorizontalAlignment = HorizontalAlignment.Left, Background = Brush(quota.Remaining < 15 ? "#E8AA5F" : "#73CFA0"), CornerRadius = new CornerRadius(2.5) };
                track.SizeChanged += delegate { fill.Width = track.ActualWidth * quota.Remaining.Value / 100; }; track.Children.Add(fill);
            }
            box.Children.Add(track);
            string reset = "暂无额度记录";
            if (quota != null)
            {
                reset = "更新于 " + quota.Observed.ToLocalTime().ToString("HH:mm");
                if (quota.Reset.HasValue) try { reset += " · 重置 " + new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(quota.Reset.Value).ToLocalTime().ToString("MM-dd HH:mm"); } catch (ArgumentOutOfRangeException) { }
            }
            box.Children.Add(Label(reset, 10, "#6F6F78")); body.Children.Add(box);
        }
        void SettingsPage()
        {
            var title = Label("灵动岛设置", 18, "#E5E5E9"); title.Margin = new Thickness(8, 8, 0, 14); body.Children.Add(title);
            var pin = new CheckBox { Content = "保持展开", IsChecked = pinned, Foreground = Brush("#C6C6CF"), Margin = new Thickness(8, 8, 8, 12) };
            pin.Click += delegate { pinned = pin.IsChecked == true; SavePreferences(); }; body.Children.Add(pin);
            var motion = new CheckBox { Content = "减少动态效果", IsChecked = reduced, Foreground = Brush("#C6C6CF"), Margin = new Thickness(8, 8, 8, 16) };
            motion.Click += delegate { reduced = motion.IsChecked == true; SavePreferences(); Render(true); }; body.Children.Add(motion);
            var hint = Label("数据目录", 11, "#777780"); hint.Margin = new Thickness(8, 0, 0, 6); body.Children.Add(hint);
            var path = Label(source.Home, 11, "#A4A4AE"); path.Margin = new Thickness(8, 0, 8, 12); path.TextTrimming = TextTrimming.CharacterEllipsis; path.ToolTip = source.Home; body.Children.Add(path);
            var description = Label("v0.7.7-build.1 → Windows 开发预览\n悬停展开 · 移开收起 · 点击卡片查看详情\n仅观察本地记录；审批操作仍在 Codex 中完成。", 11, "#777780"); description.Margin = new Thickness(8, 0, 8, 14); description.TextWrapping = TextWrapping.Wrap; description.LineHeight = 20; body.Children.Add(description);
            var actions = new StackPanel { Orientation = Orientation.Horizontal };
            actions.Children.Add(Button("重新居中", "移动到当前屏幕顶部", delegate { CenterOnScreen(); }));
            actions.Children.Add(Button("退出预览", "退出 QuotaView Windows", Close)); body.Children.Add(actions);
        }
        void Footer()
        {
            var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            actions.Children.Add(Button("↻", "刷新本地记录", async delegate { await Refresh(); }));
            actions.Children.Add(Button("⚙", "设置", delegate { settings = true; detailId = ""; usage = false; Render(true); }));
            DockPanel.SetDock(actions, Dock.Right); footer.Children.Add(actions);
            connection.Text = (snapshot.Available ? "●  " : "○  ") + snapshot.Status + " · 只读";
            connection.Foreground = Brush(snapshot.Available ? "#818B86" : "#A08B6B");
            connection.ToolTip = "连接状态仅表示本地记录读取成功，不代表桌面审批通道已连接。";
            footer.Children.Add(connection);
        }
        void SetExpanded(bool value)
        {
            hoverTimer.Stop(); closeTimer.Stop(); expanded = value;
            if (!value) { detailId = ""; usage = settings = false; AnimateSize(CompactWidth, 30); }
            Render(true);
        }
        void Escape() { if (detailId.Length > 0 || usage || settings) { detailId = ""; usage = settings = false; Render(true); } else SetExpanded(false); }
        void AnimateSize(double width, double height)
        {
            if (Math.Abs(Width - width) < 0.1 && Math.Abs(Height - height) < 0.1) return;
            double currentWidth = ActualWidth > 0 ? ActualWidth : Width, currentHeight = ActualHeight > 0 ? ActualHeight : Height;
            BeginAnimation(WidthProperty, null); BeginAnimation(HeightProperty, null); Width = width; Height = height;
            if (reduced || !SystemParameters.ClientAreaAnimation) return;
            var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
            BeginAnimation(WidthProperty, new DoubleAnimation(currentWidth, width, TimeSpan.FromMilliseconds(260)) { EasingFunction = ease, FillBehavior = FillBehavior.Stop });
            BeginAnimation(HeightProperty, new DoubleAnimation(currentHeight, height, TimeSpan.FromMilliseconds(260)) { EasingFunction = ease, FillBehavior = FillBehavior.Stop });
        }
        void UpdateGeometry()
        {
            double w = ActualWidth, h = ActualHeight; if (w <= 0 || h <= 0) return;
            // Direct translation of IslandNotchShape from the pinned release.
            double radius = expanded ? 24 : 16, lip = Math.Min(radius * 2 / 3, Math.Min(16, Math.Min(w / 6, h / 3)));
            double bottom = Math.Min(radius, Math.Min((w - lip * 2) / 2, h / 2)), k = 0.5522847498;
            var geometry = new StreamGeometry();
            using (var c = geometry.Open())
            {
                c.BeginFigure(new Point(0, 0), true, true); c.LineTo(new Point(w, 0), true, false);
                c.BezierTo(new Point(w - lip * k, 0), new Point(w - lip, lip * (1 - k)), new Point(w - lip, lip), true, false);
                c.LineTo(new Point(w - lip, h - bottom), true, false);
                c.BezierTo(new Point(w - lip, h - bottom * (1 - k)), new Point(w - lip - bottom * (1 - k), h), new Point(w - lip - bottom, h), true, false);
                c.LineTo(new Point(lip + bottom, h), true, false);
                c.BezierTo(new Point(lip + bottom * (1 - k), h), new Point(lip, h - bottom * (1 - k)), new Point(lip, h - bottom), true, false);
                c.LineTo(new Point(lip, lip), true, false);
                c.BezierTo(new Point(lip, lip * (1 - k)), new Point(lip * k, 0), new Point(0, 0), true, false);
            }
            geometry.Freeze(); shell.Data = geometry; root.Clip = geometry;
        }
        void CenterOnScreen()
        {
            var screen = Forms.Screen.FromHandle(new WindowInteropHelper(this).Handle);
            var sourceHwnd = PresentationSource.FromVisual(this); var transform = sourceHwnd != null && sourceHwnd.CompositionTarget != null ? sourceHwnd.CompositionTarget.TransformFromDevice : Matrix.Identity;
            Point start = transform.Transform(new Point(screen.WorkingArea.Left, screen.WorkingArea.Top));
            Point end = transform.Transform(new Point(screen.WorkingArea.Right, screen.WorkingArea.Bottom));
            anchorX = (start.X + end.X) / 2; anchorY = start.Y; positionReady = true;
            Left = anchorX - Width / 2; Top = anchorY;
        }
        void ShowMenu()
        {
            var menu = new ContextMenu { Background = Brush("#17171C"), Foreground = Brush("#DDDDE3") };
            AddMenu(menu, expanded ? "收起" : "展开", delegate { SetExpanded(!expanded); });
            AddMenu(menu, pinned ? "取消固定展开" : "固定展开", delegate { pinned = !pinned; SavePreferences(); SetExpanded(true); });
            AddMenu(menu, "设置", delegate { settings = true; usage = false; detailId = ""; SetExpanded(true); });
            AddMenu(menu, "退出", Close); menu.IsOpen = true;
        }
        static void AddMenu(ContextMenu menu, string text, Action action) { var item = new MenuItem { Header = text }; item.Click += delegate { action(); }; menu.Items.Add(item); }
        void LoadPreferences()
        {
            try { string p = System.IO.Path.Combine(stateDirectory, "preferences.txt"); if (File.Exists(p)) { string data = File.ReadAllText(p); pinned = data.Contains("pinned=true"); reduced = data.Contains("reduced=true"); } } catch (IOException) { }
        }
        void SavePreferences() { try { File.WriteAllText(System.IO.Path.Combine(stateDirectory, "preferences.txt"), "pinned=" + pinned.ToString().ToLowerInvariant() + "\nreduced=" + reduced.ToString().ToLowerInvariant()); } catch (IOException) { } }
        ActivityOrb Orb(Session session, double size)
        {
            var orb = new ActivityOrb { Width = size, Height = size, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Status = session.Status, Active = session.Active && session.StatusLabel != "等待更新", Phase = reduced ? 0 : clock.Elapsed.TotalSeconds };
            orbs.Add(orb); return orb;
        }
        static TextBlock Label(string text, double size, string color) { return new TextBlock { Text = text, FontSize = size, Foreground = Brush(color), VerticalAlignment = VerticalAlignment.Center }; }
        static Button Button(string content, string hint, Action action)
        {
            var button = new Button { Content = content, ToolTip = hint, VerticalAlignment = VerticalAlignment.Center, MinHeight = 26 };
            AutomationProperties.SetName(button, hint); button.Click += delegate { action(); }; return button;
        }
        internal static SolidColorBrush Brush(string hex) { var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex)); brush.Freeze(); return brush; }
        internal static Brush StateBrush(string state) { return Brush(state == "completed" ? "#5CCC8C" : state == "waiting" ? "#E6A859" : state == "error" ? "#F26E6B" : "#B9BAC2"); }
        static string FormatTokens(long n) { return n >= 1000000 ? (n / 1000000d).ToString("0.0", CultureInfo.InvariantCulture) + "M" : n >= 1000 ? (n / 1000d).ToString("0.0", CultureInfo.InvariantCulture) + "K" : n.ToString(CultureInfo.InvariantCulture); }
        static string WindowDuration(long minutes) { return minutes >= 1440 ? (minutes / 1440d).ToString("0.#") + " 天" : (minutes / 60d).ToString("0.#") + " 小时"; }
        IntPtr WindowProc(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (message == 0x007E || message == 0x02E0) Dispatcher.BeginInvoke(new Action(CenterOnScreen), DispatcherPriority.Loaded);
            return IntPtr.Zero;
        }
        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hwnd, int index);
        [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hwnd, int index, int value);
    }

    internal sealed class ActivityOrb : FrameworkElement
    {
        public string Status = "thinking";
        public double Phase;
        public bool Active;
        protected override void OnRender(DrawingContext dc)
        {
            base.OnRender(dc);
            double r = Math.Min(ActualWidth, ActualHeight) / 2, cx = ActualWidth / 2, cy = ActualHeight / 2;
            Color tint = (Color)ColorConverter.ConvertFromString(Status == "waiting" ? "#E9B568" : Status == "completed" ? "#68D99A" : Status == "error" ? "#EE7676" : "#86BFD1");
            var fill = new RadialGradientBrush(); fill.GradientOrigin = new Point(0.3, 0.25);
            fill.GradientStops.Add(new GradientStop(Color.FromArgb(180, tint.R, tint.G, tint.B), 0));
            fill.GradientStops.Add(new GradientStop(Color.FromRgb(30, 46, 56), 0.5)); fill.GradientStops.Add(new GradientStop(Color.FromRgb(6, 8, 12), 1));
            dc.DrawEllipse(fill, new Pen(new SolidColorBrush(Color.FromArgb(75, tint.R, tint.G, tint.B)), 0.7), new Point(cx, cy), r - 1, r - 1);
            for (int i = 0; i < 3; i++)
            {
                dc.PushTransform(new RotateTransform(Phase * (12 + i * 3) + i * 58, cx, cy));
                var color = Color.FromArgb((byte)(100 - i * 20), tint.R, tint.G, tint.B);
                dc.DrawEllipse(null, new Pen(new SolidColorBrush(color), 0.8), new Point(cx, cy), (r - 3) * (0.50 + 0.1 * Math.Sin(Phase + i)), r - 3);
                dc.Pop();
            }
            dc.DrawEllipse(new SolidColorBrush(Color.FromArgb(130, 232, 245, 251)), null, new Point(cx - r * 0.25, cy - r * 0.3), r * 0.10, r * 0.10);
        }
    }
}
