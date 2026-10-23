using System;
using System.IO;
using System.Linq;
using System.Text;
using QuotaView.Windows;

internal static class Smoke
{
    static int assertions;
    static void Check(bool condition, string name) { assertions++; if (!condition) throw new Exception(name); }
    static string Envelope(string type, string payload) { return "{\"timestamp\":\"2026-10-08T12:00:00Z\",\"type\":\"" + type + "\",\"payload\":" + payload + "}"; }
    static Session Started()
    {
        var s = new Session();
        s.Apply(Envelope("session_meta", "{\"id\":\"s1\",\"source\":\"vscode\",\"cwd\":\"F:/example\"}"));
        s.Apply(Envelope("event_msg", "{\"type\":\"task_started\",\"turn_id\":\"t1\"}")); return s;
    }
    static int Main(string[] args)
    {
        try
        {
            var s = Started(); Check(s.Active && s.Kind == "user", "explicit start is active");
            s.Apply(Envelope("response_item", "{\"type\":\"reasoning\",\"summary\":\"PRIVATE\",\"encrypted_content\":\"SECRET\"}"));
            s.Apply(Envelope("response_item", "{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"PRIVATE\"}]}"));
            s.Apply(Envelope("event_msg", "{\"type\":\"agent_message\",\"message\":\"PRIVATE\"}"));
            Check(s.PublicText == "" && s.Result == "", "private content is excluded");
            s.Apply(Envelope("response_item", "{\"type\":\"message\",\"role\":\"assistant\",\"phase\":\"commentary\",\"content\":[{\"type\":\"output_text\",\"text\":\"公开进展\"}]}"));
            Check(s.PublicText == "公开进展", "public commentary is admitted");
            s.Apply(Envelope("response_item", "{\"type\":\"message\",\"role\":\"assistant\",\"recipient\":\"agent\",\"phase\":\"commentary\",\"content\":[{\"type\":\"output_text\",\"text\":\"PRIVATE\"}]}"));
            Check(s.PublicText == "公开进展", "inter-agent message is excluded");
            s.Apply(Envelope("event_msg", "{\"type\":\"task_complete\",\"turn_id\":\"old\"}")); Check(s.Active, "old completion cannot finish new turn");
            s.Apply(Envelope("token_usage_record", "{\"thread_id\":\"s1\",\"turn_id\":\"t1\",\"thread_token_usage\":{\"total_tokens\":32000},\"turn_token_usage\":{\"total_tokens\":800}}"));
            Check(s.TotalTokens == 32000 && s.TurnTokens == 800, "scoped token count");
            s.Apply(Envelope("token_usage_record", "{\"thread_id\":\"other\",\"turn_id\":\"t1\",\"thread_token_usage\":{\"total_tokens\":99999}}")); Check(s.TotalTokens == 32000, "foreign usage ignored");
            s.Apply(Envelope("event_msg", "{\"type\":\"token_count\",\"rate_limits\":{\"primary\":{\"used_percent\":25,\"window_minutes\":300,\"resets_at\":1900000000}}}")); Check(s.Primary.Remaining == 75 && s.Secondary == null, "missing quota stays missing");
            s.Apply(Envelope("response_item", "{\"type\":\"function_call\",\"name\":\"request_user_input\",\"call_id\":\"q1\"}")); Check(s.Status == "waiting", "question observed");
            s.Apply(Envelope("response_item", "{\"type\":\"function_call_output\",\"call_id\":\"old\",\"output\":\"PRIVATE\"}")); Check(s.Status == "waiting", "unrelated output cannot settle question");
            s.Apply(Envelope("response_item", "{\"type\":\"function_call_output\",\"call_id\":\"q1\"}")); Check(s.Status == "thinking", "matching answer settles question");
            s.Apply(Envelope("response_item", "{\"type\":\"message\",\"role\":\"assistant\",\"phase\":\"final\",\"content\":[{\"type\":\"output_text\",\"text\":\"完成结果\"}]}")); Check(s.Active, "final text alone is not completion");
            s.Apply(Envelope("event_msg", "{\"type\":\"task_complete\",\"turn_id\":\"t1\"}")); Check(s.Terminal && s.Result == "完成结果", "real completion retains receipt");
            s.Apply(Envelope("event_msg", "{\"type\":\"task_started\",\"turn_id\":\"t2\"}")); Check(s.Active && s.Result == "" && s.TurnTokens == null, "new turn clears old result and direct tokens");
            s.Apply("not json"); Check(s.Active, "malformed line is harmless");
            var context = new Session(); context.Apply(Envelope("session_meta", "{\"id\":\"s2\",\"source\":\"vscode\"}")); context.Apply(Envelope("turn_context", "{\"turn_id\":\"t2\",\"model\":\"test-model\"}")); Check(!context.Active, "context cannot manufacture start");
            var child = new Session(); child.Apply(Envelope("session_meta", "{\"id\":\"c\",\"source\":{\"subagent\":{\"thread_spawn\":{\"parent_thread_id\":\"s1\"}}}}")); Check(child.Kind == "child" && child.ParentId == "s1", "explicit child relationship");
            var internalTask = new Session(); internalTask.Apply(Envelope("session_meta", "{\"id\":\"i\",\"source\":{\"subagent\":\"review\"}}")); Check(internalTask.Kind == "unknown", "internal tasks excluded");
            var memory = Started(); memory.Apply(Envelope("event_msg", "{\"type\":\"task_started\",\"turn_id\":\"memory\",\"trigger\":\"memory_consolidation\"}")); Check(memory.Kind == "memory", "memory trigger is isolated");
            memory.Apply(Envelope("event_msg", "{\"type\":\"task_started\",\"turn_id\":\"user-again\"}")); Check(memory.Kind == "user", "turn purpose does not permanently change source identity");
            string folder = Path.Combine(Path.GetTempPath(), "quotaview-smoke-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(folder);
            try
            {
                string path = Path.Combine(folder, "rollout.jsonl");
                string meta = Envelope("session_meta", "{\"id\":\"s1\",\"source\":\"vscode\"}");
                string start = Envelope("event_msg", "{\"type\":\"task_started\",\"turn_id\":\"t1\"}");
                string message = Envelope("response_item", "{\"type\":\"message\",\"role\":\"assistant\",\"phase\":\"commentary\",\"content\":[{\"type\":\"output_text\",\"text\":\"中文分段\"}]}");
                File.WriteAllText(path, meta + "\n" + start + "\n", new UTF8Encoding(false));
                var tail = new SessionTail(path); tail.Read();
                byte[] data = Encoding.UTF8.GetBytes(message + "\n"); int split = Array.IndexOf(data, (byte)0xE4) + 1;
                using (var writer = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite)) writer.Write(data, 0, split);
                tail.Read(); Check(tail.State.PublicText == "", "partial UTF-8 line waits");
                using (var writer = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite)) writer.Write(data, split, data.Length - split);
                tail.Read(); Check(tail.State.PublicText == "中文分段", "split UTF-8 line resumes exactly");
                int revision = tail.State.Revision; tail.Read(); Check(tail.State.Revision == revision, "unchanged file not replayed");
                File.WriteAllText(path, meta + "\n", new UTF8Encoding(false)); tail.Read(); Check(!tail.State.Active, "truncation resets lifecycle");
                File.AppendAllText(path, new string('x', 1048580) + "\n" + start + "\n", new UTF8Encoding(false)); tail.Read(); Check(tail.State.Active, "oversized line skipped without losing subsequent start");
            }
            finally { foreach (var file in Directory.GetFiles(folder)) File.Delete(file); Directory.Delete(folder); }
            Console.WriteLine("PASS: " + assertions + " lifecycle, privacy, quota and incremental-read assertions.");
            if (args.Contains("--probe"))
            {
                string home = Environment.GetEnvironmentVariable("CODEX_HOME") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
                var reader = new LocalSessions(home); var snapshot = reader.Poll(); snapshot = reader.Poll();
                Console.WriteLine("Local probe: available=" + snapshot.Available + ", user_sessions=" + snapshot.Sessions.Count(x => x.Kind == "user") + ", active=" + snapshot.Sessions.Count(x => x.Kind == "user" && x.Active) + ", quota=" + snapshot.Sessions.Any(x => x.Primary != null));
            }
            return 0;
        }
        catch (Exception e) { Console.Error.WriteLine("FAIL: " + e.Message); return 1; }
    }
}
