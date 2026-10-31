using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

namespace Aetherion.Launcher
{
    /// <summary>One chunk of a file: its SHA-256, raw size, compressed size and offset in the file.</summary>
    sealed class ChunkRef
    {
        public string Hash;
        public long Size;
        public long ZSize;
        public long Offset;
    }

    sealed class FileEntry
    {
        public string Path;
        public long Size;
        public string Sha256;
        public bool Exec;
        public string Link;
        public List<ChunkRef> Chunks = new List<ChunkRef>();
    }

    sealed class LauncherInfo
    {
        public string Version;
        public string Url;
        public string Sha256;
        public long Size;
    }

    /// <summary>A signed release of one platform (tools/release/publish.py writes it).</summary>
    sealed class Manifest
    {
        public string Platform, Version, NetVersion, Published, Launch, ChunksBase;
        public long Size, DownloadSize;
        public List<string> Notes = new List<string>();
        public List<FileEntry> Files = new List<FileEntry>();
        public LauncherInfo Launcher;
        public byte[] Raw;

        public static Manifest Parse(byte[] raw)
        {
            var d = Json.Obj(Json.Parse(Encoding.UTF8.GetString(raw)));
            if (Json.Long(d, "format") != 1)
                throw new InvalidDataException("This launcher is too old for the published release. Download the latest launcher from the website.");
            var m = new Manifest
            {
                Raw = raw,
                Platform = Json.Str(d, "platform"),
                Version = Json.Str(d, "version"),
                NetVersion = Json.Str(d, "net_version"),
                Published = Json.Str(d, "published"),
                Launch = Json.Str(d, "launch"),
                ChunksBase = Json.Str(d, "chunks"),
                Size = Json.Long(d, "size"),
                DownloadSize = Json.Long(d, "download_size"),
            };
            foreach (var n in Json.Arr(d, "notes")) m.Notes.Add(Convert.ToString(n));
            foreach (var fo in Json.Arr(d, "files"))
            {
                var f = Json.Obj(fo);
                var e = new FileEntry
                {
                    Path = Json.Str(f, "path"),
                    Size = Json.Long(f, "size"),
                    Sha256 = Json.Str(f, "sha256"),
                    Exec = f.ContainsKey("exec") && Convert.ToBoolean(f["exec"]),
                    Link = f.ContainsKey("link") ? Convert.ToString(f["link"]) : null,
                };
                if (!SafePath(e.Path)) throw new InvalidDataException("Unsafe path in release: " + e.Path);
                long off = 0;
                foreach (var co in Json.Arr(f, "chunks"))
                {
                    var c = (object[])co;
                    var cr = new ChunkRef { Hash = Convert.ToString(c[0]), Size = Convert.ToInt64(c[1]), ZSize = Convert.ToInt64(c[2]), Offset = off };
                    off += cr.Size;
                    e.Chunks.Add(cr);
                }
                if (e.Link == null && off != e.Size) throw new InvalidDataException("Chunk sizes do not add up for " + e.Path);
                m.Files.Add(e);
            }
            if (d.ContainsKey("launcher"))
            {
                var l = Json.Obj(d["launcher"]);
                m.Launcher = new LauncherInfo { Version = Json.Str(l, "version"), Url = Json.Str(l, "url"), Sha256 = Json.Str(l, "sha256"), Size = Json.Long(l, "size") };
            }
            return m;
        }

        static bool SafePath(string p)
        {
            if (string.IsNullOrEmpty(p) || p.StartsWith("/") || p.StartsWith("\\") || p.Contains(":")) return false;
            foreach (var part in p.Split('/', '\\'))
                if (part == ".." || part == "") return false;
            return true;
        }
    }

    static class Signature
    {
        static RSAParameters? _key;

        static RSAParameters Key()
        {
            if (_key == null)
            {
                using (var s = typeof(Signature).Assembly.GetManifestResourceStream("update-public-key.json"))
                using (var r = new StreamReader(s))
                {
                    var d = Json.Obj(Json.Parse(r.ReadToEnd()));
                    _key = new RSAParameters { Modulus = Convert.FromBase64String(Json.Str(d, "modulus")), Exponent = Convert.FromBase64String(Json.Str(d, "exponent")) };
                }
            }
            return _key.Value;
        }

        /// <summary>RSA PKCS#1 v1.5 SHA-256 over the exact manifest bytes, against the pinned public key.</summary>
        public static bool Verify(byte[] data, byte[] sig)
        {
            using (var rsa = new RSACng())
            {
                rsa.ImportParameters(Key());
                return rsa.VerifyData(data, sig, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
            }
        }
    }

    static class Json
    {
        static readonly JavaScriptSerializer S = new JavaScriptSerializer { MaxJsonLength = 64 * 1024 * 1024, RecursionLimit = 64 };

        public static object Parse(string text) => S.DeserializeObject(text);
        public static string Write(object o) => S.Serialize(o);

        public static Dictionary<string, object> Obj(object o) =>
            o as Dictionary<string, object> ?? throw new InvalidDataException("Expected a JSON object");

        public static string Str(Dictionary<string, object> d, string k) => d.TryGetValue(k, out var v) && v != null ? Convert.ToString(v) : "";

        public static long Long(Dictionary<string, object> d, string k) => d.TryGetValue(k, out var v) && v != null ? Convert.ToInt64(v) : 0;

        public static IEnumerable Arr(Dictionary<string, object> d, string k) =>
            d.TryGetValue(k, out var v) && v is IEnumerable e && !(v is string) ? e : new object[0];
    }

    static class Hex
    {
        public static string Of(byte[] b)
        {
            var sb = new StringBuilder(b.Length * 2);
            foreach (var x in b) sb.Append(x.ToString("x2"));
            return sb.ToString();
        }
    }
}
