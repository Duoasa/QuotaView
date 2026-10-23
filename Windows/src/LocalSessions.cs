using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;

namespace QuotaView.Windows
{
    internal static class Json
    {
        public static Dictionary<string, object> Parse(string text)
        {
            try { return new JavaScriptSerializer { MaxJsonLength = 1048576, RecursionLimit = 64 }.DeserializeObject(text) as Dictionary<string, object>; }
            catch (ArgumentException) { return null; }
            catch (InvalidOperationException) { return null; }
        }
        public static object Get(object source, string key) { var d = source as Dictionary<string, object>; object v; return d != null && d.TryGetValue(key, out v) ? v : null; }
        public static string Text(object source, string key) { return Get(source, key) as string ?? ""; }
        public static long? Number(object source, string key)
        {
            object value = Get(source, key); if (value == null || value is bool) return null;
            long n; return long.TryParse(Convert.ToString(value, CultureInfo.InvariantCulture), out n) && n >= 0 ? (long?)n : null;
        }
        public static double? Real(object source, string key)
        {
            double n; return double.TryParse(Convert.ToString(Get(source, key), CultureInfo.InvariantCulture), NumberStyles.Float, CultureInfo.InvariantCulture, out n) && !double.IsNaN(n) && !double.IsInfinity(n) ? (double?)n : null;
        }
        public static string Bound(string s, int size) { return string.IsNullOrEmpty(s) ? "" : s.Substring(0, Math.Min(s.Length, size)); }
        public static DateTime Date(object source, string key, DateTime fallback)
        {
            DateTime d; return DateTime.TryParse(Text(source, key), CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out d) ? d : fallback;
        }
    }

    internal sealed class QuotaWindow
    {
        public double? Remaining;
        public long? Reset;
        public long? Minutes;
        public DateTime Observed;
        public QuotaWindow Clone() { return (QuotaWindow)MemberwiseClone(); }
    }

    internal sealed class Session
    {
        public string Id = "", Title = "Codex 会话", Model = "", Effort = "", ParentId = "", Kind = "unknown", BaseKind = "unknown";
        public string Turn = "", Status = "unknown", Operation = "等待任务事件", PublicText = "", Result = "", PendingQuestion = "";
        public long? TotalTokens, TurnTokens;
        public DateTime Updated, Started, Ended;
        public QuotaWindow Primary, Secondary;
        public int Revision;
        public bool Terminal { get { return Status == "completed" || Status == "interrupted" || Status == "error"; } }
        public bool Active { get { return Turn.Length > 0 && !Terminal; } }
        public Session Clone() { var s = (Session)MemberwiseClone(); s.Primary = Primary == null ? null : Primary.Clone(); s.Secondary = Secondary == null ? null : Secondary.Clone(); return s; }
        public string StatusLabel
        {
            get
            {
                if (Active && DateTime.UtcNow - Updated > TimeSpan.FromMinutes(10)) return "等待更新";
                switch (Status) { case "thinking": return "思考中"; case "working": return "执行中"; case "waiting": return "待确认"; case "compacting": return "整理上下文"; case "completed": return "已完成"; case "interrupted": return "已中断"; case "error": return "出错"; default: return "等待事件"; }
            }
        }

        // Port of the release's explicit lifecycle / public-content rules. Private
        // reasoning, user messages and agent-to-agent messages are never projected.
        public void Apply(string line)
        {
            if (line.Length == 0 || line.Length > 1048576) return;
            var root = Json.Parse(line); if (root == null) return;
            var p = Json.Get(root, "payload"); if (p == null) return;
            string type = Json.Text(root, "type");
            DateTime at = Json.Date(root, "timestamp", DateTime.UtcNow);
            if (type == "session_meta")
            {
                string id = Json.Text(p, "id"); if (id.Length == 0 || (Id.Length > 0 && Id != id)) return;
                Id = id;
                string cwd = Json.Text(p, "cwd");
                if (cwd.Length > 0) { Title = Json.Bound(cwd.TrimEnd('/', '\\').Split('/', '\\').Last(), 120); }
                object source = Json.Get(p, "source"); string namedSource = source as string ?? "";
                object sub = Json.Get(source, "subagent") ?? Json.Get(source, "subAgent");
                object spawn = Json.Get(sub, "thread_spawn");
                ParentId = Json.Text(spawn, "parent_thread_id");
                Kind = ParentId.Length > 0 ? "child" : namedSource == "cli" || namedSource == "vscode" || namedSource == "exec" || namedSource == "appServer" || namedSource == "app-server" || namedSource == "desktop" ? "user" : "unknown";
                if (Json.Get(sub, "memory_consolidation") != null || (sub as string) == "memory_consolidation") Kind = "memory";
                string nativePurpose = Json.Text(p, "thread_source");
                if (nativePurpose == "memory_consolidation") Kind = "memory";
                else if (nativePurpose == "review" || nativePurpose == "guardian" || nativePurpose == "compact") Kind = "unknown";
                BaseKind = Kind;
                Revision++; return;
            }
            if (Id.Length == 0) return;
            if (type == "turn_context")
            {
                string thread = Json.Text(p, "thread_id"); if (thread.Length > 0 && thread != Id) return;
                string model = Json.Text(p, "model"); if (model.Length > 0) Model = Json.Bound(model, 80);
                Effort = Json.Bound(Json.Text(p, "effort"), 24); Revision++; return;
            }
            if (type == "event_msg")
            {
                string evt = Json.Text(p, "type");
                if (evt == "task_started")
                {
                    string turn = Json.Text(p, "turn_id"); if (turn.Length == 0) return;
                    Turn = turn; Status = "thinking"; Operation = "正在处理任务"; Started = at; Ended = DateTime.MinValue;
                    PublicText = Result = PendingQuestion = ""; TurnTokens = null;
                    Kind = BaseKind;
                    if (Json.Text(p, "trigger") == "memory_consolidation") Kind = "memory";
                    Updated = at; Revision++; return;
                }
                if (evt == "token_count")
                {
                    var limits = Json.Get(p, "rate_limits");
                    Primary = ReadQuota(Json.Get(limits, "primary"), at) ?? Primary;
                    Secondary = ReadQuota(Json.Get(limits, "secondary"), at) ?? Secondary;
                    var info = Json.Get(p, "info"); TotalTokens = Json.Number(Json.Get(info, "total_token_usage"), "total_tokens") ?? TotalTokens;
                    Revision++; return;
                }
                string eventTurn = Json.Text(p, "turn_id");
                if (!Active || (eventTurn.Length > 0 && eventTurn != Turn)) return;
                if (evt == "task_complete" && eventTurn == Turn)
                {
                    Status = "completed"; Operation = "任务已完成"; Ended = at; PendingQuestion = "";
                    if (Result.Length == 0) Result = PublicText;
                }
                else if (evt == "turn_aborted" && eventTurn == Turn) { Status = "interrupted"; Operation = "任务已中断"; PendingQuestion = ""; Ended = at; }
                else if ((evt == "item_started" || evt == "item_completed") && Json.Text(Json.Get(p, "item"), "type") == "ContextCompaction")
                { Status = evt == "item_started" ? "compacting" : "thinking"; Operation = evt == "item_started" ? "正在整理上下文" : "继续处理任务"; }
                else return;
                Updated = at; Revision++; return;
            }
            if (type == "token_usage_record")
            {
                if (Json.Text(p, "thread_id") != Id || Json.Text(p, "turn_id") != Turn) return;
                TotalTokens = Json.Number(Json.Get(p, "thread_token_usage"), "total_tokens") ?? TotalTokens;
                TurnTokens = Json.Number(Json.Get(p, "turn_token_usage"), "total_tokens") ?? TurnTokens; Revision++; return;
            }
            if (type != "response_item" || !Active) return;
            string itemType = Json.Text(p, "type");
            if (itemType == "message" && Json.Text(p, "role") == "assistant")
            {
                string phase = Json.Text(p, "phase"), recipient = Json.Text(p, "recipient");
                if ((phase != "commentary" && phase != "final") || (recipient.Length > 0 && recipient != "all")) return;
                var contents = Json.Get(p, "content") as IEnumerable; if (contents == null) return;
                var text = new StringBuilder();
                foreach (var part in contents) if (Json.Text(part, "type") == "output_text") { text.AppendLine(Json.Bound(Json.Text(part, "text"), 12000)); if (text.Length > 12000) break; }
                if (text.Length == 0) return;
                PublicText = Json.Bound(text.ToString().Trim(), 12000); if (phase == "final") Result = PublicText;
                if (Status != "waiting") { Status = "thinking"; Operation = Json.Bound(PublicText.Replace('\n', ' ').Replace('\r', ' '), 160); }
            }
            else if (itemType == "function_call" || itemType == "custom_tool_call")
            {
                string name = Json.Text(p, "name");
                if (name == "request_user_input" || name.EndsWith(".request_user_input", StringComparison.Ordinal))
                { PendingQuestion = Json.Text(p, "call_id"); Status = "waiting"; Operation = "请在 Codex 中完成确认"; }
                else if (Status != "waiting") { Status = "working"; Operation = ToolLabel(name); }
            }
            else if (itemType == "function_call_output" || itemType == "custom_tool_call_output")
            {
                string call = Json.Text(p, "call_id");
                if (PendingQuestion.Length > 0 && call == PendingQuestion) { PendingQuestion = ""; Status = "thinking"; Operation = "已收到回复，继续处理"; }
                else if (Status != "waiting") { Status = "thinking"; Operation = PublicText.Length > 0 ? Json.Bound(PublicText.Replace('\n', ' ').Replace('\r', ' '), 160) : "继续处理任务"; }
            }
            else return;
            Updated = at; Revision++;
        }
        static string ToolLabel(string name)
        {
            if (name.Contains("exec") || name.Contains("stdin")) return "正在执行工具";
            if (name.Contains("patch") || name.Contains("write")) return "正在更新文件";
            if (name.Contains("search") || name.Contains("web")) return "正在查找资料";
            if (name.Contains("read") || name.Contains("fetch")) return "正在读取内容";
            if (name.Contains("wait")) return "等待工具结果";
            return "正在使用工具";
        }
        static QuotaWindow ReadQuota(object obj, DateTime at)
        {
            double? used = Json.Real(obj, "used_percent"); if (!used.HasValue || used < 0 || used > 100) return null;
            return new QuotaWindow { Remaining = 100 - used.Value, Reset = Json.Number(obj, "resets_at"), Minutes = Json.Number(obj, "window_minutes"), Observed = at };
        }
    }

    // Byte offsets advance only as bytes are consumed. Partial UTF-8/JSON lines
    // remain buffered across refreshes. Oversized lines are skipped until newline.
    internal sealed class SessionTail
    {
        public readonly string Path;
        public Session State = new Session();
        public long Offset;
        readonly List<byte> partial = new List<byte>();
        bool dropping;
        public SessionTail(string path) { Path = path; }
        public void Read()
        {
            using (var stream = new FileStream(Path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                if (stream.Length < Offset) { Offset = 0; partial.Clear(); dropping = false; State = new Session(); }
                if (Offset == 0 && stream.Length > 8 * 1024 * 1024)
                {
                    // Metadata is always read first; a bounded tail cannot infer a
                    // missing lifecycle start from model/context records alone.
                    var head = new List<byte>(); int b;
                    while (head.Count < 1048576 && (b = stream.ReadByte()) >= 0) { if (b == 10) break; head.Add((byte)b); }
                    State.Apply(Encoding.UTF8.GetString(head.ToArray()));
                    Offset = stream.Length - 8 * 1024 * 1024; dropping = true;
                }
                stream.Position = Offset;
                byte[] buffer = new byte[65536]; int remaining = 2 * 1024 * 1024, count;
                while (remaining > 0 && (count = stream.Read(buffer, 0, Math.Min(buffer.Length, remaining))) > 0)
                {
                    Offset += count; remaining -= count;
                    for (int i = 0; i < count; i++)
                    {
                        byte b = buffer[i];
                        if (b == 10)
                        {
                            if (!dropping && partial.Count > 0) State.Apply(Encoding.UTF8.GetString(partial.ToArray()));
                            partial.Clear(); dropping = false;
                        }
                        else if (!dropping)
                        { if (partial.Count >= 1048576) { partial.Clear(); dropping = true; } else partial.Add(b); }
                    }
                }
            }
        }
    }

    internal sealed class LocalSnapshot
    {
        public List<Session> Sessions = new List<Session>();
        public string Status = "正在查找本地会话";
        public bool Available;
        public DateTime Refreshed;
    }

    internal sealed class LocalSessions
    {
        public readonly string Home;
        readonly Dictionary<string, SessionTail> tails = new Dictionary<string, SessionTail>(StringComparer.OrdinalIgnoreCase);
        readonly Dictionary<string, string> titles = new Dictionary<string, string>();
        DateTime discovered, indexModified;
        public LocalSessions(string home) { Home = home; }
        public LocalSnapshot Poll()
        {
            var snapshot = new LocalSnapshot { Refreshed = DateTime.UtcNow };
            if (!Directory.Exists(System.IO.Path.Combine(Home, "sessions"))) { snapshot.Status = "未发现 Codex 数据目录"; return snapshot; }
            try
            {
                if ((DateTime.UtcNow - discovered).TotalSeconds >= 10)
                {
                    Discover(); ReadTitles(); discovered = DateTime.UtcNow;
                }
                int failed = 0;
                foreach (var tail in tails.Values)
                {
                    try { tail.Read(); }
                    catch (IOException) { failed++; }
                    catch (UnauthorizedAccessException) { failed++; }
                    Session session = tail.State.Clone(); string title;
                    if (titles.TryGetValue(session.Id, out title)) session.Title = title;
                    if (session.Id.Length > 0 && session.Turn.Length > 0 && session.Kind != "unknown") snapshot.Sessions.Add(session);
                }
                snapshot.Sessions = snapshot.Sessions.OrderByDescending(s => s.Active).ThenByDescending(s => s.Updated).ToList();
                snapshot.Available = failed == 0;
                snapshot.Status = failed > 0 ? "部分记录暂时无法读取" : snapshot.Sessions.Count == 0 ? "等待本地任务" : "本地记录已同步";
            }
            catch (IOException) { snapshot.Status = "本地记录暂时不可用"; }
            catch (UnauthorizedAccessException) { snapshot.Status = "无法读取 Codex 数据目录"; }
            return snapshot;
        }
        void Discover()
        {
            var files = new List<FileInfo>();
            // Bounded discovery: seven date directories, at most 24 recent files.
            for (int d = 0; d < 7; d++)
            {
                string folder = System.IO.Path.Combine(Home, "sessions", DateTime.Now.AddDays(-d).ToString("yyyy/MM/dd", CultureInfo.InvariantCulture));
                if (!Directory.Exists(folder)) continue;
                files.AddRange(new DirectoryInfo(folder).EnumerateFiles("*.jsonl").Where(f => (f.Attributes & FileAttributes.ReparsePoint) == 0));
            }
            var selected = files.OrderByDescending(f => f.LastWriteTimeUtc).Take(24).ToList();
            foreach (var f in selected) if (!tails.ContainsKey(f.FullName)) tails[f.FullName] = new SessionTail(f.FullName);
            var keep = new HashSet<string>(selected.Select(f => f.FullName), StringComparer.OrdinalIgnoreCase);
            foreach (string path in tails.Keys.Where(k => !keep.Contains(k)).ToArray()) tails.Remove(path);
        }
        void ReadTitles()
        {
            string path = System.IO.Path.Combine(Home, "session_index.jsonl"); if (!File.Exists(path)) return;
            DateTime stamp = File.GetLastWriteTimeUtc(path); if (stamp == indexModified) return;
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                if (stream.Length > 1048576) stream.Seek(-1048576, SeekOrigin.End);
                using (var reader = new StreamReader(stream, Encoding.UTF8))
                {
                    if (stream.Position > 0) reader.ReadLine();
                    string line; titles.Clear();
                    while ((line = reader.ReadLine()) != null)
                    {
                        var item = Json.Parse(line); string id = Json.Text(item, "id"), title = Json.Text(item, "thread_name");
                        if (id.Length > 0 && title.Length > 0) titles[id] = Json.Bound(title, 160);
                    }
                }
            }
            indexModified = stamp;
        }
    }
}
