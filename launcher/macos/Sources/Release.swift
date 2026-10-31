import CommonCrypto
import Compression
import Foundation
import Security

/// One chunk of a file: SHA-256 of its raw bytes, raw size, compressed size, offset in the file.
struct ChunkRef {
    let hash: String
    let size: Int
    let zsize: Int
    let offset: Int
}

struct FileEntry {
    let path: String
    let size: Int
    let sha256: String
    let exec: Bool
    let link: String?
    let chunks: [ChunkRef]
}

struct LauncherInfo {
    let version: String
    let url: String
    let sha256: String
    let size: Int
}

enum LauncherError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

/// A signed release of one platform (tools/release/publish.py writes it; docs/HOSTING.md).
struct Manifest {
    let platform, version, published, launch, chunksBase: String
    let size, downloadSize: Int
    let notes: [String]
    let files: [FileEntry]
    let launcher: LauncherInfo?

    static func parse(_ raw: Data) throws -> Manifest {
        guard let d = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else { throw LauncherError.message("The release is not readable.") }
        guard (d["format"] as? Int) == 1 else {
            throw LauncherError.message("This launcher is too old for the published release. Download the latest launcher from the website.")
        }
        var files: [FileEntry] = []
        for case let f as [String: Any] in d["files"] as? [Any] ?? [] {
            let path = f["path"] as? String ?? ""
            guard safePath(path) else { throw LauncherError.message("Unsafe path in release: \(path)") }
            var off = 0
            var chunks: [ChunkRef] = []
            for case let c as [Any] in f["chunks"] as? [Any] ?? [] {
                let size = (c[1] as? NSNumber)?.intValue ?? 0
                chunks.append(ChunkRef(hash: c[0] as? String ?? "", size: size, zsize: (c[2] as? NSNumber)?.intValue ?? 0, offset: off))
                off += size
            }
            let link = f["link"] as? String
            let size = (f["size"] as? NSNumber)?.intValue ?? 0
            if link == nil && off != size { throw LauncherError.message("Chunk sizes do not add up for \(path)") }
            files.append(FileEntry(path: path, size: size, sha256: f["sha256"] as? String ?? "", exec: f["exec"] as? Bool ?? false, link: link, chunks: chunks))
        }
        var li: LauncherInfo?
        if let l = d["launcher"] as? [String: Any] {
            li = LauncherInfo(version: l["version"] as? String ?? "0", url: l["url"] as? String ?? "", sha256: l["sha256"] as? String ?? "",
                              size: (l["size"] as? NSNumber)?.intValue ?? 0)
        }
        return Manifest(platform: d["platform"] as? String ?? "", version: d["version"] as? String ?? "", published: d["published"] as? String ?? "",
                        launch: d["launch"] as? String ?? "", chunksBase: d["chunks"] as? String ?? "../chunks/",
                        size: (d["size"] as? NSNumber)?.intValue ?? 0, downloadSize: (d["download_size"] as? NSNumber)?.intValue ?? 0,
                        notes: d["notes"] as? [String] ?? [], files: files, launcher: li)
    }

    static func safePath(_ p: String) -> Bool {
        if p.isEmpty || p.hasPrefix("/") || p.contains("\\") { return false }
        return !p.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0.isEmpty }
    }
}

enum Signature {
    /// RSA PKCS#1 v1.5 SHA-256 over the exact manifest bytes, against the pinned public key.
    static func verify(_ data: Data, _ sig: Data) -> Bool {
        guard let url = Bundle.main.url(forResource: "update-public-key", withExtension: "json"),
              let kd = try? Data(contentsOf: url),
              let k = try? JSONSerialization.jsonObject(with: kd) as? [String: Any],
              let b64 = k["pkcs1_der"] as? String, let der = Data(base64Encoded: b64) else { return false }
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        var err: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &err) else { return false }
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, sig as CFData, &err)
    }
}

/// Incremental SHA-256 (CommonCrypto, every macOS version).
final class Sha256 {
    private var ctx = CC_SHA256_CTX()
    init() { CC_SHA256_Init(&ctx) }
    func update(_ d: Data) {
        d.withUnsafeBytes { p in _ = CC_SHA256_Update(&ctx, p.baseAddress, CC_LONG(d.count)) }
    }
    func hex() -> String {
        var out = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&out, &ctx)
        return out.map { String(format: "%02x", $0) }.joined()
    }
    static func hex(_ d: Data) -> String {
        let s = Sha256()
        s.update(d)
        return s.hex()
    }
}

/// Raw DEFLATE (RFC 1951): Apple's COMPRESSION_ZLIB is exactly that, without a zlib header.
func inflate(_ z: Data, size: Int) -> Data? {
    if size == 0 { return Data() }
    var out = Data(count: size)
    let n = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
        z.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                      src.bindMemory(to: UInt8.self).baseAddress!, z.count, nil, COMPRESSION_ZLIB)
        }
    }
    return n == size ? out : nil
}

func formatSize(_ b: Int) -> String {
    if b >= 1 << 30 { return String(format: "%.2f GB", Double(b) / Double(1 << 30)) }
    if b >= 1 << 20 { return String(format: "%.1f MB", Double(b) / Double(1 << 20)) }
    return "\(max(1, b / 1024)) KB"
}

/// The player paused the download.
struct Cancelled: Error {}
