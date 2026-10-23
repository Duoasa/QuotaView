using System.Diagnostics;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace QuotaView;

public sealed partial class NativeBridge
{
    // Verify the server on the very handle used for traffic. Never discover a
    // PID on one pipe and send decisions over a second, unverified connection.
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetNamedPipeServerProcessId(SafePipeHandle pipe, out uint pid);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern int GetPackageFamilyName(IntPtr process, ref uint length, StringBuilder name);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder name, ref uint length);

    static void VerifyCodexPeer(NamedPipeClientStream pipe)
    {
        if (!GetNamedPipeServerProcessId(pipe.SafePipeHandle, out var pid))
            throw new IOException("codex_desktop_peer_unavailable");
        var process = OpenProcess(0x1000, false, pid);
        if (process == IntPtr.Zero) throw new IOException("codex_desktop_peer_unavailable");
        IntPtr token = IntPtr.Zero;
        try
        {
            if (!OpenProcessToken(process, 8, out token)) throw new IOException("codex_desktop_peer_unavailable");
            using var peer = new WindowsIdentity(token);
            using var current = WindowsIdentity.GetCurrent();
            if (peer.User != current.User) throw new IOException("codex_desktop_peer_mismatch");
            uint size = 512;
            var family = new StringBuilder((int)size);
            if (GetPackageFamilyName(process, ref size, family) != 0 || family.ToString() != "OpenAI.Codex_2p2nqsd0c76g0")
                throw new IOException("codex_desktop_package_unverified");
            size = 32768;
            var image = new StringBuilder((int)size);
            if (!QueryFullProcessImageName(process, 0, image, ref size)) throw new IOException("codex_desktop_peer_unavailable");
            var name = Path.GetFileName(image.ToString());
            if (!name.Equals("ChatGPT.exe", StringComparison.OrdinalIgnoreCase) && !name.Equals("Codex.exe", StringComparison.OrdinalIgnoreCase))
                throw new IOException("codex_desktop_peer_mismatch");
        }
        finally { if (token != IntPtr.Zero) CloseHandle(token); CloseHandle(process); }
    }

    void ConnectCodexDesktop(string id)
    {
        _ = Task.Run(async () =>
        {
            var pipe = new NamedPipeClientStream(".", "codex-ipc", PipeDirection.InOut, PipeOptions.Asynchronous);
            try
            {
                await pipe.ConnectAsync(2000);
                VerifyCodexPeer(pipe);
                var connection = new Connection(pipe);
                sockets[id] = connection;
                Emit(new { id, type = "connect" });
                StartRead(id, connection);
            }
            catch (Exception e)
            {
                pipe.Dispose();
                Emit(new { id, type = "error", error = e.Message });
                Emit(new { id, type = "close" });
            }
        });
    }
}
