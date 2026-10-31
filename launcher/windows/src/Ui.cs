using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;

namespace Aetherion.Launcher
{
    /// <summary>The game's look (game/src/ui/ui_theme.gd): colours, its Barlow fonts, and drawing helpers.</summary>
    static class Ui
    {
        public static readonly Color Bg = Color.FromArgb(10, 12, 15);
        public static readonly Color Panel = Color.FromArgb(205, 12, 15, 19);
        public static readonly Color Line = Color.FromArgb(28, 255, 255, 255);
        public static readonly Color Text = Color.FromArgb(235, 237, 230);
        public static readonly Color Dim = Color.FromArgb(153, 163, 163);
        public static readonly Color Accent = Color.FromArgb(242, 163, 59);
        public static readonly Color AccentHot = Color.FromArgb(255, 189, 102);
        public static readonly Color Accent2 = Color.FromArgb(77, 199, 184);
        public static readonly Color Danger = Color.FromArgb(235, 92, 82);
        public static readonly Color Good = Color.FromArgb(122, 214, 133);

        static PrivateFontCollection _cond, _reg, _semi;
        static readonly System.Collections.Generic.List<IntPtr> _pinned = new System.Collections.Generic.List<IntPtr>();

        static PrivateFontCollection Load(string res)
        {
            var pfc = new PrivateFontCollection();
            using (var s = typeof(Ui).Assembly.GetManifestResourceStream(res))
            {
                var data = new byte[s.Length];
                s.Read(data, 0, data.Length);
                var mem = Marshal.AllocCoTaskMem(data.Length);  // must outlive the collection
                Marshal.Copy(data, 0, mem, data.Length);
                pfc.AddMemoryFont(mem, data.Length);
                _pinned.Add(mem);
            }
            return pfc;
        }

        public static Font Condensed(float px) => new Font((_cond ?? (_cond = Load("BarlowCondensed-SemiBold.ttf"))).Families[0], px, FontStyle.Regular, GraphicsUnit.Pixel);
        public static Font Regular(float px) => new Font((_reg ?? (_reg = Load("Barlow-Regular.ttf"))).Families[0], px, FontStyle.Regular, GraphicsUnit.Pixel);
        public static Font Semi(float px) => new Font((_semi ?? (_semi = Load("Barlow-SemiBold.ttf"))).Families[0], px, FontStyle.Regular, GraphicsUnit.Pixel);

        public static Image Resource(string name)
        {
            using (var s = typeof(Ui).Assembly.GetManifestResourceStream(name))
            {
                var ms = new MemoryStream();
                s.CopyTo(ms);
                ms.Position = 0;
                return Image.FromStream(ms);
            }
        }

        public static readonly StringFormat Typo = MakeTypo();

        static StringFormat MakeTypo()
        {
            var f = (StringFormat)StringFormat.GenericTypographic.Clone();
            f.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces | StringFormatFlags.NoClip;
            return f;
        }

        public static float Measure(Graphics g, string s, Font f, float spacing = 0)
        {
            if (string.IsNullOrEmpty(s)) return 0;
            if (spacing == 0) return g.MeasureString(s, f, PointF.Empty, Typo).Width;
            float w = 0;
            foreach (var ch in s) w += g.MeasureString(ch.ToString(), f, PointF.Empty, Typo).Width + spacing;
            return w - spacing;
        }

        /// <summary>Draws text at (x, y); spacing adds letter spacing. Returns the width.</summary>
        public static float Draw(Graphics g, string s, Font f, Color c, float x, float y, float spacing = 0)
        {
            if (string.IsNullOrEmpty(s)) return 0;
            using (var b = new SolidBrush(c))
            {
                if (spacing == 0)
                {
                    g.DrawString(s, f, b, x, y, Typo);
                    return Measure(g, s, f);
                }
                float x0 = x;
                foreach (var ch in s)
                {
                    var t = ch.ToString();
                    g.DrawString(t, f, b, x, y, Typo);
                    x += g.MeasureString(t, f, PointF.Empty, Typo).Width + spacing;
                }
                return x - x0 - spacing;
            }
        }

        public static void DrawRight(Graphics g, string s, Font f, Color c, float right, float y, float spacing = 0) =>
            Draw(g, s, f, c, right - Measure(g, s, f, spacing), y, spacing);

        public static void Wrap(Graphics g, string s, Font f, Color c, RectangleF r)
        {
            using (var b = new SolidBrush(c))
            using (var fmt = new StringFormat(StringFormat.GenericTypographic) { Trimming = StringTrimming.EllipsisWord })
                g.DrawString(s, f, b, r, fmt);
        }

        public static float WrapHeight(Graphics g, string s, Font f, float width)
        {
            using (var fmt = new StringFormat(StringFormat.GenericTypographic))
                return g.MeasureString(s, f, new SizeF(width, 10000), fmt).Height;
        }

        public static string Ellipsize(Graphics g, string s, Font f, float width)
        {
            if (Measure(g, s, f) <= width) return s;
            // Keep the end of a path visible: "C:\…\Aetherion Project".
            for (int cut = 4; cut < s.Length; cut++)
            {
                var t = s.Substring(0, 3) + "…" + s.Substring(cut);
                if (Measure(g, t, f) <= width) return t;
            }
            return "…";
        }

        public static GraphicsPath Round(RectangleF r, float radius)
        {
            var p = new GraphicsPath();
            float d = radius * 2;
            if (radius <= 0) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        public static void Fill(Graphics g, RectangleF r, float radius, Color c)
        {
            using (var p = Round(r, radius))
            using (var b = new SolidBrush(c))
                g.FillPath(b, p);
        }

        public static void Stroke(Graphics g, RectangleF r, float radius, Color c, float w = 1)
        {
            using (var p = Round(r, radius))
            using (var pen = new Pen(c, w))
                g.DrawPath(pen, p);
        }
    }
}
