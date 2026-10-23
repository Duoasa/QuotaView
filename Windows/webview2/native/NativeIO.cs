using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Net.Http;
using System.Text.Json.Nodes;

namespace QuotaView;

public sealed partial class NativeBridge
{
    readonly ConcurrentDictionary<string, Process> processes = new();
    JsonNode? ProcessOp(string op, JsonArray a)
    {
        var id = A(a, 0);
        if (op == "check")
        {
            try
            {
                using var p = Process.GetProcessById(I(a, 0));
                if (p.HasExited)
                    throw new ArgumentException();
                return null;
            }
            catch { throw new FileNotFoundException("ESRCH"); }
        }
        if (op == "spawn")
        {
            var exe = A(a, 1);
            if (!Path.IsPathFullyQualified(exe) && exe != "cmd.exe" && exe != "powershell.exe")
                throw new ArgumentException("Process path must be absolute");
            var opts = a[3];
            var psi = new ProcessStartInfo(exe) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = S(opts, "cwd", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)) };
            foreach (var item in a[2]!.AsArray())
                psi.ArgumentList.Add(item!.ToString());
            if (opts?["env"] is JsonObject env)
            {
                psi.Environment.Clear();
                foreach (var pair in env)
                if (pair.Value != null)
                    psi.Environment[pair.Key] = pair.Value.ToString();
            }
            var child = new Process { StartInfo = psi };
            child.Start();
            processes[id] = child;
            _ = Task.Run(async () => { var stdout = PipeRead(id, "stdout", child.StandardOutput.BaseStream); var stderr = PipeRead(id, "stderr", child.StandardError.BaseStream); await child.WaitForExitAsync(); await Task.WhenAll(stdout, stderr); Emit(new { id, type = "close", value = child.ExitCode }); processes.TryRemove(id, out _); child.Dispose(); });
            return JsonValue.Create(child.Id);
        }
        if (!processes.TryGetValue(id, out var process))
            return null;
        if (op == "write")
        {
            process.StandardInput.BaseStream.Write(Convert.FromBase64String(A(a, 1)));
            process.StandardInput.BaseStream.Flush();
        }
        else if (op == "end")
            process.StandardInput.Close();
        else if (op == "kill")
        {
            try
            {
                process.Kill(true);
            }
            catch { }
        }
        else
            throw new NotSupportedException(op);
        return null;
    }
    async Task PipeRead(string id, string type, Stream stream)
    {
        try
        {
            var b = new byte[65536];
            int n;
            while ((n = await stream.ReadAsync(b)) > 0)
                Emit(new
                {
                    id,
                    type,
                    data = Convert.ToBase64String(b, 0, n)
                });
        }
        catch (Exception e) { Emit(new { id, type = "error", error = e.Message }); }
    }
    sealed class Connection : IDisposable
    {
        public TcpClient? Client; public Stream Stream; public Task Writes = Task.CompletedTask; public readonly object Gate = new(); public bool Reading, RemoteEnded, LocalEnded, AllowHalfOpen; public long QueuedBytes; public Connection(TcpClient c)
        {
            Client = c;
            Stream = c.GetStream();
        }
        public Connection(Stream stream) { Stream = stream; }
        public void Dispose()
        {
            try
            {
                Client?.Dispose();
                Stream.Dispose();
            }
            catch { }
        }
    }
    readonly ConcurrentDictionary<string, Connection> sockets = new();
    readonly ConcurrentDictionary<string, TcpListener> servers = new();
    JsonNode? NetworkOp(string op, JsonArray a)
    {
        var id = A(a, 0);
        if (op == "server.listen")
        {
            if (A(a, 2) != "127.0.0.1")
                throw new ArgumentException("Only loopback servers are permitted");
            var listener = new TcpListener(IPAddress.Loopback, I(a, 1));
            listener.Start(64);
            servers[id] = listener;
            _ = Task.Run(async () => { try { while (true) { var client = await listener.AcceptTcpClientAsync(); if (sockets.Count >= 128) { client.Dispose(); continue; } var sid = "accepted-" + Guid.NewGuid().ToString("N"); sockets[sid] = new Connection(client) { AllowHalfOpen = true }; Emit(new { id, type = "connection", socket = sid, remoteAddress = (client.Client.RemoteEndPoint as IPEndPoint)?.Address.ToString() }); } } catch (ObjectDisposedException) { } catch (SocketException) { } catch (Exception e) { Emit(new { id, type = "error", error = e.Message }); } });
            return JsonValue.Create(((IPEndPoint)listener.LocalEndpoint).Port);
        }
        if (op == "server.close")
        {
            if (servers.TryRemove(id, out var listener))
                listener.Stop();
            return null;
        }
        if (op == "socket.codexDesktop") { ConnectCodexDesktop(id); return null; }
        if (op == "socket.connect")
        {
            var host = A(a, 1);
            var port = I(a, 2);
            var secure = B(a, 3);
            _ = Task.Run(async () => { Connection? c = null; TcpClient? tcp = null; try { tcp = new TcpClient(); await tcp.ConnectAsync(host, port).WaitAsync(TimeSpan.FromSeconds(10)); c = new Connection(tcp); if (secure) { var ssl = new SslStream(c.Stream, false); await ssl.AuthenticateAsClientAsync(host); c.Stream = ssl; } sockets[id] = c; Emit(new { id, type = secure ? "secureConnect" : "connect" }); StartRead(id, c); } catch (Exception e) { c?.Dispose(); tcp?.Dispose(); Emit(new { id, type = "error", error = e.Message }); Emit(new { id, type = "close" }); } });
            return null;
        }
        if (!sockets.TryGetValue(id, out var conn))
            return null;
        switch (op)
        {
            case "socket.resume":
                StartRead(id, conn);
                break;
            case "socket.write":
                QueueWrite(id, conn, Convert.FromBase64String(A(a, 1)));
                break;
            case "socket.end":
                QueueWrite(id, conn, null);
                break;
            case "socket.close":
                CloseSocket(id);
                break;
            default:
                throw new NotSupportedException(op);
        }
        return null;
    }
    void QueueWrite(string id, Connection c, byte[]? data)
    {
        lock (c.Gate)
        {
            c.QueuedBytes += data?.Length ?? 0;
            if (c.QueuedBytes > 4 * 1024 * 1024)
            {
                CloseSocket(id);
                return;
            }
            c.Writes = c.Writes.ContinueWith(async _ => { try { if (data != null) { await c.Stream.WriteAsync(data); Interlocked.Add(ref c.QueuedBytes, -data.Length); } else { c.LocalEnded = true; if (c.Client != null) c.Client.Client.Shutdown(SocketShutdown.Send); if (c.Client == null || c.RemoteEnded) CloseSocket(id); } } catch (Exception e) { Emit(new { id, type = "error", error = e.Message }); CloseSocket(id); } }, TaskScheduler.Default).Unwrap();
        }
    }
    void StartRead(string id, Connection c)
    {
        if (c.Reading)
            return;
        c.Reading = true;
        _ = Task.Run(async () => { try { var b = new byte[65536]; int n; while ((n = await c.Stream.ReadAsync(b)) > 0) Emit(new { id, type = "data", data = Convert.ToBase64String(b, 0, n) }); c.RemoteEnded = true; Emit(new { id, type = "end" }); if (c.LocalEnded) CloseSocket(id); else if (!c.AllowHalfOpen) QueueWrite(id, c, null); } catch (Exception e) { Emit(new { id, type = "error", error = e.Message }); CloseSocket(id); } });
    }
    void CloseSocket(string id)
    {
        if (sockets.TryRemove(id, out var c))
        {
            c.Dispose();
            Emit(new
            {
                id,
                type = "close"
            });
        }
    }
    internal JsonObject proxySettings = new() { ["mode"] = "system" };
    JsonNode? ResolveProxy(string target)
    {
        if (S(proxySettings, "mode") == "direct")
            return JsonValue.Create("DIRECT");
        if (S(proxySettings, "mode") == "fixed_servers")
            return JsonValue.Create("PROXY " + new Uri(S(proxySettings, "proxyRules")).Authority);
        var uri = new Uri(target);
        var proxy = HttpClient.DefaultProxy;
        var resolved = proxy.GetProxy(uri);
        if (proxy.IsBypassed(uri) || resolved == null || resolved == uri)
            return JsonValue.Create("DIRECT");
        var kind = resolved.Scheme switch
        {
            "https" => "HTTPS",
            "socks5" => "SOCKS5",
            "socks4" => "SOCKS4",
            _ => "PROXY"
        };
        return JsonValue.Create(kind + " " + resolved.Authority);
    }
    async Task<JsonNode?> Fetch(JsonArray args)
    {
        var uri = new Uri(A(args, 0));
        if (uri.Scheme != "https")
            throw new ArgumentException("HTTPS required");
        using var handler = new HttpClientHandler();
        var mode = S(proxySettings, "mode");
        if (mode == "direct")
            handler.UseProxy = false;
        else if (mode == "fixed_servers")
            handler.Proxy = new WebProxy(S(proxySettings, "proxyRules"));
        using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(15) };
        using var request = new HttpRequestMessage(HttpMethod.Get, uri);
        if (args.ElementAtOrDefault(1)?["headers"] is JsonObject headers)
        foreach (var pair in headers)
            request.Headers.TryAddWithoutValidation(pair.Key, pair.Value?.ToString());
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
        var body = await response.Content.ReadAsStringAsync();
        if (body.Length > 4 * 1024 * 1024)
            throw new IOException("Response exceeds limit");
        return Node(new
        {
            status = (int)response.StatusCode,
            body
        });
    }
}
