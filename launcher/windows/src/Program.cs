using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;

namespace Aetherion.Launcher
{
    static class Program
    {
        public const string BaseUrl = "https://aetherion.15-235-246-87.sslip.io";
        public const string Website = BaseUrl + "/";
        public static readonly string Version = Assembly.GetExecutingAssembly().GetName().Version.ToString(3);
        public static string Root => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Aetherion Project");
        public static string InstalledLauncher => Path.Combine(Root, "AetherionLauncher.exe");
        public static string SelfPath => Process.GetCurrentProcess().MainModule.FileName;
        public static Dictionary<string, string> Args = new Dictionary<string, string>();

        [STAThread]
        static int Main(string[] argv)
        {
            foreach (var a in argv)
            {
                if (!a.StartsWith("--")) continue;
                var i = a.IndexOf('=');
                Args[i > 0 ? a.Substring(2, i - 2) : a.Substring(2)] = i > 0 ? a.Substring(i + 1) : "true";
            }
            var baseUrl = Arg("base-url", BaseUrl);
            if (Args.ContainsKey("selftest")) return SelfTest(baseUrl);
            if (Args.ContainsKey("uninstall")) return Setup.Uninstall();
            CleanupOld();
            using (var single = new Mutex(true, @"Local\AetherionProjectLauncher", out bool first))
            {
                if (!first)
                {
                    var h = Native.FindWindow(null, LauncherForm.WindowTitle);
                    if (h != IntPtr.Zero) { Native.ShowWindow(h, 9); Native.SetForegroundWindow(h); }
                    return 0;
                }
                if (!Args.ContainsKey("portable") && Setup.InstallSelfAndRelaunch(argv)) return 0;
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new LauncherForm(baseUrl));
            }
            return 0;
        }

        public static string Arg(string k, string def) => Args.TryGetValue(k, out var v) ? v : def;

        static void CleanupOld()
        {
            try { var old = SelfPath + ".old"; if (File.Exists(old)) File.Delete(old); } catch (Exception) { }
        }

        public static string Settings => Path.Combine(Root, "launcher-settings.json");

        public static string InstallDir
        {
            get
            {
                try
                {
                    if (File.Exists(Settings))
                    {
                        var d = Json.Obj(Json.Parse(File.ReadAllText(Settings)));
                        var dir = Json.Str(d, "install_dir");
                        if (dir != "") return dir;
                    }
                }
                catch (Exception) { }
                return Path.Combine(Root, "Game");
            }
            set
            {
                Directory.CreateDirectory(Root);
                File.WriteAllText(Settings, Json.Write(new Dictionary<string, object> { ["install_dir"] = value }));
            }
        }

        /// <summary>
        /// --selftest --install-dir=X [--report=file] [--base-url=U]: installs or updates without a window and writes a JSON
        /// report (tests and CI; nothing is launched).
        /// </summary>
        static int SelfTest(string baseUrl)
        {
            Native.AttachConsole(-1);
            var report = new Dictionary<string, object> { ["launcher"] = Version, ["ok"] = false };
            var sw = Stopwatch.StartNew();
            try
            {
                var dir = Arg("install-dir", Path.Combine(Path.GetTempPath(), "aetherion-selftest"));
                var u = new Updater(baseUrl, dir);
                UpdateProgress last = null;
                u.Progress += p => last = p;
                var m = u.FetchAsync(CancellationToken.None).GetAwaiter().GetResult();
                report["version"] = m.Version;
                report["before"] = u.InstalledVersion(m);
                report["pending_download"] = u.PendingDownload(m, false);
                u.ApplyAsync(m, Args.ContainsKey("verify"), CancellationToken.None).GetAwaiter().GetResult();
                report["after"] = u.InstalledVersion(m);
                report["downloaded"] = last?.Downloaded ?? 0;
                report["reused"] = last?.Reused ?? 0;
                report["written"] = last?.Done ?? 0;
                report["game_exe"] = File.Exists(u.GameExe(m));
                report["ok"] = (string)report["after"] == m.Version && (bool)report["game_exe"];
            }
            catch (Exception e)
            {
                report["error"] = e.GetType().Name + ": " + e.Message;
            }
            report["seconds"] = Math.Round(sw.Elapsed.TotalSeconds, 1);
            var text = Json.Write(report);
            Console.WriteLine(text);
            if (Args.TryGetValue("report", out var rp)) File.WriteAllText(rp, text);
            return (bool)report["ok"] ? 0 : 1;
        }
    }

    /// <summary>Per-user setup: the launcher lives in %LocalAppData%\Aetherion Project with shortcuts and an Apps entry.</summary>
    static class Setup
    {
        const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\AetherionProject";
        static string Desktop => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Aetherion Project.lnk");
        static string StartMenu => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Aetherion Project.lnk");

        /// <summary>First run from Downloads: copy the launcher into place, add shortcuts, start that copy. True if it did.</summary>
        public static bool InstallSelfAndRelaunch(string[] argv)
        {
            var self = Program.SelfPath;
            var target = Program.InstalledLauncher;
            try
            {
                if (string.Equals(Path.GetFullPath(self), Path.GetFullPath(target), StringComparison.OrdinalIgnoreCase))
                {
                    EnsureShortcuts(target);
                    return false;
                }
                Directory.CreateDirectory(Program.Root);
                bool newer = !File.Exists(target) ||
                    new Version(FileVersionInfo.GetVersionInfo(target).FileVersion ?? "0.0.0") <= new Version(FileVersionInfo.GetVersionInfo(self).FileVersion ?? "0.0.0");
                if (newer)
                {
                    if (IsRunning(target)) return false;
                    File.Copy(self, target, true);
                }
                EnsureShortcuts(target);
                Process.Start(new ProcessStartInfo(target, string.Join(" ", argv)) { UseShellExecute = false });
                return true;
            }
            catch (Exception)
            {
                return false;  // run from where it is
            }
        }

        static bool IsRunning(string exe)
        {
            foreach (var p in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(exe)))
            {
                try { if (p.Id != Process.GetCurrentProcess().Id && string.Equals(p.MainModule.FileName, exe, StringComparison.OrdinalIgnoreCase)) return true; }
                catch (Exception) { }
            }
            return false;
        }

        public static void EnsureShortcuts(string target)
        {
            try
            {
                if (!File.Exists(StartMenu)) MakeShortcut(StartMenu, target);
                if (!File.Exists(Desktop) && !File.Exists(Path.Combine(Program.Root, ".no-desktop-shortcut"))) MakeShortcut(Desktop, target);
                using (var k = Registry.CurrentUser.CreateSubKey(UninstallKey))
                {
                    k.SetValue("DisplayName", "Aetherion Project");
                    k.SetValue("Publisher", "AzAz Games");
                    k.SetValue("DisplayIcon", target + ",0");
                    k.SetValue("DisplayVersion", Program.Version);
                    k.SetValue("InstallLocation", Program.Root);
                    k.SetValue("UninstallString", "\"" + target + "\" --uninstall");
                    k.SetValue("URLInfoAbout", Program.Website);
                    k.SetValue("NoModify", 1, RegistryValueKind.DWord);
                    k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                }
            }
            catch (Exception) { }
        }

        static void MakeShortcut(string path, string target)
        {
            var t = Type.GetTypeFromProgID("WScript.Shell");
            dynamic shell = Activator.CreateInstance(t);
            try
            {
                dynamic lnk = shell.CreateShortcut(path);
                lnk.TargetPath = target;
                lnk.WorkingDirectory = Path.GetDirectoryName(target);
                lnk.IconLocation = target + ",0";
                lnk.Description = "Aetherion Project by Aljay Leodones · AzAz Games";
                lnk.Save();
                Marshal.FinalReleaseComObject(lnk);
            }
            finally { Marshal.FinalReleaseComObject(shell); }
        }

        public static int Uninstall()
        {
            var game = Program.InstallDir;
            var r = MessageBox.Show("Remove Aetherion Project and its launcher from this PC?\n\nGame files: " + game +
                "\n\nYour profile, outfits and settings are kept (they live in your user folder).", "Uninstall Aetherion Project",
                MessageBoxButtons.OKCancel, MessageBoxIcon.Question);
            if (r != DialogResult.OK) return 1;
            try { RemoveGame(game); }
            catch (Exception e) { MessageBox.Show("Some game files could not be removed (" + e.Message + "). Close the game and try again.", "Aetherion Project"); return 1; }
            foreach (var p in new[] { Desktop, StartMenu }) try { File.Delete(p); } catch (Exception) { }
            try { Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, false); } catch (Exception) { }
            // The launcher cannot delete itself while it runs: a hidden shell removes the folder a moment later.
            Process.Start(new ProcessStartInfo("cmd.exe", "/c ping 127.0.0.1 -n 3 >nul & rmdir /s /q \"" + Program.Root + "\"")
            { CreateNoWindow = true, UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden });
            return 0;
        }

        /// <summary>Deletes only the files the launcher installed (listed in its state), then the folders they leave empty.</summary>
        static void RemoveGame(string dir)
        {
            var state = Path.Combine(dir, ".launcher", "state.json");
            if (!File.Exists(state)) return;
            var d = Json.Obj(Json.Parse(File.ReadAllText(state)));
            var folders = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var kv in Json.Obj(d["files"]))
            {
                if (kv.Key.Contains("..") || Path.IsPathRooted(kv.Key)) continue;
                var p = Path.Combine(dir, kv.Key);
                foreach (var extra in new[] { p, p + ".download" })
                    if (File.Exists(extra)) File.Delete(extra);
                for (var f = Path.GetDirectoryName(p); f != null && f.Length > dir.Length; f = Path.GetDirectoryName(f)) folders.Add(f);
            }
            Directory.Delete(Path.Combine(dir, ".launcher"), true);
            foreach (var f in folders.OrderByDescending(x => x.Length))
                try { if (Directory.Exists(f) && Directory.GetFileSystemEntries(f).Length == 0) Directory.Delete(f); } catch (Exception) { }
            try { if (Directory.GetFileSystemEntries(dir).Length == 0) Directory.Delete(dir); } catch (Exception) { }
        }
    }

    static class Native
    {
        [DllImport("kernel32.dll")] public static extern bool AttachConsole(int pid);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] public static extern bool ReleaseCapture();
        [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] public static extern bool FlashWindow(IntPtr h, bool invert);
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);
    }
}
