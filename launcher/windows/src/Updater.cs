using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Aetherion.Launcher
{
    sealed class UpdateProgress
    {
        public string Phase = "";      // what is happening, for the status line
        public string File = "";
        public long Done, Total;       // bytes of game files written / to write
        public long Downloaded, DownloadTotal;
        public long Reused;            // bytes taken from files already on disk
        public double Speed;           // download bytes per second
    }

    /// <summary>
    /// Installs and updates the game from signed releases (docs/HOSTING.md). Every file is rebuilt in order from its
    /// chunks: a chunk already on disk (in the installed version of any file) is copied after its hash is checked,
    /// anything else is downloaded, inflated and checked. Files are written beside the old ones and swapped in when
    /// their whole hash matches. An interrupted download resumes where it stopped.
    /// </summary>
    sealed class Updater
    {
        public const string Platform = "windows";
        public readonly Uri ReleaseUrl;
        public string InstallDir;
        readonly HttpClient _http;
        public event Action<UpdateProgress> Progress;

        const int Parallel = 6, Window = 18;

        public Updater(string baseUrl, string installDir)
        {
            ReleaseUrl = new Uri(baseUrl.TrimEnd('/') + "/updates/" + Platform + "/release.json");
            InstallDir = installDir;
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            ServicePointManager.DefaultConnectionLimit = Math.Max(ServicePointManager.DefaultConnectionLimit, Parallel + 2);
            _http = new HttpClient(new HttpClientHandler { AutomaticDecompression = DecompressionMethods.None }) { Timeout = TimeSpan.FromSeconds(60) };
            _http.DefaultRequestHeaders.UserAgent.ParseAdd("AetherionLauncher/" + Program.Version + " (Windows)");
        }

        string StateDir => Path.Combine(InstallDir, ".launcher");
        string StatePath => Path.Combine(StateDir, "state.json");
        string JournalPath => Path.Combine(StateDir, "journal.json");

        // ------------------------------------------------------------------ releases

        public async Task<Manifest> FetchAsync(CancellationToken ct)
        {
            var url = new Uri(ReleaseUrl + "?t=" + DateTime.UtcNow.Ticks);
            var text = await _http.GetStringAsync(url).ConfigureAwait(false);
            var doc = Json.Obj(Json.Parse(text));
            var raw = Convert.FromBase64String(Json.Str(doc, "manifest"));
            var sig = Convert.FromBase64String(Json.Str(doc, "sig"));
            if (!Signature.Verify(raw, sig))
                throw new InvalidDataException("The release is not signed by Aetherion Project. Nothing was installed.");
            var m = Manifest.Parse(raw);
            if (m.Platform != Platform) throw new InvalidDataException("The release is for " + m.Platform + ", not Windows.");
            return m;
        }

        public Uri Resolve(string relative) => new Uri(ReleaseUrl, relative);

        // ------------------------------------------------------------------ local state

        sealed class LocalFile
        {
            public string Sha256;
            public long Size;
            public List<ChunkRef> Chunks;
        }

        Dictionary<string, LocalFile> LoadState(out string version)
        {
            version = "";
            var files = new Dictionary<string, LocalFile>(StringComparer.OrdinalIgnoreCase);
            try
            {
                if (!File.Exists(StatePath)) return files;
                var d = Json.Obj(Json.Parse(File.ReadAllText(StatePath)));
                version = Json.Str(d, "version");
                foreach (var kv in Json.Obj(d["files"]))
                {
                    var f = Json.Obj(kv.Value);
                    var lf = new LocalFile { Sha256 = Json.Str(f, "sha256"), Size = Json.Long(f, "size"), Chunks = new List<ChunkRef>() };
                    long off = 0;
                    foreach (var co in Json.Arr(f, "chunks"))
                    {
                        var c = (object[])co;
                        lf.Chunks.Add(new ChunkRef { Hash = Convert.ToString(c[0]), Size = Convert.ToInt64(c[1]), Offset = off });
                        off += Convert.ToInt64(c[1]);
                    }
                    files[kv.Key] = lf;
                }
            }
            catch (Exception) { files.Clear(); version = ""; }
            return files;
        }

        void SaveState(Dictionary<string, LocalFile> files, string version)
        {
            Directory.CreateDirectory(StateDir);
            var o = new Dictionary<string, object> { ["version"] = version, ["platform"] = Platform };
            var fo = new Dictionary<string, object>();
            foreach (var kv in files)
                fo[kv.Key] = new Dictionary<string, object>
                {
                    ["sha256"] = kv.Value.Sha256,
                    ["size"] = kv.Value.Size,
                    ["chunks"] = kv.Value.Chunks.Select(c => new object[] { c.Hash, c.Size }).ToArray(),
                };
            o["files"] = fo;
            var tmp = StatePath + ".tmp";
            File.WriteAllText(tmp, Json.Write(o));
            if (File.Exists(StatePath)) File.Replace(tmp, StatePath, null);
            else File.Move(tmp, StatePath);
        }

        /// <summary>The version on disk, or "" when the game is not installed (or its files are missing).</summary>
        public string InstalledVersion(Manifest m = null)
        {
            var files = LoadState(out var v);
            if (v == "") return "";
            var launch = m?.Launch ?? "Aetherion.exe";
            return File.Exists(Path.Combine(InstallDir, launch)) ? v : "";
        }

        public string GameExe(Manifest m) => Path.Combine(InstallDir, m?.Launch ?? "Aetherion.exe");

        /// <summary>Bytes still to download for this release (a guess: chunks found on disk are counted as present).</summary>
        public long PendingDownload(Manifest m, bool verify)
        {
            var state = LoadState(out var _);
            var have = new HashSet<string>();
            foreach (var kv in state)
                if (File.Exists(Path.Combine(InstallDir, kv.Key)))
                    foreach (var c in kv.Value.Chunks) have.Add(c.Hash);
            long n = 0;
            foreach (var f in m.Files)
            {
                if (f.Link != null) continue;
                if (!verify && state.TryGetValue(f.Path, out var lf) && lf.Sha256 == f.Sha256 && ExistsWithSize(f)) continue;
                foreach (var c in f.Chunks) if (!have.Contains(c.Hash)) n += c.ZSize;
            }
            return n;
        }

        bool ExistsWithSize(FileEntry f)
        {
            var p = Path.Combine(InstallDir, f.Path);
            return File.Exists(p) && new FileInfo(p).Length == f.Size;
        }

        public bool IsGameRunning(Manifest m)
        {
            var exe = GameExe(m);
            foreach (var p in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(exe)))
            {
                try { if (string.Equals(p.MainModule.FileName, exe, StringComparison.OrdinalIgnoreCase)) return true; }
                catch (Exception) { return true; }  // cannot look inside: assume it is ours
            }
            return false;
        }

        // ------------------------------------------------------------------ install / update

        sealed class Source
        {
            public string Path;
            public long Offset, Size;
        }

        public async Task ApplyAsync(Manifest m, bool verifyAll, CancellationToken ct)
        {
            Directory.CreateDirectory(InstallDir);
            Directory.CreateDirectory(StateDir);
            var state = LoadState(out var _);
            var prog = new UpdateProgress { Phase = verifyAll ? "Checking files" : "Preparing" };
            Report(prog);

            // Which files need work.
            var todo = new List<FileEntry>();
            foreach (var f in m.Files)
            {
                if (f.Link != null) continue;
                var p = Path.Combine(InstallDir, f.Path);
                bool ok = state.TryGetValue(f.Path, out var lf) && lf.Sha256 == f.Sha256 && ExistsWithSize(f);
                if (ok && verifyAll)
                {
                    prog.Phase = "Checking " + f.Path;
                    Report(prog);
                    ok = await Task.Run(() => FileSha(p, ct), ct).ConfigureAwait(false) == f.Sha256;
                }
                if (!ok) todo.Add(f);
            }
            // Where chunks can be found on disk: the recorded layout of every file there, else the new layout.
            var sources = new Dictionary<string, List<Source>>();
            void AddSource(string hash, string path, long off, long size)
            {
                if (!sources.TryGetValue(hash, out var l)) sources[hash] = l = new List<Source>();
                l.Add(new Source { Path = path, Offset = off, Size = size });
            }
            foreach (var kv in state)
            {
                var p = Path.Combine(InstallDir, kv.Key);
                if (File.Exists(p))
                    foreach (var c in kv.Value.Chunks) AddSource(c.Hash, p, c.Offset, c.Size);
            }
            foreach (var f in m.Files)
            {
                var p = Path.Combine(InstallDir, f.Path);
                if (f.Link == null && !state.ContainsKey(f.Path) && File.Exists(p))
                    foreach (var c in f.Chunks) AddSource(c.Hash, p, c.Offset, c.Size);
            }
            prog.Total = todo.Sum(f => f.Size);
            prog.DownloadTotal = todo.Sum(f => f.Chunks.Where(c => !sources.ContainsKey(c.Hash)).Sum(c => c.ZSize));
            long need = todo.Count == 0 ? 0 : todo.Max(f => f.Size) + 64L * 1024 * 1024;
            var free = new DriveInfo(Path.GetPathRoot(Path.GetFullPath(InstallDir))).AvailableFreeSpace;
            if (free < need)
                throw new IOException(string.Format("Not enough disk space: {0} needed, {1} free on {2}.", Size(need), Size(free), Path.GetPathRoot(Path.GetFullPath(InstallDir))));
            if (todo.Count > 0 && IsGameRunning(m))
                throw new IOException("Close Aetherion first: the game is still running.");

            var clock = Stopwatch.StartNew();
            var speedClock = Stopwatch.StartNew();
            long speedMark = 0;
            foreach (var f in todo)
            {
                ct.ThrowIfCancellationRequested();
                prog.File = f.Path;
                prog.Phase = "Installing";
                await WriteFileAsync(m, f, sources, prog, ct, () =>
                {
                    if (speedClock.ElapsedMilliseconds >= 500)
                    {
                        double inst = (prog.Downloaded - speedMark) * 1000.0 / speedClock.ElapsedMilliseconds;
                        prog.Speed = prog.Speed <= 0 ? inst : prog.Speed * 0.7 + inst * 0.3;
                        speedMark = prog.Downloaded;
                        speedClock.Restart();
                    }
                    Report(prog);
                }).ConfigureAwait(false);
                state[f.Path] = new LocalFile { Sha256 = f.Sha256, Size = f.Size, Chunks = f.Chunks };
                SaveState(state, "");  // mixed versions until every file is done
            }
            // Files the new release no longer has.
            var keep = new HashSet<string>(m.Files.Select(f => f.Path), StringComparer.OrdinalIgnoreCase);
            foreach (var old in state.Keys.ToList())
            {
                if (keep.Contains(old)) continue;
                try { File.Delete(Path.Combine(InstallDir, old)); } catch (Exception) { }
                state.Remove(old);
            }
            SaveState(state, m.Version);
            try { if (File.Exists(JournalPath)) File.Delete(JournalPath); } catch (Exception) { }
            prog.Phase = "Done";
            prog.Done = prog.Total;
            Report(prog);
        }

        async Task WriteFileAsync(Manifest m, FileEntry f, Dictionary<string, List<Source>> sources, UpdateProgress prog,
            CancellationToken ct, Action tick)
        {
            var target = Path.Combine(InstallDir, f.Path);
            Directory.CreateDirectory(Path.GetDirectoryName(target));
            var tmp = target + ".download";
            int start = 0;
            long startBytes = 0;
            var j = ReadJournal();
            if (j != null && Json.Str(j, "file") == f.Path && Json.Str(j, "sha256") == f.Sha256 && File.Exists(tmp))
            {
                start = (int)Json.Long(j, "done");
                startBytes = start > 0 && start <= f.Chunks.Count ? f.Chunks[start - 1].Offset + f.Chunks[start - 1].Size : 0;
                if (new FileInfo(tmp).Length < startBytes) { start = 0; startBytes = 0; }
            }
            var chunksBase = Resolve(m.ChunksBase);
            using (var sha = SHA256.Create())
            using (var outf = new FileStream(tmp, start > 0 ? FileMode.Open : FileMode.Create, FileAccess.ReadWrite, FileShare.Read, 1 << 20))
            {
                if (start > 0)
                {
                    // Resume: hash what is already written, then continue after it.
                    var buf = new byte[1 << 20];
                    long left = startBytes;
                    while (left > 0)
                    {
                        int n = outf.Read(buf, 0, (int)Math.Min(buf.Length, left));
                        if (n <= 0) throw new IOException("Could not read the partial download.");
                        sha.TransformBlock(buf, 0, n, null, 0);
                        left -= n;
                    }
                    outf.SetLength(startBytes);
                    prog.Done += startBytes;
                }
                else outf.SetLength(0);

                var inflight = new Dictionary<int, Task<byte[]>>();
                var gate = new SemaphoreSlim(Parallel);
                Task<byte[]> Fetch(int i) => Task.Run(async () =>
                {
                    await gate.WaitAsync(ct).ConfigureAwait(false);
                    try { return await DownloadChunkAsync(chunksBase, f.Chunks[i], prog, ct).ConfigureAwait(false); }
                    finally { gate.Release(); }
                }, ct);

                long sinceFlush = 0;
                try
                {
                    for (int i = start; i < f.Chunks.Count; i++)
                    {
                        ct.ThrowIfCancellationRequested();
                        for (int k = i; k < Math.Min(f.Chunks.Count, i + Window); k++)
                            if (!inflight.ContainsKey(k) && !sources.ContainsKey(f.Chunks[k].Hash))
                                inflight[k] = Fetch(k);
                        var c = f.Chunks[i];
                        byte[] data = null;
                        if (!inflight.ContainsKey(i) && sources.TryGetValue(c.Hash, out var srcs))
                        {
                            foreach (var s in srcs)
                            {
                                data = ReadLocal(s, c.Hash);
                                if (data != null) break;
                            }
                            if (data != null) prog.Reused += data.Length;
                            else inflight[i] = Fetch(i);
                        }
                        if (data == null)
                        {
                            data = await inflight[i].ConfigureAwait(false);
                            inflight.Remove(i);
                        }
                        await outf.WriteAsync(data, 0, data.Length, ct).ConfigureAwait(false);
                        sha.TransformBlock(data, 0, data.Length, null, 0);
                        prog.Done += data.Length;
                        sinceFlush += data.Length;
                        if (sinceFlush >= 48L * 1024 * 1024 || i == f.Chunks.Count - 1)
                        {
                            outf.Flush(true);
                            WriteJournal(f, i + 1);
                            sinceFlush = 0;
                        }
                        tick();
                    }
                }
                finally
                {
                    foreach (var t in inflight.Values) _ = t.ContinueWith(_ => { }, TaskScheduler.Default);
                }
                sha.TransformFinalBlock(new byte[0], 0, 0);
                if (Hex.Of(sha.Hash) != f.Sha256 || outf.Length != f.Size)
                {
                    outf.Dispose();
                    try { File.Delete(tmp); File.Delete(JournalPath); } catch (Exception) { }
                    throw new InvalidDataException("A downloaded file did not match its release (" + f.Path + "). Try again.");
                }
            }
            for (int attempt = 0; ; attempt++)
            {
                try
                {
                    if (File.Exists(target)) File.Delete(target);
                    File.Move(tmp, target);
                    break;
                }
                catch (IOException) when (attempt < 10)
                {
                    await Task.Delay(500, ct).ConfigureAwait(false);
                }
                catch (UnauthorizedAccessException) when (attempt < 10)
                {
                    await Task.Delay(500, ct).ConfigureAwait(false);
                }
            }
        }

        static byte[] ReadLocal(Source s, string hash)
        {
            try
            {
                using (var fs = new FileStream(s.Path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    if (fs.Length < s.Offset + s.Size) return null;
                    fs.Seek(s.Offset, SeekOrigin.Begin);
                    var data = new byte[s.Size];
                    int got = 0;
                    while (got < data.Length)
                    {
                        int n = fs.Read(data, got, data.Length - got);
                        if (n <= 0) return null;
                        got += n;
                    }
                    using (var sha = SHA256.Create())
                        return Hex.Of(sha.ComputeHash(data)) == hash ? data : null;
                }
            }
            catch (Exception) { return null; }
        }

        async Task<byte[]> DownloadChunkAsync(Uri chunksBase, ChunkRef c, UpdateProgress prog, CancellationToken ct)
        {
            var url = new Uri(chunksBase, c.Hash.Substring(0, 2) + "/" + c.Hash);
            Exception last = null;
            for (int attempt = 0; attempt < 6; attempt++)
            {
                if (attempt > 0) await Task.Delay(TimeSpan.FromSeconds(Math.Min(20, 1 << attempt)), ct).ConfigureAwait(false);
                long counted = 0;
                try
                {
                    using (var resp = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false))
                    {
                        resp.EnsureSuccessStatusCode();
                        var z = new MemoryStream((int)Math.Max(c.ZSize, 16));
                        using (var s = await resp.Content.ReadAsStreamAsync().ConfigureAwait(false))
                        {
                            var buf = new byte[64 * 1024];
                            int n;
                            while ((n = await s.ReadAsync(buf, 0, buf.Length, ct).ConfigureAwait(false)) > 0)
                            {
                                z.Write(buf, 0, n);
                                Interlocked.Add(ref prog.Downloaded, n);
                                counted += n;
                            }
                        }
                        z.Position = 0;
                        var raw = new byte[c.Size];
                        using (var inf = new DeflateStream(z, CompressionMode.Decompress))
                        {
                            int got = 0;
                            while (got < raw.Length)
                            {
                                int n = inf.Read(raw, got, raw.Length - got);
                                if (n <= 0) break;
                                got += n;
                            }
                            if (got != raw.Length || inf.ReadByte() != -1) throw new InvalidDataException("chunk size");
                        }
                        using (var sha = SHA256.Create())
                            if (Hex.Of(sha.ComputeHash(raw)) != c.Hash) throw new InvalidDataException("chunk hash");
                        return raw;
                    }
                }
                catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
                catch (Exception e)
                {
                    last = e;
                    Interlocked.Add(ref prog.Downloaded, -counted);
                }
            }
            throw new IOException("Could not download part of the game (" + (last?.Message ?? "network error") + "). Check your connection and try again.", last);
        }

        Dictionary<string, object> ReadJournal()
        {
            try { return File.Exists(JournalPath) ? Json.Obj(Json.Parse(File.ReadAllText(JournalPath))) : null; }
            catch (Exception) { return null; }
        }

        void WriteJournal(FileEntry f, int done)
        {
            File.WriteAllText(JournalPath, Json.Write(new Dictionary<string, object> { ["file"] = f.Path, ["sha256"] = f.Sha256, ["done"] = done }));
        }

        static string FileSha(string path, CancellationToken ct)
        {
            using (var sha = SHA256.Create())
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, 1 << 20))
            {
                var buf = new byte[1 << 20];
                int n;
                while ((n = fs.Read(buf, 0, buf.Length)) > 0)
                {
                    ct.ThrowIfCancellationRequested();
                    sha.TransformBlock(buf, 0, n, null, 0);
                }
                sha.TransformFinalBlock(buf, 0, 0);
                return Hex.Of(sha.Hash);
            }
        }

        void Report(UpdateProgress p) => Progress?.Invoke(p);

        // ------------------------------------------------------------------ the launcher itself

        /// <summary>Downloads a newer launcher next to this one; returns its path, or null when this one is current.</summary>
        public async Task<string> FetchNewLauncherAsync(Manifest m, string selfPath, CancellationToken ct)
        {
            var li = m.Launcher;
            if (li == null || !Version.TryParse(li.Version, out var remote) || remote <= Version.Parse(Program.Version)) return null;
            var bytes = await _http.GetByteArrayAsync(Resolve(li.Url)).ConfigureAwait(false);
            using (var sha = SHA256.Create())
                if (bytes.Length != li.Size || Hex.Of(sha.ComputeHash(bytes)) != li.Sha256)
                    throw new InvalidDataException("The launcher update did not match its release.");
            var next = selfPath + ".new";
            File.WriteAllBytes(next, bytes);
            return next;
        }

        public async Task<string> GetStringAsync(string url, CancellationToken ct)
        {
            using (var cts = CancellationTokenSource.CreateLinkedTokenSource(ct))
            {
                cts.CancelAfter(TimeSpan.FromSeconds(8));
                var r = await _http.GetAsync(url, cts.Token).ConfigureAwait(false);
                r.EnsureSuccessStatusCode();
                return await r.Content.ReadAsStringAsync().ConfigureAwait(false);
            }
        }

        public static string Size(long b)
        {
            if (b >= 1L << 30) return (b / (double)(1L << 30)).ToString("0.00") + " GB";
            if (b >= 1L << 20) return (b / (double)(1L << 20)).ToString("0.0") + " MB";
            return Math.Max(1, b / 1024) + " KB";
        }
    }
}
