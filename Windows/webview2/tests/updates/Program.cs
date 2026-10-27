using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Xml.Linq;
using QuotaView;

if (args.Length == 3 && args[0] == "--verify-package")
{
    var candidate = WindowsUpdatePolicy.ReadFeed(File.ReadAllText(args[1]), "0.0.0-win.0", WindowsUpdatePolicy.PublicKey) ?? throw new Exception("No signed Windows release");
    WindowsUpdatePolicy.VerifyPackage(args[2], candidate);
    var destination = Path.Combine(Path.GetTempPath(), "QuotaView-package-test-" + Guid.NewGuid().ToString("N"));
    try { Console.WriteLine($"Verified signed package: {WindowsUpdateInstaller.Extract(args[2], destination, candidate.Version).Count} files, {candidate.Version}"); }
    finally { if (Directory.Exists(destination)) Directory.Delete(destination, true); }
    return;
}

int passed = 0;
void Check(bool ok, string name) { if (!ok) throw new Exception(name); passed++; Console.WriteLine("PASS " + name); }
void Reject(Action run, string name) { bool failed = false; try { run(); } catch { failed = true; } Check(failed, name); }
using var key = RSA.Create(2048);
var publicKey = key.ExportSubjectPublicKeyInfoPem();
var root = Path.Combine(Path.GetTempPath(), "QuotaView-update-test-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
try
{
    string version = "0.8.3-win.11";
    WindowsRelease Sign(WindowsRelease r) => r with { Signature = Convert.ToBase64String(key.SignData(r.SignedBytes, HashAlgorithmName.SHA256, RSASignaturePadding.Pss)) };
    var release = Sign(new(version, $"https://github.com/Duoasa/QuotaView/releases/download/v{version}/QuotaView-Windows-{version}-x64.zip", 10, new string('a', 64), ""));
    var ns = WindowsUpdatePolicy.Ns;
    string Feed(WindowsRelease r, string arch = "x64") => new XDocument(new XElement("rss", new XElement("channel", new XElement("item", new XElement("enclosure",
        new XAttribute("url", r.Url), new XAttribute("length", r.Length), new XAttribute(ns + "version", r.Version),
        new XAttribute(ns + "os", "windows"), new XAttribute(ns + "arch", arch), new XAttribute(ns + "kind", "standalone"),
        new XAttribute(ns + "sha256", r.Sha256), new XAttribute(ns + "signature", r.Signature)))))).ToString();
    Check(WindowsUpdatePolicy.ReadFeed(Feed(release), "0.8.3-win.10", publicKey) == release, "signed newer Windows release selected");
    Check(WindowsUpdatePolicy.ReadFeed(Feed(release), version, publicKey) == null, "no same-version reinstall");
    Check(WindowsUpdatePolicy.ReadFeed(Feed(release), "0.9.0-win.1", publicKey) == null, "no downgrade");
    Check(WindowsUpdatePolicy.ReadFeed(Feed(release, "arm64"), "0.8.3-win.10", publicKey) == null, "other architecture ignored");
    Check(WindowsUpdatePolicy.ReadFeed("<rss><channel><item><enclosure url='mac.zip'/></item></channel></rss>", "0.8.3-win.10", publicKey) == null, "macOS feed entry ignored");
    Check(WindowsUpdatePolicy.Compare("v0.8.3-win.1.effects.2", "0.8.3-win.1") > 0, "legacy Windows version supported");
    Reject(() => WindowsUpdatePolicy.ReadFeed(Feed(release with { Length = 11 }), "0.8.3-win.10", publicKey), "tampered metadata rejected");
    Reject(() => WindowsUpdatePolicy.ReadFeed(Feed(release with { Signature = "bad" }), "0.8.3-win.10", publicKey), "malformed signature rejected");
    Reject(() => WindowsUpdatePolicy.ReadFeed(Feed(Sign(release with { Url = "https://example.com/app.zip" })), "0.8.3-win.10", publicKey), "foreign package origin rejected even if signed");
    Reject(() => WindowsUpdatePolicy.ReadFeed("<!DOCTYPE rss [<!ENTITY x SYSTEM 'file:///test'>]><rss><channel>&x;</channel></rss>", "0.8.3-win.10", publicKey), "XML external entities rejected");
    Reject(() => WindowsUpdatePolicy.Compare("0.8.3-build.9", version), "macOS version not comparable");

    string package = Path.Combine(root, "fixture.zip");
    void Zip(string output, params (string Name, string Text)[] entries)
    {
        using var archive = ZipFile.Open(output, ZipArchiveMode.Create);
        foreach (var e in entries) { using var writer = new StreamWriter(archive.CreateEntry(e.Name).Open()); writer.Write(e.Text); }
    }
    Zip(package, ("QuotaView.Native.exe", "exe"), ("QuotaView.Native.dll", "dll"), ("QuotaView.Native.runtimeconfig.json", "{}"),
        ("coreclr.dll", "runtime"), ("hostfxr.dll", "runtime"), ("app/package.json", "{\"version\":\"" + version + "\"}"),
        ("app/backend.js", "app"), ("app/dist/renderer/index.html", "html"));
    var packageRelease = Sign(release with { Length = new FileInfo(package).Length, Sha256 = Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(package))) });
    WindowsUpdatePolicy.VerifyPackage(package, packageRelease); passed++; Console.WriteLine("PASS package hash and size");
    Reject(() => WindowsUpdatePolicy.VerifyPackage(package, packageRelease with { Sha256 = new string('b', 64) }), "corrupted package rejected");
    var stage = Path.Combine(root, "stage");
    var files = WindowsUpdateInstaller.Extract(package, stage, version);
    Check(files.Count == 8, "complete standalone package extracted");
    Reject(() => WindowsUpdateInstaller.Extract(package, Path.Combine(root, "wrong-version"), "0.8.3-win.10"), "mislabeled package version rejected");
    foreach (string name in new[] { "../escape", "/absolute", "app/file:stream", "app/CON.txt", "app/file. ", "app\\file", "app//file" })
        Reject(() => WindowsUpdateInstaller.Child(stage, name), "unsafe archive path: " + name);
    var duplicate = Path.Combine(root, "duplicate.zip"); Zip(duplicate, ("app/A", "1"), ("app/a", "2"));
    Reject(() => WindowsUpdateInstaller.Extract(duplicate, Path.Combine(root, "duplicate"), version), "case-insensitive duplicate rejected");
    var escape = Path.Combine(root, "escape.zip"); Zip(escape, ("../outside", "1"));
    Reject(() => WindowsUpdateInstaller.Extract(escape, Path.Combine(root, "escape"), version), "zip traversal rejected");
    var target = Path.Combine(root, "target"); Directory.CreateDirectory(target);
    File.WriteAllText(Path.Combine(target, "QuotaView.Native.exe"), "old");
    File.WriteAllText(Path.Combine(target, "user-note.txt"), "keep");
    WindowsUpdateInstaller.Apply(stage, target, Path.Combine(root, "backup"), files);
    Check(File.ReadAllText(Path.Combine(target, "QuotaView.Native.exe")) == "exe" && File.ReadAllText(Path.Combine(target, "user-note.txt")) == "keep", "install preserves unrelated files");
    Check(File.ReadAllText(Path.Combine(root, "backup", "QuotaView.Native.exe")) == "old", "original version backed up");
    File.WriteAllText(Path.Combine(target, "QuotaView.Native.exe"), "before-failure");
    File.Delete(Path.Combine(target, "app/backend.js"));
    Reject(() => WindowsUpdateInstaller.Apply(stage, target, Path.Combine(root, "rollback"), files, () => throw new IOException("test failure")), "failed install reports failure");
    Check(File.ReadAllText(Path.Combine(target, "QuotaView.Native.exe")) == "before-failure" && !File.Exists(Path.Combine(target, "app/backend.js")), "rollback restores existing and removes new files");
    // A locked destination exercises a real partial-write failure, not just an injected callback.
    using (var locked = new FileStream(Path.Combine(target, "QuotaView.Native.dll"), FileMode.Open, FileAccess.Read, FileShare.Read))
        Reject(() => WindowsUpdateInstaller.Apply(stage, target, Path.Combine(root, "locked-backup"), files), "locked file aborts installation");
    Check(File.ReadAllText(Path.Combine(target, "QuotaView.Native.exe")) == "before-failure", "partial install rolled back after locked file");
    Console.WriteLine($"Windows update checks: {passed} passed");
}
finally { Directory.Delete(root, true); }
