import AppKit
import Foundation

final class UpdateProgress {
    var phase = ""
    var file = ""
    var done = 0, total = 0          // bytes of game files written / to write
    var downloaded = 0, downloadTotal = 0
    var reused = 0                   // bytes taken from files already on disk
    var speed = 0.0                  // download bytes per second
    let lock = NSLock()
    func addDownloaded(_ n: Int) { lock.lock(); downloaded += n; lock.unlock() }
}

/// Installs and updates the game from signed releases, like the Windows launcher (launcher/windows/src/Updater.cs):
/// every file is rebuilt in order from its chunks; a chunk already on disk is copied once its hash is checked, anything
/// else is downloaded, inflated and checked; files are written beside the old ones and swapped in when their whole hash
/// matches; an interrupted download resumes. Blocking calls, run on a worker thread.
final class Updater {
    static let platform = "macos"
    let releaseURL: URL
    var installDir: URL
    let session: URLSession
    var cancelled = false
    var onProgress: ((UpdateProgress) -> Void)?
    private let parallel = 6, window = 18

    init(baseURL: String, installDir: URL) {
        releaseURL = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/updates/\(Updater.platform)/release.json")!
        self.installDir = installDir
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpMaximumConnectionsPerHost = 8
        cfg.timeoutIntervalForRequest = 60
        cfg.httpAdditionalHeaders = ["User-Agent": "AetherionLauncher/\(appVersion) (macOS)"]
        session = URLSession(configuration: cfg)
    }

    var stateDir: URL { installDir.appendingPathComponent(".launcher") }
    var statePath: URL { stateDir.appendingPathComponent("state.json") }
    var journalPath: URL { stateDir.appendingPathComponent("journal.json") }

    // MARK: http

    func get(_ url: URL, timeout: TimeInterval = 60) throws -> Data {
        var result: Result<Data, Error> = .failure(LauncherError.message("no response"))
        let sem = DispatchSemaphore(value: 0)
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = "GET"
        session.dataTask(with: req) { data, resp, err in
            if let err = err { result = .failure(err) }
            else if let h = resp as? HTTPURLResponse, h.statusCode != 200 { result = .failure(LauncherError.message("HTTP \(h.statusCode) for \(url.lastPathComponent)")) }
            else { result = .success(data ?? Data()) }
            sem.signal()
        }.resume()
        sem.wait()
        return try result.get()
    }

    func resolve(_ relative: String) -> URL { URL(string: relative, relativeTo: releaseURL)!.absoluteURL }

    // MARK: releases

    func fetch() throws -> Manifest {
        var c = URLComponents(url: releaseURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
        let data = try get(c.url!, timeout: 20)
        guard let doc = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = Data(base64Encoded: doc["manifest"] as? String ?? ""), let sig = Data(base64Encoded: doc["sig"] as? String ?? "") else {
            throw LauncherError.message("The release could not be read.")
        }
        guard Signature.verify(raw, sig) else { throw LauncherError.message("The release is not signed by Aetherion Project. Nothing was installed.") }
        let m = try Manifest.parse(raw)
        guard m.platform == Updater.platform else { throw LauncherError.message("The release is for \(m.platform), not macOS.") }
        return m
    }

    // MARK: local state

    struct LocalFile {
        var sha256: String
        var size: Int
        var chunks: [(String, Int, Int)]  // hash, size, offset
    }

    func loadState() -> (String, [String: LocalFile]) {
        guard let d = try? Data(contentsOf: statePath), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return ("", [:]) }
        var files: [String: LocalFile] = [:]
        for (k, v) in o["files"] as? [String: Any] ?? [:] {
            guard let f = v as? [String: Any] else { continue }
            var off = 0
            var ch: [(String, Int, Int)] = []
            for case let c as [Any] in f["chunks"] as? [Any] ?? [] {
                let size = (c[1] as? NSNumber)?.intValue ?? 0
                ch.append((c[0] as? String ?? "", size, off))
                off += size
            }
            files[k] = LocalFile(sha256: f["sha256"] as? String ?? "", size: (f["size"] as? NSNumber)?.intValue ?? 0, chunks: ch)
        }
        return (o["version"] as? String ?? "", files)
    }

    func saveState(_ files: [String: LocalFile], version: String) throws {
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        var fo: [String: Any] = [:]
        for (k, v) in files { fo[k] = ["sha256": v.sha256, "size": v.size, "chunks": v.chunks.map { [$0.0, $0.1] }] }
        let data = try JSONSerialization.data(withJSONObject: ["version": version, "platform": Updater.platform, "files": fo])
        try data.write(to: statePath, options: .atomic)
    }

    func gameApp(_ m: Manifest?) -> URL { installDir.appendingPathComponent(m?.launch ?? "Aetherion Project by Aljay Leodones.app") }

    func installedVersion(_ m: Manifest? = nil) -> String {
        let (v, files) = loadState()
        if v.isEmpty { return "" }
        let launch = m?.launch ?? files.keys.first.map { String($0.split(separator: "/")[0]) } ?? ""
        return FileManager.default.fileExists(atPath: installDir.appendingPathComponent(launch).path) ? v : ""
    }

    func existsWithSize(_ f: FileEntry) -> Bool {
        let p = installDir.appendingPathComponent(f.path).path
        guard let a = try? FileManager.default.attributesOfItem(atPath: p) else { return false }
        return (a[.size] as? NSNumber)?.intValue == f.size
    }

    func pendingDownload(_ m: Manifest) -> Int {
        let (_, state) = loadState()
        var have = Set<String>()
        for (k, v) in state where FileManager.default.fileExists(atPath: installDir.appendingPathComponent(k).path) {
            for c in v.chunks { have.insert(c.0) }
        }
        var n = 0
        for f in m.files where f.link == nil {
            if let lf = state[f.path], lf.sha256 == f.sha256, existsWithSize(f) { continue }
            for c in f.chunks where !have.contains(c.hash) { n += c.zsize }
        }
        return n
    }

    func isGameRunning(_ m: Manifest) -> Bool {
        let app = gameApp(m).standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL.path == app }
    }

    // MARK: install / update

    struct Source { let path: String; let offset: Int; let size: Int }

    func apply(_ m: Manifest, verifyAll: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: stateDir, withIntermediateDirectories: true)
        var (_, state) = loadState()
        let prog = UpdateProgress()
        prog.phase = verifyAll ? "Checking files" : "Preparing"
        report(prog)
        var todo: [FileEntry] = []
        for f in m.files {
            if let link = f.link {
                let p = installDir.appendingPathComponent(f.path)
                if (try? fm.destinationOfSymbolicLink(atPath: p.path)) != link {
                    try? fm.removeItem(at: p)
                    try fm.createDirectory(at: p.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.createSymbolicLink(atPath: p.path, withDestinationPath: link)
                }
                continue
            }
            var ok = state[f.path].map { $0.sha256 == f.sha256 } ?? false && existsWithSize(f)
            if ok && verifyAll {
                prog.phase = "Checking \(f.path)"
                report(prog)
                ok = try fileSha(installDir.appendingPathComponent(f.path)) == f.sha256
            }
            if !ok { todo.append(f) }
        }
        var sources: [String: [Source]] = [:]
        for (k, v) in state {
            let p = installDir.appendingPathComponent(k).path
            if fm.fileExists(atPath: p) { for c in v.chunks { sources[c.0, default: []].append(Source(path: p, offset: c.2, size: c.1)) } }
        }
        for f in m.files where f.link == nil && state[f.path] == nil {
            let p = installDir.appendingPathComponent(f.path).path
            if fm.fileExists(atPath: p) { for c in f.chunks { sources[c.hash, default: []].append(Source(path: p, offset: c.offset, size: c.size)) } }
        }
        prog.total = todo.reduce(0) { $0 + $1.size }
        prog.downloadTotal = todo.reduce(0) { $0 + $1.chunks.filter { sources[$0.hash] == nil }.reduce(0) { $0 + $1.zsize } }
        let need = (todo.map { $0.size }.max() ?? 0) + 64 << 20
        if let free = try? installDir.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free > 0, Int(free) < need {
            throw LauncherError.message("Not enough disk space: \(formatSize(need)) needed, \(formatSize(Int(free))) free.")
        }
        if !todo.isEmpty && isGameRunning(m) { throw LauncherError.message("Quit Aetherion first: the game is still running.") }
        var mark = Date(), markBytes = 0
        for f in todo {
            if cancelled { throw Cancelled() }
            prog.file = f.path
            prog.phase = "Installing"
            try writeFile(m, f, sources: sources, prog: prog) {
                let dt = Date().timeIntervalSince(mark)
                if dt >= 0.5 {
                    let inst = Double(prog.downloaded - markBytes) / dt
                    prog.speed = prog.speed <= 0 ? inst : prog.speed * 0.7 + inst * 0.3
                    mark = Date()
                    markBytes = prog.downloaded
                }
                self.report(prog)
            }
            state[f.path] = LocalFile(sha256: f.sha256, size: f.size, chunks: f.chunks.map { ($0.hash, $0.size, $0.offset) })
            try saveState(state, version: "")
        }
        let keep = Set(m.files.map { $0.path })
        for old in state.keys where !keep.contains(old) {
            try? fm.removeItem(at: installDir.appendingPathComponent(old))
            state[old] = nil
        }
        try saveState(state, version: m.version)
        try? fm.removeItem(at: journalPath)
        prog.phase = "Done"
        prog.done = prog.total
        report(prog)
    }

    private func writeFile(_ m: Manifest, _ f: FileEntry, sources: [String: [Source]], prog: UpdateProgress, tick: () -> Void) throws {
        let fm = FileManager.default
        let target = installDir.appendingPathComponent(f.path)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = URL(fileURLWithPath: target.path + ".download")
        var start = 0, startBytes = 0
        if let jd = try? Data(contentsOf: journalPath), let j = try? JSONSerialization.jsonObject(with: jd) as? [String: Any],
           j["file"] as? String == f.path, j["sha256"] as? String == f.sha256, fm.fileExists(atPath: tmp.path) {
            start = (j["done"] as? NSNumber)?.intValue ?? 0
            if start > 0 && start <= f.chunks.count { startBytes = f.chunks[start - 1].offset + f.chunks[start - 1].size }
            let have = ((try? fm.attributesOfItem(atPath: tmp.path))?[.size] as? NSNumber)?.intValue ?? 0
            if have < startBytes { start = 0; startBytes = 0 }
        }
        if start == 0 { fm.createFile(atPath: tmp.path, contents: nil) }
        guard let out = FileHandle(forUpdatingAtPath: tmp.path) else { throw LauncherError.message("Cannot write \(tmp.path)") }
        defer { try? out.close() }
        let sha = Sha256()
        if start > 0 {
            var left = startBytes
            while left > 0 {
                let d = out.readData(ofLength: min(1 << 20, left))
                if d.isEmpty { throw LauncherError.message("Could not read the partial download.") }
                sha.update(d)
                left -= d.count
            }
            out.truncateFile(atOffset: UInt64(startBytes))
            prog.done += startBytes
        } else {
            out.truncateFile(atOffset: 0)
        }
        let chunksBase = resolve(m.chunksBase)
        // Downloads run ahead of the writer, in parallel; the writer takes them in order.
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = parallel
        let lock = NSLock()
        var results: [Int: Result<Data, Error>] = [:]
        var started = Set<Int>()
        let ready = NSCondition()
        func fetch(_ i: Int) {
            started.insert(i)
            let c = f.chunks[i]
            queue.addOperation {
                let r = Result { try self.downloadChunk(chunksBase, c, prog) }
                ready.lock(); lock.lock(); results[i] = r; lock.unlock(); ready.broadcast(); ready.unlock()
            }
        }
        defer { queue.cancelAllOperations() }
        var sinceFlush = 0
        var i = start
        while i < f.chunks.count {
            if cancelled { throw Cancelled() }
            for k in i..<min(f.chunks.count, i + window) where !started.contains(k) && sources[f.chunks[k].hash] == nil { fetch(k) }
            let c = f.chunks[i]
            var data: Data?
            if !started.contains(i), let srcs = sources[c.hash] {
                for s in srcs { if let d = readLocal(s, c.hash) { data = d; break } }
                if let d = data { prog.reused += d.count } else { fetch(i) }
            }
            if data == nil {
                ready.lock()
                while true {
                    lock.lock(); let r = results[i]; lock.unlock()
                    if r != nil || cancelled { break }
                    ready.wait(until: Date().addingTimeInterval(0.25))
                }
                ready.unlock()
                if cancelled { throw Cancelled() }
                lock.lock(); let r = results.removeValue(forKey: i)!; lock.unlock()
                data = try r.get()
            }
            out.write(data!)
            sha.update(data!)
            prog.done += data!.count
            sinceFlush += data!.count
            if sinceFlush >= 48 << 20 || i == f.chunks.count - 1 {
                out.synchronizeFile()
                let j = try JSONSerialization.data(withJSONObject: ["file": f.path, "sha256": f.sha256, "done": i + 1])
                try j.write(to: journalPath, options: .atomic)
                sinceFlush = 0
            }
            tick()
            i += 1
        }
        let size = Int(out.seekToEndOfFile())
        if sha.hex() != f.sha256 || size != f.size {
            try? fm.removeItem(at: tmp)
            try? fm.removeItem(at: journalPath)
            throw LauncherError.message("A downloaded file did not match its release (\(f.path)). Try again.")
        }
        try? out.close()
        try fm.setAttributes([.posixPermissions: f.exec ? 0o755 : 0o644], ofItemAtPath: tmp.path)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: tmp, to: target)
    }

    private func readLocal(_ s: Source, _ hash: String) -> Data? {
        guard let h = FileHandle(forReadingAtPath: s.path) else { return nil }
        defer { try? h.close() }
        let end = h.seekToEndOfFile()
        if end < UInt64(s.offset + s.size) { return nil }
        h.seek(toFileOffset: UInt64(s.offset))
        let d = h.readData(ofLength: s.size)
        return d.count == s.size && Sha256.hex(d) == hash ? d : nil
    }

    private func downloadChunk(_ base: URL, _ c: ChunkRef, _ prog: UpdateProgress) throws -> Data {
        let url = base.appendingPathComponent(String(c.hash.prefix(2))).appendingPathComponent(c.hash)
        var last: Error = LauncherError.message("network error")
        for attempt in 0..<6 {
            if cancelled { throw Cancelled() }
            if attempt > 0 { Thread.sleep(forTimeInterval: Double(min(20, 1 << attempt))) }
            do {
                let z = try get(url)
                prog.addDownloaded(z.count)
                guard let raw = inflate(z, size: c.size), Sha256.hex(raw) == c.hash else {
                    prog.addDownloaded(-z.count)
                    throw LauncherError.message("chunk check failed")
                }
                return raw
            } catch { last = error }
        }
        throw LauncherError.message("Could not download part of the game (\(last.localizedDescription)). Check your connection and try again.")
    }

    private func fileSha(_ url: URL) throws -> String {
        guard let h = FileHandle(forReadingAtPath: url.path) else { return "" }
        defer { try? h.close() }
        let sha = Sha256()
        while true {
            if cancelled { throw Cancelled() }
            let d = h.readData(ofLength: 1 << 20)
            if d.isEmpty { break }
            sha.update(d)
        }
        return sha.hex()
    }

    private func report(_ p: UpdateProgress) { onProgress?(p) }

    // MARK: the launcher itself

    /// A newer launcher, downloaded and checked, unpacked next to this one: its .app URL, or nil when current.
    func fetchNewLauncher(_ m: Manifest) throws -> URL? {
        guard let li = m.launcher, versionLess(appVersion, li.version) else { return nil }
        let data = try get(resolve(li.url))
        guard data.count == li.size, Sha256.hex(data) == li.sha256 else { throw LauncherError.message("The launcher update did not match its release.") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aetherion-launcher-\(li.version)")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let zip = dir.appendingPathComponent("launcher.zip")
        try data.write(to: zip)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        try p.run()
        p.waitUntilExit()
        let app = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first { $0.pathExtension == "app" }
        return app
    }
}

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

func versionLess(_ a: String, _ b: String) -> Bool {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(x.count, y.count) {
        let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
        if p != q { return p < q }
    }
    return false
}
