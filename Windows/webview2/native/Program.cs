namespace QuotaView;

internal static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--apply-windows-update")
        {
            Environment.ExitCode = WindowsUpdateInstaller.Run(args[1]);
            return;
        }
        if (args.Contains("--stdio-adapter-test"))
        {
            string? line;
            while ((line = Console.ReadLine()) != null)
            {
                Console.WriteLine(line);
                Console.Out.Flush();
            }
            return;
        }
        if (args.Any(x => x is "--helper-smoke-test" or "--foreground-monitor" or "--quotaview-hook" or "--quotaview-codex-hook"))
        {
            Environment.ExitCode = QuotaViewHelper.Run(args);
            return;
        }
        ApplicationConfiguration.Initialize();
        bool isolated = args.Contains("--smoke-test") || args.Contains("--adapter-test") || args.Contains("--approval-test") || args.Contains("--approval-demo");
        using var mutex = new Mutex(true, isolated ? null : @"Local\QuotaView.WebView2", out bool first);
        if (!first)
        {
            try
            {
                EventWaitHandle.OpenExisting(@"Local\QuotaView.WebView2.Activate").Set();
            }
            catch { }
            return;
        }
        Application.ThreadException += (_, e) => Host.Fatal(e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Host.Fatal(e.ExceptionObject as Exception ?? new Exception("Unhandled error"));
        using var host = new Host(isolated);
        Application.Run(host);
    }
}
