using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;

namespace QuotaView;

internal sealed record WindowsRelease(string Version, string Url, long Length, string Sha256, string Signature)
{
    internal string ReleasePage => $"https://github.com/Duoasa/QuotaView/releases/tag/v{Version}";
    // A fixed, locale-independent signature format. No user-controlled newline is accepted by Validate.
    internal byte[] SignedBytes => Encoding.UTF8.GetBytes($"QuotaView-Windows-v1\n{Version}\nwindows\nx64\nstandalone\n{Url}\n{Length.ToString(CultureInfo.InvariantCulture)}\n{Sha256}\n");
}

internal static class WindowsUpdatePolicy
{
    internal const string FeedUrl = "https://raw.githubusercontent.com/Duoasa/QuotaView/main/Windows/updates/appcast.xml";
    internal const long MaximumPackage = 300 * 1024 * 1024;
    internal static readonly XNamespace Ns = "https://quotaview.app/windows-update/v1";
    static readonly Regex VersionPattern = new(@"^v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})-win\.(\d{1,6})(?:\.(effects|build)\.(\d{1,6}))?$", RegexOptions.CultureInvariant);

    internal static int Compare(string left, string right)
    {
        static int[] Parts(string v)
        {
            var m = VersionPattern.Match(v);
            if (!m.Success) throw new InvalidDataException("Invalid Windows version: " + v);
            return [.. Enumerable.Range(1, 4).Select(i => int.Parse(m.Groups[i].Value, CultureInfo.InvariantCulture)),
                m.Groups[5].Value == "build" ? 2 : m.Groups[5].Value == "effects" ? 1 : 0,
                m.Groups[6].Success ? int.Parse(m.Groups[6].Value, CultureInfo.InvariantCulture) : 0];
        }
        var a = Parts(left); var b = Parts(right);
        for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return a[i].CompareTo(b[i]);
        return 0;
    }

    internal static string PublicKey
    {
        get
        {
            using var stream = typeof(WindowsUpdatePolicy).Assembly.GetManifestResourceStream("QuotaView.WindowsUpdatePublicKey")!;
            using var reader = new StreamReader(stream);
            return reader.ReadToEnd();
        }
    }

    internal static void Validate(WindowsRelease release, string publicKey)
    {
        if (!Regex.IsMatch(release.Version, @"^\d{1,6}\.\d{1,6}\.\d{1,6}-win\.\d{1,6}$", RegexOptions.CultureInvariant))
            throw new InvalidDataException("Invalid Windows release identity");
        string expected = $"https://github.com/Duoasa/QuotaView/releases/download/v{release.Version}/QuotaView-Windows-{release.Version}-x64.zip";
        if (release.Url != expected || release.Length is <= 0 or > MaximumPackage || !Regex.IsMatch(release.Sha256, "^[a-f0-9]{64}$"))
            throw new InvalidDataException("Invalid Windows update package");
        using var rsa = RSA.Create();
        rsa.ImportFromPem(publicKey);
        if (!rsa.VerifyData(release.SignedBytes, Convert.FromBase64String(release.Signature), HashAlgorithmName.SHA256, RSASignaturePadding.Pss))
            throw new CryptographicException("Windows update signature is invalid");
    }

    internal static WindowsRelease? ReadFeed(string xml, string current, string publicKey)
    {
        using var input = new StringReader(xml);
        using var reader = XmlReader.Create(input, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = 1024 * 1024 });
        var doc = XDocument.Load(reader);
        var channel = doc.Root?.Name == "rss" ? doc.Root.Element("channel") : null;
        if (channel == null) throw new InvalidDataException("Invalid Windows appcast");
        WindowsRelease? newest = null;
        Compare(current, current);
        foreach (var item in channel.Elements("item"))
        {
            var e = item.Element("enclosure");
            // Sparkle/macOS, other architectures and installer kinds never enter this channel.
            if ((string?)e?.Attribute(Ns + "os") != "windows" || (string?)e?.Attribute(Ns + "arch") != "x64" || (string?)e?.Attribute(Ns + "kind") != "standalone") continue;
            var r = new WindowsRelease((string?)e!.Attribute(Ns + "version") ?? "", (string?)e.Attribute("url") ?? "",
                long.Parse((string?)e.Attribute("length") ?? "0", CultureInfo.InvariantCulture),
                (string?)e.Attribute(Ns + "sha256") ?? "", (string?)e.Attribute(Ns + "signature") ?? "");
            Validate(r, publicKey);
            if (Compare(r.Version, current) > 0 && (newest == null || Compare(r.Version, newest.Version) > 0)) newest = r;
        }
        return newest;
    }

    internal static void VerifyPackage(string path, WindowsRelease release)
    {
        using var file = File.OpenRead(path);
        if (file.Length != release.Length || Convert.ToHexStringLower(SHA256.HashData(file)) != release.Sha256)
            throw new InvalidDataException("Windows update package checksum does not match");
    }
}
