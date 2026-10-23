// QuotaView, MIT. Framework 4.8 is part of supported Windows installations.
// Fail-open hook transport: only a matching live Claude permission reply may
// emit a decision. Codex observation never emits a decision or prompt content.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
#if NET
#nullable disable
using System.Text.Json;
#else
using System.Web.Script.Serialization;
#endif

static class QuotaViewHelper {
    const int WireLimit = 1048576;
#if !NET
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 8388608, RecursionLimit = 64 };
#endif
    static Dictionary<string, object> Obj(object o) { return o as Dictionary<string, object>; }
    static object Get(Dictionary<string, object> d, string k) { object v; return d != null && d.TryGetValue(k, out v) ? v : null; }
    static string Str(Dictionary<string, object> d, string k) { return Get(d, k) as string; }
    static bool Is(Dictionary<string, object> d, string k, bool v) { return Get(d, k) is bool && (bool)Get(d, k) == v; }
    static int Number(Dictionary<string, object> d, string k, int fallback) { var n = Get(d, k); return n is int ? (int)n : fallback; }
#if NET
    static string Encode(object o) { return JsonSerializer.Serialize(o); }
    static object Value(JsonElement e) {
        switch(e.ValueKind) {
        case JsonValueKind.Object: var d = new Dictionary<string, object>(); foreach(var p in e.EnumerateObject()) d[p.Name]=Value(p.Value); return d;
        case JsonValueKind.Array: var a = new List<object>(); foreach(var item in e.EnumerateArray()) a.Add(Value(item)); return a.ToArray();
        case JsonValueKind.String: return e.GetString();
        case JsonValueKind.Number: if(e.TryGetInt32(out var i)) return i; return e.GetDouble();
        case JsonValueKind.True: return true;
        case JsonValueKind.False: return false;
        default: return null;
        }
    }
    static Dictionary<string, object> Decode(string s) { if(s.Length>8388608) throw new IOException(); using(var doc=JsonDocument.Parse(s,new JsonDocumentOptions{MaxDepth=64})) return Obj(Value(doc.RootElement)); }
#else
    static string Encode(object o) { return Json.Serialize(o); }
    static Dictionary<string, object> Decode(string s) { return Obj(Json.DeserializeObject(s)); }
#endif
    static string Clip(string s, int bytes) {
        if (s == null) return null;
        var data = Encoding.UTF8.GetBytes(s); if (data.Length <= bytes) return s;
        int length = bytes; while (length > 0 && (data[length] & 0xc0) == 0x80) length--;
        return Encoding.UTF8.GetString(data, 0, length);
    }
    static bool Id(string s) { return !String.IsNullOrEmpty(s) && Encoding.UTF8.GetByteCount(s) <= 1024 && !Regex.IsMatch(s, "[\\x00-\\x1f\\x7f]"); }
    static string Arg(string[] args, string key) { int i = Array.IndexOf(args, key); return i >= 0 && i + 1 < args.Length ? args[i + 1] : null; }
    static Dictionary<string, object> Route(string path, bool codex) {
        var f = new FileInfo(path);
        if (!f.Exists || (f.Attributes & FileAttributes.ReparsePoint) != 0 || f.Length < 1 || f.Length > (codex ? 16384 : 65536)) throw new IOException();
        var r = Decode(File.ReadAllText(path, Encoding.UTF8));
        string p = Str(r, "provider"); int port = Number(r, "port", 0);
        if (Number(r, "version", 0) != 1 || Str(r, "host") != "127.0.0.1" || port < 1 || port > 65535 || !Regex.IsMatch(Str(r, "authenticationToken") ?? "", "^[a-f0-9]{64}$") || (codex ? p != "codex" || Str(r, "installationId") == null : p != "claude" && p != "dsh" && p != "kimi")) throw new IOException();
        return r;
    }
    static byte[] Input(int limit, int timeout) {
        var task = Task.Run(() => {
            using (var m = new MemoryStream()) { var stream = Console.OpenStandardInput(); var b = new byte[8192]; int n;
                while ((n = stream.Read(b, 0, b.Length)) > 0) { if (m.Length + n > limit) throw new IOException(); m.Write(b, 0, n); } return m.ToArray();
            }
        });
        if (!task.Wait(timeout)) throw new IOException(); return task.Result;
    }
    static Dictionary<string, object> Payload(Dictionary<string, object> input, string provider) {
        string ev = Str(input, "hook_event_name"), sid = Str(input, "session_id");
        if (provider == "codex") {
            if (!Id(sid) || Array.IndexOf(new[] {"SessionStart","SessionEnd","UserPromptSubmit","PreToolUse","PermissionRequest","PostToolUse","PreCompact","PostCompact","SubagentStart","SubagentStop","Interrupt","Stop"}, ev) < 0) return null;
            var p = new Dictionary<string, object> { {"event",ev}, {"sessionId",sid} };
            if (Get(input, "turn_id") != null) { if (!Id(Str(input, "turn_id"))) return null; p["turnId"] = Str(input, "turn_id"); }
            foreach (var pair in new[] { new[] { "tool_use_id", "toolUseId" }, new[] { "tool_name", "toolName" } }) {
                if (Get(input, pair[0]) != null) { if (!Id(Str(input, pair[0]))) return null; p[pair[1]] = Str(input, pair[0]); }
            }
            return p;
        }
        if (ev == null || String.IsNullOrEmpty(sid) || sid.Length > 256) return null;
        var result = new Dictionary<string, object>();
        foreach (var k in new[] {"hook_event_name","session_id","turn_id","prompt_id","tool_name","tool_use_id","tool_call_id","model","session_title","agent_id","agent_type","source","reason","stop_reason"}) if (Str(input,k) != null) result[k] = Clip(Str(input,k),256);
        if (provider == "claude") {
            foreach (var k in new[] {"transcript_path","agent_transcript_path","cwd","notification_type","title","message","last_assistant_message","error"}) if (Str(input,k) != null) result[k] = Clip(Str(input,k), k == "last_assistant_message" ? 65536 : 4096);
            foreach (var k in new[] {"stop_hook_active","is_interrupt"}) if (Get(input,k) is bool) result[k] = Get(input,k);
            foreach (var k in new[] {"tool_input","permission_suggestions"}) if (input.ContainsKey(k)) result[k] = Encoding.UTF8.GetByteCount(Encode(input[k])) <= (k == "tool_input" ? 262144 : 65536) ? input[k] : new Dictionary<string, object> {{"_quotaViewTruncated",true}};
            string effort = Str(input,"effort") ?? Str(Obj(Get(input,"effort")),"level"); if(effort != null) result["effort"] = Clip(effort,64);
        }
        return result;
    }
    static string Line(NetworkStream stream, int limit, int timeout) {
        var watch = Stopwatch.StartNew();
        using (var m = new MemoryStream()) {
            while (m.Length < limit) { int left = timeout - (int)watch.ElapsedMilliseconds; if(left <= 0) throw new IOException(); stream.ReadTimeout = left; int b = stream.ReadByte(); if(b < 0) throw new IOException(); if(b == 10) return Encoding.UTF8.GetString(m.ToArray()); m.WriteByte((byte)b); }
        } throw new IOException();
    }
    static Dictionary<string, object> Send(Dictionary<string, object> route, object payload, bool codex, string kind, bool decision) {
        if (Is(route,"enabled",false) || codex && !Is(route,"enabled",true)) return null;
        string id = Guid.NewGuid().ToString(), key = codex ? "eventId" : "eventID";
        var envelope = new Dictionary<string, object> {{"authenticationToken",Str(route,"authenticationToken")},{key,id},{"payload",payload}};
        if (codex) envelope["installationId"] = Str(route,"installationId");
        else { envelope["kind"] = kind; envelope["awaitDecision"] = decision; }
        byte[] data = Encoding.UTF8.GetBytes(Encode(envelope) + "\n"); if(data.Length > WireLimit) return null;
        int timeout = codex ? 700 : Str(route,"provider") == "kimi" ? 750 : 1500;
        var watch = Stopwatch.StartNew();
        using(var client = new TcpClient()) {
            var pending = client.ConnectAsync("127.0.0.1", Number(route,"port",0)); if(!pending.Wait(timeout)) return null;
            using(var stream = client.GetStream()) {
                stream.WriteTimeout = timeout; stream.Write(data,0,data.Length);
                int left = timeout - (int)watch.ElapsedMilliseconds; if(left <= 0) return null;
                var ack = Decode(Line(stream, codex ? 4096 : WireLimit, left));
                if(Str(ack,key) != id || !Is(ack,"accepted",true) || !decision || !Is(ack,"pending",true)) return null;
                var reply = Decode(Line(stream,WireLimit,Math.Min(3600000,Math.Max(50,Number(route,"decisionTimeoutMs",3540000)))));
                return Str(reply,key) == id ? Obj(Get(reply,"decision")) : null;
            }
        }
    }
    static string Decision(Dictionary<string, object> d) {
        string behavior = Str(d,"behavior"); if(behavior != "allow" && behavior != "deny") return "";
        var result = new Dictionary<string, object> {{"behavior",behavior}};
        if(behavior == "allow") {
            if(Obj(Get(d,"updatedInput")) != null) result["updatedInput"] = d["updatedInput"];
            if(Get(d,"updatedPermissions") is object[]) result["updatedPermissions"] = d["updatedPermissions"];
        } else { if(Str(d,"message") != null) result["message"] = Clip(Str(d,"message"),4096); if(Is(d,"interrupt",true)) result["interrupt"] = true; }
        string text = Encode(new { hookSpecificOutput = new {hookEventName = "PermissionRequest", decision = result} });
        return Encoding.UTF8.GetByteCount(text) <= WireLimit ? text : "";
    }
    static string Quote(string s) { return "\"" + Regex.Replace(s, "(\\\\*)\"", "$1$1\\\"").TrimEnd('\\') + new string('\\', s.Length - s.TrimEnd('\\').Length) + new string('\\', s.Length - s.TrimEnd('\\').Length) + "\""; }
    static string Forward(Dictionary<string, object> route, byte[] input) {
        var original = Obj(Get(route,"originalStatusLine")); string command = Str(original,"command"); if(String.IsNullOrWhiteSpace(command) || command.Length > 16384) return null;
        string executable, arguments; var args = Get(original,"args") as object[];
        if(args != null && args.Length <= 256) {
            var quoted = new List<string>(); foreach(var a in args) { var s = a as string; if(s == null || s.Length > 16384) return null; quoted.Add(Quote(s)); }
            executable = command; arguments = String.Join(" ",quoted);
        } else {
            string bash = null;
            if(Str(original,"shell") != "powershell") foreach(var candidate in new[] {Environment.GetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"Git","bin","bash.exe"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),"Git","bin","bash.exe")}) if(!String.IsNullOrEmpty(candidate) && File.Exists(candidate)) { bash = candidate; break; }
            if(bash != null || Str(original,"shell") == "bash") { executable = bash ?? "bash.exe"; arguments = "-c " + Quote(command); }
            else { executable = "powershell.exe"; arguments = "-NoLogo -NoProfile -NonInteractive -EncodedCommand " + Convert.ToBase64String(Encoding.Unicode.GetBytes(command)); }
        }
        using(var child = new Process()) {
            child.StartInfo = new ProcessStartInfo(executable,arguments) { UseShellExecute=false, CreateNoWindow=true, RedirectStandardInput=true, RedirectStandardOutput=true, RedirectStandardError=true, StandardOutputEncoding=Encoding.UTF8 };
            child.Start(); child.ErrorDataReceived += (s,e) => {}; child.BeginErrorReadLine();
            var write = Task.Run(() => { try { child.StandardInput.BaseStream.Write(input,0,input.Length); child.StandardInput.Close(); } catch {} });
            var read = Task.Run(() => { var text = new StringBuilder(); var buffer = new char[4096]; int n; while((n=child.StandardOutput.Read(buffer,0,buffer.Length))>0) { if(text.Length+n>262144) throw new IOException(); text.Append(buffer,0,n); } return text.ToString(); });
            try { if(!child.WaitForExit(5000) || !read.Wait(100) || !write.Wait(100)) return null; return child.ExitCode == 0 ? read.Result : null; }
            finally { if(!child.HasExited) child.Kill(); }
        }
    }
    static string Compact(Dictionary<string, object> input) {
        var parts = new List<string>(); string model = Str(Obj(Get(input,"model")),"display_name"); if(model != null) parts.Add(Clip(model,256));
        var rates = Obj(Get(input,"rate_limits")); foreach(var key in new[]{"five_hour","seven_day"}) { object n = Get(Obj(Get(rates,key)),"used_percentage"); if(n is int || n is double || n is decimal) parts.Add((key == "five_hour" ? "5h " : "7d ") + Math.Round(Convert.ToDouble(n)).ToString(System.Globalization.CultureInfo.InvariantCulture) + "%"); }
        return String.Join(" · ",parts);
    }
    static void Hook(string[] args, bool codex) {
        var route = Route(Arg(args,"--configuration"),codex); if(codex && !Is(route,"enabled",true)) return;
        bool status = !codex && Arg(args,"--mode") == "statusline"; byte[] bytes = Input(codex ? WireLimit : status ? 2097152 : 8388608,codex ? 800 : 5000);
        var input = Decode(Encoding.UTF8.GetString(bytes)); if(input == null) return;
        string provider = Str(route,"provider");
        if(status) {
            if(provider != "claude") return;
            var payload = new Dictionary<string, object> {{"capturedAt", (DateTime.UtcNow-new DateTime(1970,1,1)).TotalSeconds}};
            foreach(var k in new[]{"session_id","version","rate_limits","cost","model","context_window","exceeds_200k_tokens"}) if(input.ContainsKey(k) && Encoding.UTF8.GetByteCount(Encode(input[k]))<=16384) payload[k]=input[k];
            try { Send(route,payload,false,"statusLine",false); } catch {}
            string text = null; try { text=Forward(route,bytes); } catch {} Console.Write(text ?? Compact(input)); return;
        }
        var safe = Payload(input,provider); if(safe == null) return;
        bool decision = !codex && provider=="claude" && !Is(route,"interactiveApprovals",false) && Str(safe,"hook_event_name")=="PermissionRequest";
        var result = Send(route,safe,codex,"hook",decision); if(decision) Console.Write(Decision(result));
    }
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window,out Rect rect);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    static void Foreground() {
        SetThreadDpiAwarenessContext(new IntPtr(-4));
        while(true) { var window=GetForegroundWindow(); Rect rect; uint pid; GetWindowThreadProcessId(window,out pid); if(GetWindowRect(window,out rect)) Console.WriteLine(Encode(new {x=rect.Left,y=rect.Top,width=rect.Right-rect.Left,height=rect.Bottom-rect.Top,pid=pid})); Thread.Sleep(1500); }
    }
#if !NET
    static int Main(string[] args) { return Run(args); }
#endif
    public static int Run(string[] args) {
        Console.OutputEncoding = new UTF8Encoding(false);
        if(Array.IndexOf(args,"--helper-smoke-test")>=0) {
            try { var p=Payload(Decode("{\"hook_event_name\":\"Stop\",\"session_id\":\"fixture\",\"prompt\":\"secret\"}"),"codex"); if(p.Count!=2 || Encode(p).Contains("secret") || Decision(null)!="" || Clip("你好",4)!="你") return 1; Console.WriteLine(Encode(new {ok=true,runtime=Environment.Version.ToString()})); return 0; } catch { return 1; }
        }
        try { if(Array.IndexOf(args,"--foreground-monitor")>=0) Foreground(); else Hook(args,Array.IndexOf(args,"--quotaview-codex-hook")>=0); } catch { /* Preserve agent defaults on every transport/configuration failure. */ }
        return 0;
    }
}
