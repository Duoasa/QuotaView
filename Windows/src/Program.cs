using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows;
using System.Windows.Threading;

namespace QuotaView.Windows
{
    internal static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            string stateDirectory = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", ".local");
            Directory.CreateDirectory(stateDirectory);
            bool created;
            using (var mutex = new Mutex(true, "Local\\QuotaView.Windows.Preview", out created))
            {
                if (!created) { MessageBox.Show("QuotaView Windows 已在运行。请点击屏幕顶部灵动岛，或使用系统托盘入口。", "QuotaView"); return 0; }
                var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
                app.DispatcherUnhandledException += delegate(object sender, DispatcherUnhandledExceptionEventArgs e)
                {
                    // No transcripts, paths, credentials or tool arguments in diagnostics.
                    try { File.AppendAllText(Path.Combine(stateDirectory, "errors.log"), DateTime.UtcNow.ToString("O") + " " + e.Exception.GetType().Name + Environment.NewLine); } catch { }
                    MessageBox.Show("开发版遇到错误，请关闭后重新启动。错误类型：" + e.Exception.GetType().Name, "QuotaView Windows");
                    e.Handled = true; app.Shutdown(1);
                };
                string home = Environment.GetEnvironmentVariable("CODEX_HOME");
                if (string.IsNullOrWhiteSpace(home)) home = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
                var window = new IslandWindow(new LocalSessions(home), stateDirectory, args.Contains("--expanded"));
                app.Run(window);
                return 0;
            }
        }
    }
}
