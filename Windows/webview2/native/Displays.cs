using System.Runtime.InteropServices;
using System.Text.Json.Nodes;

namespace QuotaView;

internal static class Displays
{
    internal record Box(int x, int y, int width, int height);
    internal record Display(int id, string label, bool primary, double scaleFactor, Box bounds, Box workArea);
    static double Scale(Screen s)
    {
        var p = new Point(s.Bounds.Left + 1, s.Bounds.Top + 1);
        var monitor = MonitorFromPoint(p, 2);
        return GetDpiForMonitor(monitor, 0, out uint x, out _) == 0 ? x / 96d : 1d;
    }
    static Box Dip(Rectangle r, double scale) => new((int)Math.Round(r.X / scale), (int)Math.Round(r.Y / scale), (int)Math.Round(r.Width / scale), (int)Math.Round(r.Height / scale));
    internal static Display[] All() => Screen.AllScreens.Select((s, i) => new Display(i + 1, s.DeviceName, s.Primary, Scale(s), Dip(s.Bounds, Scale(s)), Dip(s.WorkingArea, Scale(s)))).ToArray();
    static double Num(JsonNode n, string key, double fallback = 0) => n[key]?.GetValue<double>() ?? fallback;
    static double Distance(Display d, double x, double y)
    {
        var b = d.bounds;
        double dx = Math.Max(Math.Max(b.x - x, 0), x - b.x - b.width), dy = Math.Max(Math.Max(b.y - y, 0), y - b.y - b.height);
        return dx * dx + dy * dy;
    }
    internal static Display Nearest(JsonNode p) => All().OrderBy(d => Distance(d, Num(p, "x"), Num(p, "y"))).First();
    internal static Display Matching(JsonNode r) => All().OrderByDescending(d => { var b = d.bounds; return Math.Max(0, Math.Min(b.x + b.width, Num(r, "x") + Num(r, "width")) - Math.Max(b.x, Num(r, "x"))) * Math.Max(0, Math.Min(b.y + b.height, Num(r, "y") + Num(r, "height")) - Math.Max(b.y, Num(r, "y"))); }).First();
    internal static object Cursor()
    {
        var p = System.Windows.Forms.Cursor.Position;
        double s = Scale(Screen.FromPoint(p));
        return new
        {
            x = (int)Math.Round(p.X / s),
            y = (int)Math.Round(p.Y / s)
        };
    }
    internal static Box ToDip(JsonNode r)
    {
        var p = new Rectangle((int)Num(r, "x"), (int)Num(r, "y"), (int)Num(r, "width"), (int)Num(r, "height"));
        return Dip(p, Scale(Screen.FromRectangle(p)));
    }
    internal static Rectangle Physical(JsonNode r)
    {
        var d = Matching(r);
        double s = d.scaleFactor;
        var physical = Screen.AllScreens[d.id - 1].Bounds;
        return new Rectangle(physical.X + (int)Math.Round((Num(r, "x") - d.bounds.x) * s), physical.Y + (int)Math.Round((Num(r, "y") - d.bounds.y) * s), (int)Math.Round(Num(r, "width") * s), (int)Math.Round(Num(r, "height") * s));
    }
    [DllImport("user32.dll")] static extern nint MonitorFromPoint(Point p, uint flags);
    [DllImport("shcore.dll")] static extern int GetDpiForMonitor(nint monitor, int type, out uint x, out uint y);
}
