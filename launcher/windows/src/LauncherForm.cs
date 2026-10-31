using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace Aetherion.Launcher
{
    /// <summary>
    /// The launcher window: key art of Sitio Kalinaw, the title, what's new in the release, the official servers, and one
    /// big button that installs, updates or plays. Drawn by hand at 1180x680 logical pixels, scaled to the monitor's DPI.
    /// </summary>
    sealed class LauncherForm : Form
    {
        public const string WindowTitle = "Aetherion Project";
        const float W = 1180, H = 680, M = 64, BtnW = 280, BtnH = 80;

        enum Mode { Checking, Install, Update, Ready, Working, Error, Playing }

        readonly string _baseUrl;
        readonly Updater _u;
        Manifest _remote;
        Mode _mode = Mode.Checking;
        string _status = "Checking for updates…", _detail = "Connecting to the Aetherion servers";
        Color _statusColor = Ui.Text;
        UpdateProgress _p;
        CancellationTokenSource _cts;
        Process _game;
        bool _offline;
        // Official servers (stats API /status)
        List<Dictionary<string, object>> _servers;
        bool? _serversUp;
        int _onlineCount;

        float S = 1f;
        readonly Dictionary<string, RectangleF> _hit = new Dictionary<string, RectangleF>();
        string _hover, _pressed;
        Bitmap _bgCache;
        readonly Image _art;
        readonly Image _icon;
        readonly System.Windows.Forms.Timer _anim = new System.Windows.Forms.Timer { Interval = 50 };
        readonly System.Windows.Forms.Timer _poll = new System.Windows.Forms.Timer { Interval = 20000 };
        int _tick, _pollCount;
        readonly Font _fTitle = Ui.Condensed(104), _fSub = Ui.Condensed(38), _fBtn = Ui.Condensed(34), _fHead = Ui.Semi(13),
            _fBody = Ui.Regular(15.5f), _fBodyB = Ui.Semi(15.5f), _fStatus = Ui.Semi(21), _fSmall = Ui.Regular(13.5f), _fBy = Ui.Regular(21);

        public LauncherForm(string baseUrl)
        {
            _baseUrl = baseUrl;
            _u = new Updater(baseUrl, Program.InstallDir);
            Text = WindowTitle;
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Ui.Bg;
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            using (var s = typeof(Ui).Assembly.GetManifestResourceStream("app.ico")) Icon = new Icon(s);
            _art = Ui.Resource("background.jpg");
            _icon = Icon.ToBitmap();
            ApplyDpi(DeviceDpi);
            _anim.Tick += (s, e) => { _tick++; Invalidate(); };
            _poll.Tick += async (s, e) => await PollAsync();
            _u.Progress += p => { _p = p; };
        }

        protected override CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                cp.ClassStyle |= 0x20000;  // CS_DROPSHADOW
                return cp;
            }
        }

        void ApplyDpi(int dpi)
        {
            S = dpi / 96f;
            ClientSize = new Size((int)Math.Round(W * S), (int)Math.Round(H * S));
            _bgCache?.Dispose();
            _bgCache = null;
        }

        protected override void OnDpiChanged(DpiChangedEventArgs e)
        {
            base.OnDpiChanged(e);
            ApplyDpi(e.DeviceDpiNew);
            Invalidate();
        }

        protected override async void OnShown(EventArgs e)
        {
            base.OnShown(e);
            try
            {
                int round = 2;  // DWMWCP_ROUND: rounded corners on Windows 11
                Native.DwmSetWindowAttribute(Handle, 33, ref round, sizeof(int));
            }
            catch (Exception) { }
            _anim.Start();
            _poll.Start();
            _ = RefreshServersAsync();
            await CheckAsync();
        }

        // ------------------------------------------------------------------ state

        async Task CheckAsync(bool quiet = false)
        {
            if (!quiet) SetMode(Mode.Checking, "Checking for updates…", "Connecting to the Aetherion servers");
            try
            {
                var m = await _u.FetchAsync(CancellationToken.None);
                _remote = m;
                _offline = false;
                var next = await _u.FetchNewLauncherAsync(m, Program.SelfPath, CancellationToken.None);
                if (next != null)
                {
                    SetMode(Mode.Working, "Updating the launcher…", "Launcher " + m.Launcher.Version);
                    var self = Program.SelfPath;
                    File.Move(self, self + ".old");
                    File.Move(next, self);
                    Process.Start(new ProcessStartInfo(self, "--updated") { UseShellExecute = false });
                    Application.Exit();
                    return;
                }
                ShowLocalState();
            }
            catch (Exception ex)
            {
                _offline = true;
                var have = _u.InstalledVersion();
                if (have != "")
                    SetMode(Mode.Ready, "Ready to play", "Offline: the update server cannot be reached (" + Short(ex) + "). You can still play version " + have + ".");
                else if (!quiet)
                    SetMode(Mode.Error, "Can't reach the Aetherion servers", Short(ex) + " Check your internet connection, then try again.", Ui.Danger);
            }
        }

        void ShowLocalState()
        {
            var m = _remote;
            var have = _u.InstalledVersion(m);
            if (_game != null && !_game.HasExited)
            {
                SetMode(Mode.Playing, "Aetherion is running", have != m.Version ? "Update " + m.Version + " is ready: close the game to install it." : "Have a good match.");
                return;
            }
            if (have == "")
            {
                long dl = _u.PendingDownload(m, false);
                SetMode(Mode.Install, "Ready to install", string.Format("Version {0} · {1} download · {2} on disk", m.Version, Updater.Size(dl), Updater.Size(m.Size)));
            }
            else if (have != m.Version)
            {
                long dl = _u.PendingDownload(m, false);
                SetMode(Mode.Update, "Update available", string.Format("Version {0} → {1} · {2} to download", have, m.Version, Updater.Size(Math.Max(dl, 1))));
            }
            else SetMode(Mode.Ready, "Ready to play", "Version " + m.Version + " is installed and up to date.");
        }

        void SetMode(Mode m, string status, string detail, Color? color = null)
        {
            _mode = m;
            _status = status;
            _detail = detail;
            _statusColor = color ?? Ui.Text;
            Invalidate();
        }

        async Task RunUpdateAsync(bool verify)
        {
            if (_remote == null) { await CheckAsync(); if (_remote == null) return; }
            _cts = new CancellationTokenSource();
            _p = null;
            SetMode(Mode.Working, verify ? "Checking game files…" : (_u.InstalledVersion(_remote) == "" ? "Installing Aetherion…" : "Updating Aetherion…"), "Starting");
            try
            {
                await Task.Run(() => _u.ApplyAsync(_remote, verify, _cts.Token));
                Program.InstallDir = _u.InstallDir;
                Setup.EnsureShortcuts(Program.InstalledLauncher);
                ShowLocalState();
                if (verify) _detail = "All files checked: " + _detail;
                FlashIfInactive();
            }
            catch (OperationCanceledException)
            {
                SetMode(Mode.Error, "Paused", "The download stopped. Choose RESUME to continue where it left off.", Ui.Accent);
            }
            catch (Exception ex)
            {
                SetMode(Mode.Error, "Something went wrong", Short(ex), Ui.Danger);
            }
            finally { _cts = null; }
        }

        void Launch()
        {
            var exe = _u.GameExe(_remote);
            if (!File.Exists(exe)) { _ = CheckAsync(); return; }
            try
            {
                Watch(Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = Path.GetDirectoryName(exe), UseShellExecute = false }), exe);
                SetMode(Mode.Playing, "Aetherion is running", "Have a good match.");
                WindowState = FormWindowState.Minimized;
            }
            catch (Exception ex)
            {
                SetMode(Mode.Error, "The game did not start", Short(ex), Ui.Danger);
            }
        }

        void Watch(Process p, string exe)
        {
            _game = p;
            _game.EnableRaisingEvents = true;
            _game.Exited += (s, e) => BeginInvoke((Action)(async () =>
            {
                int code = 0;
                try { code = p.ExitCode; } catch (Exception) { }
                _game = null;
                // After a crash the game can restart itself on Safe graphics (OpenGL): follow the new process
                // instead of coming back with PLAY while it is starting.
                await Task.Delay(2000);
                var again = FindGame(exe);
                if (again != null) { Watch(again, exe); return; }
                if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
                Activate();
                await CheckAsync(true);
                if (code != 0 && _mode == Mode.Ready)
                    SetMode(Mode.Ready, "Aetherion closed unexpectedly",
                        string.Format("Error 0x{0:X8}. Press PLAY again; if it keeps crashing, the game switches itself to Safe graphics (Settings > Graphics).", code),
                        Ui.Danger);
            }));
        }

        static Process FindGame(string exe)
        {
            foreach (var q in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(exe)))
            {
                try { if (string.Equals(q.MainModule.FileName, exe, StringComparison.OrdinalIgnoreCase)) return q; }
                catch (Exception) { }
            }
            return null;
        }

        async Task PollAsync()
        {
            _pollCount++;
            await RefreshServersAsync();
            if (_pollCount % 15 == 0 && (_mode == Mode.Ready || _mode == Mode.Playing || _offline))
            {
                var before = _remote?.Version;
                await CheckAsync(true);
                if (_remote != null && before != null && _remote.Version != before) FlashIfInactive();
            }
        }

        async Task RefreshServersAsync()
        {
            try
            {
                var text = await _u.GetStringAsync(_baseUrl.TrimEnd('/') + "/api/status", CancellationToken.None);
                var d = Json.Obj(Json.Parse(text));
                _servers = Json.Arr(d, "servers").Cast<object>().Select(Json.Obj).ToList();
                _onlineCount = (int)Json.Long(d, "online");
                _serversUp = _servers.Count > 0;
            }
            catch (Exception) { _serversUp = false; _servers = null; }
            Invalidate();
        }

        void FlashIfInactive()
        {
            if (Form.ActiveForm != this) Native.FlashWindow(Handle, true);
        }

        static string Short(Exception e)
        {
            while (e is AggregateException && e.InnerException != null) e = e.InnerException;
            if (e is System.Net.Http.HttpRequestException && e.InnerException != null) return e.InnerException.Message.TrimEnd('.') + ".";
            return e.Message;
        }

        // ------------------------------------------------------------------ input

        PointF Logical(Point p) => new PointF(p.X / S, p.Y / S);

        string HitAt(PointF p)
        {
            foreach (var kv in _hit) if (kv.Value.Contains(p)) return kv.Key;
            return null;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            var h = HitAt(Logical(e.Location));
            if (h != _hover) { _hover = h; Cursor = h != null ? Cursors.Hand : Cursors.Default; Invalidate(); }
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            _hover = null;
            Invalidate();
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            var lp = Logical(e.Location);
            var h = HitAt(lp);
            if (h == null && lp.Y < 48 && e.Button == MouseButtons.Left)
            {
                Native.ReleaseCapture();
                Native.SendMessage(Handle, 0xA1, (IntPtr)2, IntPtr.Zero);  // drag by the title bar
                return;
            }
            _pressed = h;
            Invalidate();
        }

        protected override async void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            var h = HitAt(Logical(e.Location));
            var was = _pressed;
            _pressed = null;
            Invalidate();
            if (h == null || h != was || e.Button != MouseButtons.Left) return;
            switch (h)
            {
                case "close": Close(); break;
                case "min": WindowState = FormWindowState.Minimized; break;
                case "main": await MainButtonAsync(); break;
                case "change": ChangeFolder(); break;
                case "folder": if (Directory.Exists(_u.InstallDir)) Process.Start("explorer.exe", "\"" + _u.InstallDir + "\""); break;
                case "verify": if (_mode == Mode.Ready || _mode == Mode.Update || _mode == Mode.Error) await RunUpdateAsync(true); break;
                case "website": Process.Start(Program.Website); break;
                case "uninstall":
                    if (_mode != Mode.Working && Setup.Uninstall() == 0) Close();
                    break;
            }
        }

        async Task MainButtonAsync()
        {
            switch (_mode)
            {
                case Mode.Install:
                case Mode.Update: await RunUpdateAsync(false); break;
                case Mode.Ready: Launch(); break;
                case Mode.Working: _cts?.Cancel(); break;
                case Mode.Error:
                    if (_remote != null && _status == "Paused") await RunUpdateAsync(false);
                    else await CheckAsync();
                    break;
            }
        }

        void ChangeFolder()
        {
            if (_mode == Mode.Working || _mode == Mode.Playing) return;
            using (var dlg = new FolderBrowserDialog { Description = "Choose where to install Aetherion Project. A folder named \"Aetherion Project\" is made inside it.", ShowNewFolderButton = true })
            {
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                var dir = dlg.SelectedPath;
                if (!Path.GetFileName(dir.TrimEnd('\\')).Equals("Aetherion Project", StringComparison.OrdinalIgnoreCase))
                    dir = Path.Combine(dir, "Aetherion Project");
                var installed = _u.InstalledVersion(_remote) != "";
                if (installed && !string.Equals(Path.GetFullPath(dir), Path.GetFullPath(_u.InstallDir), StringComparison.OrdinalIgnoreCase))
                {
                    var ask = MessageBox.Show(this, "Move the installed game to\n" + dir + "?", "Aetherion Project", MessageBoxButtons.OKCancel, MessageBoxIcon.Question);
                    if (ask != DialogResult.OK) return;
                    try
                    {
                        if (Directory.Exists(dir) && Directory.GetFileSystemEntries(dir).Length > 0) throw new IOException("That folder is not empty.");
                        if (Directory.Exists(dir)) Directory.Delete(dir);
                        Directory.CreateDirectory(Path.GetDirectoryName(dir));
                        if (Path.GetPathRoot(Path.GetFullPath(dir)).Equals(Path.GetPathRoot(Path.GetFullPath(_u.InstallDir)), StringComparison.OrdinalIgnoreCase))
                            Directory.Move(_u.InstallDir, dir);
                        else throw new IOException("Moving to another drive is not supported: uninstall, then install to the new folder.");
                    }
                    catch (Exception ex)
                    {
                        MessageBox.Show(this, "The game could not be moved: " + ex.Message, "Aetherion Project", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return;
                    }
                }
                _u.InstallDir = dir;
                Program.InstallDir = dir;
                if (_remote != null) ShowLocalState();
                Invalidate();
            }
        }

        // ------------------------------------------------------------------ drawing

        void BuildBackground()
        {
            _bgCache?.Dispose();
            _bgCache = new Bitmap(Math.Max(1, ClientSize.Width), Math.Max(1, ClientSize.Height));
            using (var g = Graphics.FromImage(_bgCache))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.ScaleTransform(S, S);
                // Cover: the artificial sun stays in the upper right.
                float sc = Math.Max(W / _art.Width, H / _art.Height);
                float iw = _art.Width * sc, ih = _art.Height * sc;
                g.DrawImage(_art, (W - iw) * 0.7f, (H - ih) * 0.3f, iw, ih);
                using (var lb = new LinearGradientBrush(new RectangleF(0, 0, W, H), Color.Black, Color.Black, 0f))
                {
                    lb.InterpolationColors = new ColorBlend
                    {
                        Colors = new[] { Color.FromArgb(238, 7, 9, 12), Color.FromArgb(190, 7, 9, 12), Color.FromArgb(40, 7, 9, 12), Color.FromArgb(10, 7, 9, 12) },
                        Positions = new[] { 0f, 0.36f, 0.72f, 1f },
                    };
                    g.FillRectangle(lb, 0, 0, W, H);
                }
                using (var bb = new LinearGradientBrush(new RectangleF(0, H - 300, W, 300), Color.FromArgb(0, 7, 9, 12), Color.FromArgb(250, 7, 9, 12), 90f))
                    g.FillRectangle(bb, 0, H - 299, W, 300);
                using (var tb = new LinearGradientBrush(new RectangleF(0, 0, W, 110), Color.FromArgb(170, 5, 6, 8), Color.FromArgb(0, 5, 6, 8), 90f))
                    g.FillRectangle(tb, 0, 0, W, 109);
                using (var pen = new Pen(Color.FromArgb(40, 255, 255, 255)))
                    g.DrawRectangle(pen, 0, 0, W - 1 / S, H - 1 / S);
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            if (_bgCache == null || _bgCache.Width != ClientSize.Width || _bgCache.Height != ClientSize.Height) BuildBackground();
            g.DrawImageUnscaled(_bgCache, 0, 0);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.ScaleTransform(S, S);
            _hit.Clear();
            DrawTitleBar(g);
            DrawHero(g);
            DrawNews(g);
            DrawServers(g);
            DrawBottom(g);
        }

        bool Hot(string id) => _hover == id;

        void DrawTitleBar(Graphics g)
        {
            g.DrawImage(_icon, 18, 13, 22, 22);
            Ui.Draw(g, "AETHERION PROJECT", _fHead, Color.FromArgb(200, Ui.Text), 50, 17, 2.2f);
            var close = new RectangleF(W - 50, 0, 50, 44);
            var min = new RectangleF(W - 100, 0, 50, 44);
            _hit["close"] = close;
            _hit["min"] = min;
            if (Hot("close")) g.FillRectangle(new SolidBrush(Color.FromArgb(220, 196, 43, 28)), close);
            if (Hot("min")) g.FillRectangle(new SolidBrush(Color.FromArgb(30, 255, 255, 255)), min);
            using (var pen = new Pen(Ui.Text, 1.4f))
            {
                float cx = close.X + 25, cy = 22;
                g.DrawLine(pen, cx - 6, cy - 6, cx + 6, cy + 6);
                g.DrawLine(pen, cx + 6, cy - 6, cx - 6, cy + 6);
                g.DrawLine(pen, min.X + 19, cy, min.X + 31, cy);
            }
            Ui.DrawRight(g, "Launcher " + Program.Version, _fSmall, Color.FromArgb(150, Ui.Dim), W - 116, 15);
        }

        void DrawHero(Graphics g)
        {
            float x = M, y = 86;
            // Soft shadow behind the title so it reads over the sky.
            Ui.Draw(g, "AETHERION", _fTitle, Color.FromArgb(120, 0, 0, 0), x + 3, y + 4, 5);
            Ui.Draw(g, "AETHERION", _fTitle, Ui.Text, x, y, 5);
            float pw = Ui.Draw(g, "PROJECT", _fSub, Ui.Accent, x + 4, y + 106, 21);
            using (var lb = new LinearGradientBrush(new RectangleF(x + 4, y + 158, 180, 2), Ui.Accent, Color.FromArgb(0, Ui.Accent), 0f))
                g.FillRectangle(lb, x + 4, y + 158, 180, 2);
            Ui.Draw(g, "by Aljay Leodones", _fBy, Ui.Text, x + 4, y + 174);
            var tag = "AZAZ GAMES";
            float tw = Ui.Measure(g, tag, _fHead, 3.2f);
            var pill = new RectangleF(x + 4, y + 210, tw + 26, 28);
            Ui.Fill(g, pill, 14, Color.FromArgb(40, Ui.Accent2));
            Ui.Stroke(g, pill, 14, Color.FromArgb(150, Ui.Accent2));
            Ui.Draw(g, tag, _fHead, Ui.Accent2, pill.X + 13, pill.Y + 6, 3.2f);
            Ui.Wrap(g, "Battle royale and team deathmatch in the Philippines. New map: Freight Delight, a container-yard slum by the port at night, 12 against 12 with a second floor. PC, Mac and phones share matches.",
                _fBody, Ui.Dim, new RectangleF(x + 4, y + 254, 500, 70));
        }

        static string MapName(string id)
        {
            switch (id)
            {
                case "malasugue_mall": return "Malasugue Mall";
                case "freight_delight": return "Freight Delight";
                case "lawless_sub": return "Lawless Sub";
                case "kalinaw": case "": return "Sitio Kalinaw";
                default: return id;
            }
        }

        void DrawNews(Graphics g)
        {
            var r = new RectangleF(M, 418, 520, 150);
            Ui.Fill(g, r, 10, Ui.Panel);
            Ui.Stroke(g, r, 10, Ui.Line);
            Ui.Draw(g, "WHAT'S NEW", _fHead, Ui.Accent, r.X + 20, r.Y + 16, 3);
            if (_remote != null)
            {
                var v = "VERSION " + _remote.Version;
                Ui.DrawRight(g, v, _fHead, Ui.Dim, r.Right - 20, r.Y + 16, 2);
            }
            float y = r.Y + 42;
            var notes = _remote?.Notes ?? new List<string> { _offline ? "Release notes appear here when the launcher is online." : "Loading the latest release…" };
            foreach (var n in notes)
            {
                float h = Ui.WrapHeight(g, n, _fBody, r.Width - 56);
                if (y + Math.Min(h, 21) > r.Bottom - 10) break;
                Ui.Fill(g, new RectangleF(r.X + 22, y + 7, 5, 5), 2.5f, Ui.Accent);
                var box = new RectangleF(r.X + 36, y, r.Width - 56, Math.Min(h + 1, r.Bottom - 12 - y));
                Ui.Wrap(g, n, _fBody, Ui.Text, box);
                y += box.Height + 6;
            }
        }

        void DrawServers(Graphics g)
        {
            float w = 360;
            var r = new RectangleF(W - M - w, 70, w, 0);
            int rows = _servers?.Count ?? 1;
            r.Height = 58 + Math.Max(rows, 1) * 46;
            Ui.Fill(g, r, 10, Ui.Panel);
            Ui.Stroke(g, r, 10, Ui.Line);
            var dot = _serversUp == true ? Ui.Good : _serversUp == false ? Ui.Danger : Ui.Dim;
            float pulse = _serversUp == true ? (float)(0.5 + 0.5 * Math.Sin(_tick * 0.12)) : 0;
            Ui.Fill(g, new RectangleF(r.X + 20 - 4 * pulse, r.Y + 21 - 4 * pulse, 10 + 8 * pulse, 10 + 8 * pulse), 5 + 4 * pulse, Color.FromArgb((int)(70 * (1 - pulse)), dot));
            Ui.Fill(g, new RectangleF(r.X + 20, r.Y + 21, 10, 10), 5, dot);
            Ui.Draw(g, "OFFICIAL SERVERS", _fHead, Ui.Text, r.X + 40, r.Y + 18, 3);
            var right = _serversUp == true ? (_onlineCount + " online") : _serversUp == false ? "offline" : "…";
            Ui.DrawRight(g, right, _fSmall, Ui.Dim, r.Right - 20, r.Y + 18);
            float y = r.Y + 52;
            if (_servers == null || _servers.Count == 0)
            {
                Ui.Draw(g, _serversUp == false ? "The official servers can't be reached right now." : "Checking…", _fBody, Ui.Dim, r.X + 20, y + 4);
                return;
            }
            foreach (var s in _servers)
            {
                var mode = Json.Str(s, "game_mode") == "deathmatch" ? "Deathmatch" : "Classic";
                var map = MapName(Json.Str(s, "map"));
                Ui.Draw(g, mode, _fBodyB, Ui.Text, r.X + 20, y);
                Ui.Draw(g, map + " · " + Json.Str(s, "region"), _fSmall, Ui.Dim, r.X + 20, y + 20);
                Ui.DrawRight(g, Json.Long(s, "players") + " / " + Json.Long(s, "max"), _fBodyB, Ui.Text, r.Right - 20, y);
                var st = Json.Str(s, "state") == "lobby" ? "in the lobby" : "match in progress";
                Ui.DrawRight(g, st, _fSmall, Json.Str(s, "state") == "lobby" ? Ui.Accent2 : Ui.Accent, r.Right - 20, y + 20);
                y += 46;
            }
        }

        void DrawBottom(Graphics g)
        {
            float barW = W - M * 2 - BtnW - 32;
            // Status
            Ui.Draw(g, _status, _fStatus, _statusColor, M, H - 150);
            var detail = _detail;
            double frac = -1;
            if (_mode == Mode.Working && _p != null)
            {
                frac = _p.Total > 0 ? Math.Min(1.0, _p.Done / (double)_p.Total) : 0;
                var parts = new List<string>();
                if (_p.Total > 0) parts.Add(string.Format("{0} of {1}", Updater.Size(_p.Done), Updater.Size(_p.Total)));
                if (_p.DownloadTotal > 0) parts.Add(string.Format("downloaded {0} of {1}", Updater.Size(_p.Downloaded), Updater.Size(_p.DownloadTotal)));
                if (_p.Speed > 1024 && _p.DownloadTotal > _p.Downloaded)
                {
                    parts.Add(Updater.Size((long)_p.Speed) + "/s");
                    var left = TimeSpan.FromSeconds((_p.DownloadTotal - _p.Downloaded) / Math.Max(_p.Speed, 1));
                    parts.Add(left.TotalMinutes >= 1 ? "about " + Math.Ceiling(left.TotalMinutes) + " min left" : "less than a minute left");
                }
                detail = (_p.Total > 0 ? Math.Floor(frac * 100) + "%  ·  " : "") + (parts.Count > 0 ? string.Join("  ·  ", parts) : _p.Phase);
            }
            Ui.Wrap(g, detail, _fBody, Ui.Dim, new RectangleF(M, H - 118, barW, 40));
            // Progress
            var track = new RectangleF(M, H - 72, barW, 6);
            Ui.Fill(g, track, 3, Color.FromArgb(34, 255, 255, 255));
            if (frac >= 0)
            {
                var fill = new RectangleF(track.X, track.Y, Math.Max(6, (float)(track.Width * frac)), track.Height);
                using (var lb = new LinearGradientBrush(new RectangleF(track.X, track.Y, track.Width, track.Height), Color.FromArgb(214, 120, 36), Ui.AccentHot, 0f))
                using (var p = Ui.Round(fill, 3))
                    g.FillPath(lb, p);
            }
            else if (_mode == Mode.Checking || _mode == Mode.Working)
            {
                float seg = barW * 0.22f, t = (_tick * 9) % (barW + seg) - seg;
                var fill = RectangleF.Intersect(new RectangleF(M + t, track.Y, seg, track.Height), track);
                if (fill.Width > 0) Ui.Fill(g, fill, 3, Color.FromArgb(200, Ui.Accent));
            }
            // Folder and links
            float y = H - 50, x = M;
            x += Ui.Draw(g, "Install folder", _fSmall, Ui.Dim, x, y) + 10;
            var path = Ui.Ellipsize(g, _u.InstallDir, _fSmall, 330);
            x += Ui.Draw(g, path, _fSmall, Ui.Text, x, y) + 18;
            x = Link(g, "change", "Change", x, y) + 16;
            x = Link(g, "folder", "Open folder", x, y) + 16;
            if (_u.InstalledVersion(_remote) != "") x = Link(g, "verify", "Verify files", x, y) + 16;
            float rx = M + barW;
            if (_u.InstalledVersion(_remote) != "")
            {
                float uw = Ui.Measure(g, "Uninstall", _fSmall);
                Link(g, "uninstall", "Uninstall", rx - uw, y, Ui.Dim);
                rx -= uw + 16;
            }
            float ww = Ui.Measure(g, "Website", _fSmall);
            Link(g, "website", "Website", rx - ww, y);
            // The button
            var b = new RectangleF(W - M - BtnW, H - 154, BtnW, BtnH);
            string label;
            bool enabled = true, primary = true;
            switch (_mode)
            {
                case Mode.Install: label = "INSTALL"; break;
                case Mode.Update: label = "UPDATE"; break;
                case Mode.Ready: label = "PLAY"; break;
                case Mode.Working: label = "PAUSE"; primary = false; break;
                case Mode.Error: label = _status == "Paused" ? "RESUME" : "RETRY"; break;
                case Mode.Playing: label = "PLAYING"; enabled = false; break;
                default: label = "PLEASE WAIT"; enabled = false; break;
            }
            if (enabled) _hit["main"] = b;
            bool hot = enabled && Hot("main"), down = enabled && _pressed == "main";
            if (primary)
            {
                if (enabled)
                {
                    // Glow
                    for (int i = 3; i >= 1; i--)
                        Ui.Fill(g, RectangleF.Inflate(b, i * 5, i * 5), 12 + i * 5, Color.FromArgb(hot ? 22 : 12, Ui.Accent));
                }
                var top = !enabled ? Color.FromArgb(70, 62, 50) : down ? Color.FromArgb(214, 136, 40) : hot ? Ui.AccentHot : Ui.Accent;
                var bot = !enabled ? Color.FromArgb(58, 52, 44) : down ? Color.FromArgb(190, 112, 30) : hot ? Color.FromArgb(245, 160, 64) : Color.FromArgb(222, 132, 38);
                using (var lb = new LinearGradientBrush(b, top, bot, 90f))
                using (var p = Ui.Round(b, 12))
                    g.FillPath(lb, p);
                var tc = enabled ? Color.FromArgb(26, 17, 6) : Color.FromArgb(150, Ui.Dim);
                Ui.Draw(g, label, _fBtn, tc, b.X + (b.Width - Ui.Measure(g, label, _fBtn, 4)) / 2, b.Y + 20, 4);
            }
            else
            {
                Ui.Fill(g, b, 12, hot ? Color.FromArgb(60, 255, 255, 255) : Color.FromArgb(34, 255, 255, 255));
                Ui.Stroke(g, b, 12, Color.FromArgb(90, 255, 255, 255));
                Ui.Draw(g, label, _fBtn, Ui.Text, b.X + (b.Width - Ui.Measure(g, label, _fBtn, 4)) / 2, b.Y + 20, 4);
            }
            Ui.DrawRight(g, "© Aljay Leodones · AzAz Games", _fSmall, Color.FromArgb(130, Ui.Dim), W - M, H - 50);
        }

        float Link(Graphics g, string id, string text, float x, float y, Color? color = null)
        {
            bool enabled = _mode != Mode.Working || id == "website" || id == "folder";
            var c = !enabled ? Color.FromArgb(90, Ui.Dim) : Hot(id) ? Color.White : color ?? Ui.Accent2;
            float w = Ui.Draw(g, text, _fSmall, c, x, y);
            if (enabled) _hit[id] = new RectangleF(x - 2, y - 4, w + 4, 22);
            if (Hot(id) && enabled)
                using (var pen = new Pen(c, 1)) g.DrawLine(pen, x, y + 18, x + w, y + 18);
            return x + w;
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (_mode == Mode.Working)
            {
                var r = MessageBox.Show(this, "Stop the download? It continues from where it stopped next time.", "Aetherion Project",
                    MessageBoxButtons.OKCancel, MessageBoxIcon.Question);
                if (r != DialogResult.OK) { e.Cancel = true; return; }
                _cts?.Cancel();
            }
            base.OnFormClosing(e);
        }
    }
}
