import AppKit
import CoreText
import Foundation

// Aetherion Project launcher for macOS (launcher/README.md): the same window, release format and update engine as the
// Windows launcher. Built on a Mac by launcher/macos/build.sh (GitHub Actions: .github/workflows/mac-launcher.yml).

let baseURL = argValue("base-url") ?? "https://aetherion.15-235-246-87.sslip.io"
let website = baseURL + "/"

func argValue(_ key: String) -> String? {
    for a in CommandLine.arguments where a.hasPrefix("--\(key)") {
        if a == "--\(key)" { return "true" }
        if a.hasPrefix("--\(key)=") { return String(a.dropFirst(key.count + 3)) }
    }
    return nil
}

var supportDir: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aetherion Project")
}

var settingsURL: URL { supportDir.appendingPathComponent("launcher-settings.json") }

var savedInstallDir: URL {
    get {
        if let d = try? Data(contentsOf: settingsURL), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let p = o["install_dir"] as? String, !p.isEmpty { return URL(fileURLWithPath: p) }
        return supportDir.appendingPathComponent("Game")
    }
    set {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: ["install_dir": newValue.path]) { try? d.write(to: settingsURL) }
    }
}

// MARK: - command line self test

/// --selftest --install-dir=X [--report=F] [--verify] [--launch-check]: install or update without a window, write a JSON
/// report; --launch-check also starts the installed game headless for a few seconds (CI).
func selfTest() -> Int32 {
    var report: [String: Any] = ["launcher": appVersion, "ok": false]
    let t0 = Date()
    do {
        let dir = URL(fileURLWithPath: argValue("install-dir") ?? NSTemporaryDirectory() + "aetherion-selftest")
        let u = Updater(baseURL: baseURL, installDir: dir)
        var last: UpdateProgress?
        u.onProgress = { last = $0 }
        let m = try u.fetch()
        report["version"] = m.version
        report["before"] = u.installedVersion(m)
        report["pending_download"] = u.pendingDownload(m)
        try u.apply(m, verifyAll: argValue("verify") != nil)
        report["after"] = u.installedVersion(m)
        report["downloaded"] = last?.downloaded ?? 0
        report["reused"] = last?.reused ?? 0
        report["written"] = last?.done ?? 0
        let app = u.gameApp(m)
        report["game_app"] = FileManager.default.fileExists(atPath: app.path)
        var ok = report["after"] as? String == m.version && report["game_app"] as? Bool == true
        if argValue("launch-check") != nil, let bin = Bundle(url: app)?.executableURL {
            let p = Process()
            p.executableURL = bin
            p.arguments = ["--headless", "--quit-after", "600"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            try p.run()
            let out = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(data: out, encoding: .utf8) ?? ""
            report["launch_exit"] = Int(p.terminationStatus)
            report["launch_log"] = String(text.suffix(1500))
            ok = ok && p.terminationStatus == 0 && text.contains("Godot Engine")
        }
        report["ok"] = ok
    } catch {
        report["error"] = "\(error.localizedDescription)"
    }
    report["seconds"] = (Date().timeIntervalSince(t0) * 10).rounded() / 10
    let data = (try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])) ?? Data()
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    if let r = argValue("report") { try? data.write(to: URL(fileURLWithPath: r)) }
    return report["ok"] as? Bool == true ? 0 : 1
}

// MARK: - look

enum Theme {
    static let bg = NSColor(srgbRed: 10 / 255, green: 12 / 255, blue: 15 / 255, alpha: 1)
    static let panel = NSColor(srgbRed: 12 / 255, green: 15 / 255, blue: 19 / 255, alpha: 0.8)
    static let line = NSColor(white: 1, alpha: 0.11)
    static let text = NSColor(srgbRed: 235 / 255, green: 237 / 255, blue: 230 / 255, alpha: 1)
    static let dim = NSColor(srgbRed: 153 / 255, green: 163 / 255, blue: 163 / 255, alpha: 1)
    static let accent = NSColor(srgbRed: 242 / 255, green: 163 / 255, blue: 59 / 255, alpha: 1)
    static let accentHot = NSColor(srgbRed: 1, green: 189 / 255, blue: 102 / 255, alpha: 1)
    static let accent2 = NSColor(srgbRed: 77 / 255, green: 199 / 255, blue: 184 / 255, alpha: 1)
    static let danger = NSColor(srgbRed: 235 / 255, green: 92 / 255, blue: 82 / 255, alpha: 1)
    static let good = NSColor(srgbRed: 122 / 255, green: 214 / 255, blue: 133 / 255, alpha: 1)

    static func registerFonts() {
        for name in ["BarlowCondensed-SemiBold", "Barlow-Regular", "Barlow-SemiBold"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    static func font(_ name: String, _ size: CGFloat) -> NSFont { NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: .semibold) }
    static func condensed(_ s: CGFloat) -> NSFont { font("BarlowCondensed-SemiBold", s) }
    static func regular(_ s: CGFloat) -> NSFont { font("Barlow-Regular", s) }
    static func semi(_ s: CGFloat) -> NSFont { font("Barlow-SemiBold", s) }
}

@discardableResult
func drawText(_ s: String, _ font: NSFont, _ color: NSColor, _ x: CGFloat, _ y: CGFloat, kern: CGFloat = 0) -> CGFloat {
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    a.draw(at: NSPoint(x: x, y: y))
    return a.size().width - kern
}

func textWidth(_ s: String, _ font: NSFont, kern: CGFloat = 0) -> CGFloat {
    NSAttributedString(string: s, attributes: [.font: font, .kern: kern]).size().width - kern
}

func drawRight(_ s: String, _ font: NSFont, _ color: NSColor, _ right: CGFloat, _ y: CGFloat, kern: CGFloat = 0) {
    drawText(s, font, color, right - textWidth(s, font, kern: kern), y, kern: kern)
}

func drawWrapped(_ s: String, _ font: NSFont, _ color: NSColor, _ r: NSRect) {
    let p = NSMutableParagraphStyle()
    p.lineBreakMode = .byWordWrapping
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
    a.draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
}

func wrappedHeight(_ s: String, _ font: NSFont, _ w: CGFloat) -> CGFloat {
    NSAttributedString(string: s, attributes: [.font: font]).boundingRect(with: NSSize(width: w, height: 10000), options: [.usesLineFragmentOrigin]).height
}

func fill(_ r: NSRect, _ radius: CGFloat, _ c: NSColor) {
    c.setFill()
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
}

func stroke(_ r: NSRect, _ radius: CGFloat, _ c: NSColor, _ w: CGFloat = 1) {
    c.setStroke()
    let p = NSBezierPath(roundedRect: r.insetBy(dx: w / 2, dy: w / 2), xRadius: radius, yRadius: radius)
    p.lineWidth = w
    p.stroke()
}

// MARK: - window

enum Mode { case checking, install, update, ready, working, error, playing }

final class LauncherView: NSView {
    static let W: CGFloat = 1180, H: CGFloat = 680
    let M: CGFloat = 64, btnW: CGFloat = 280, btnH: CGFloat = 80
    let u = Updater(baseURL: baseURL, installDir: savedInstallDir)
    var remote: Manifest?
    var mode: Mode = .checking
    var status = "Checking for updates…", detail = "Connecting to the Aetherion servers"
    var statusColor = Theme.text
    var progress: UpdateProgress?
    var offline = false
    var servers: [[String: Any]]?
    var serversUp: Bool?
    var onlineCount = 0
    var hit: [String: NSRect] = [:]
    var hover: String?, pressed: String?
    var tick = 0
    var game: Process?
    let art = Bundle.main.image(forResource: "background")
    let icon = NSImage(named: NSImage.applicationIconName)
    let fTitle = Theme.condensed(104), fSub = Theme.condensed(38), fBtn = Theme.condensed(34), fHead = Theme.semi(13),
        fBody = Theme.regular(15.5), fBodyB = Theme.semi(15.5), fStatus = Theme.semi(21), fSmall = Theme.regular(13.5), fBy = Theme.regular(21)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func start() {
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick += 1; self?.needsDisplay = true }
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.poll() }
        refreshServers()
        check()
    }

    // MARK: state

    func set(_ m: Mode, _ s: String, _ d: String, _ color: NSColor = Theme.text) {
        DispatchQueue.main.async {
            self.mode = m
            self.status = s
            self.detail = d
            self.statusColor = color
            self.needsDisplay = true
        }
    }

    func background(_ work: @escaping () -> Void) { Thread { work() }.start() }

    func check(quiet: Bool = false) {
        if !quiet { set(.checking, "Checking for updates…", "Connecting to the Aetherion servers") }
        background {
            do {
                let m = try self.u.fetch()
                DispatchQueue.main.async { self.remote = m; self.offline = false }
                if let next = try? self.u.fetchNewLauncher(m) { self.replaceLauncher(next); return }
                self.showLocalState(m)
            } catch {
                DispatchQueue.main.async { self.offline = true }
                let have = self.u.installedVersion()
                if !have.isEmpty {
                    self.set(.ready, "Ready to play", "Offline: the update server cannot be reached (\(error.localizedDescription)). You can still play version \(have).")
                } else if !quiet {
                    self.set(.error, "Can't reach the Aetherion servers", "\(error.localizedDescription) Check your internet connection, then try again.", Theme.danger)
                }
            }
        }
    }

    func replaceLauncher(_ next: URL) {
        let me = Bundle.main.bundleURL
        if me.path.contains("/AppTranslocation/") || !FileManager.default.isWritableFile(atPath: me.deletingLastPathComponent().path) {
            if let m = remote { showLocalState(m) }
            DispatchQueue.main.async { self.detail = "A new launcher is available: move Aetherion Launcher to Applications to let it update itself." }
            return
        }
        do {
            let old = me.deletingLastPathComponent().appendingPathComponent(".AetherionLauncher-old.app")
            try? FileManager.default.removeItem(at: old)
            try FileManager.default.moveItem(at: me, to: old)
            try FileManager.default.moveItem(at: next, to: me)
            try? FileManager.default.removeItem(at: old)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-n", me.path]
            try p.run()
            DispatchQueue.main.async { NSApp.terminate(nil) }
        } catch {
            if let m = remote { showLocalState(m) }
        }
    }

    func showLocalState(_ m: Manifest) {
        let have = u.installedVersion(m)
        if let g = game, g.isRunning {
            set(.playing, "Aetherion is running", have != m.version ? "Update \(m.version) is ready: quit the game to install it." : "Have a good match.")
        } else if have.isEmpty {
            set(.install, "Ready to install", "Version \(m.version) · \(formatSize(u.pendingDownload(m))) download · \(formatSize(m.size)) on disk")
        } else if have != m.version {
            set(.update, "Update available", "Version \(have) → \(m.version) · \(formatSize(max(u.pendingDownload(m), 1))) to download")
        } else {
            set(.ready, "Ready to play", "Version \(m.version) is installed and up to date.")
        }
    }

    func runUpdate(verify: Bool) {
        guard let m = remote else { check(); return }
        u.cancelled = false
        progress = nil
        set(.working, verify ? "Checking game files…" : (u.installedVersion(m).isEmpty ? "Installing Aetherion…" : "Updating Aetherion…"), "Starting")
        u.onProgress = { p in DispatchQueue.main.async { self.progress = p } }
        background {
            do {
                try self.u.apply(m, verifyAll: verify)
                savedInstallDir = self.u.installDir
                self.showLocalState(m)
                DispatchQueue.main.async { NSApp.requestUserAttention(.informationalRequest) }
            } catch is Cancelled {
                self.set(.error, "Paused", "The download stopped. Choose RESUME to continue where it left off.", Theme.accent)
            } catch {
                self.set(.error, "Something went wrong", error.localizedDescription, Theme.danger)
            }
        }
    }

    func launch() {
        guard let m = remote ?? nil else { return }
        let app = u.gameApp(m)
        guard FileManager.default.fileExists(atPath: app.path) else { check(); return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-W", "-n", app.path]   // -W: returns when the game quits
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.game = nil
                self.window?.deminiaturize(nil)
                NSApp.activate(ignoringOtherApps: true)
                self.check(quiet: true)
            }
        }
        do {
            try p.run()
            game = p
            set(.playing, "Aetherion is running", "Have a good match.")
            window?.miniaturize(nil)
        } catch {
            set(.error, "The game did not start", error.localizedDescription, Theme.danger)
        }
    }

    var pollCount = 0
    func poll() {
        pollCount += 1
        refreshServers()
        if pollCount % 15 == 0 && (mode == .ready || mode == .playing || offline) { check(quiet: true) }
    }

    func refreshServers() {
        background {
            if let d = try? self.u.get(URL(string: baseURL + "/api/status")!, timeout: 8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                let s = o["servers"] as? [[String: Any]] ?? []
                DispatchQueue.main.async {
                    self.servers = s
                    self.onlineCount = (o["online"] as? NSNumber)?.intValue ?? 0
                    self.serversUp = !s.isEmpty
                }
            } else {
                DispatchQueue.main.async { self.serversUp = false; self.servers = nil }
            }
        }
    }

    // MARK: input

    func hitAt(_ e: NSEvent) -> String? {
        let p = convert(e.locationInWindow, from: nil)
        return hit.first { $0.value.contains(p) }?.key
    }

    override func mouseMoved(with e: NSEvent) {
        let h = hitAt(e)
        if h != hover { hover = h; needsDisplay = true }
        (h != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func mouseExited(with e: NSEvent) { hover = nil; needsDisplay = true }

    override func mouseDown(with e: NSEvent) {
        pressed = hitAt(e)
        if pressed == nil { window?.performDrag(with: e) }
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        let h = hitAt(e)
        let was = pressed
        pressed = nil
        needsDisplay = true
        guard let id = h, id == was else { return }
        switch id {
        case "main": mainButton()
        case "change": changeFolder()
        case "folder": NSWorkspace.shared.open(u.installDir)
        case "verify": if mode == .ready || mode == .update || mode == .error { runUpdate(verify: true) }
        case "website": NSWorkspace.shared.open(URL(string: website)!)
        case "uninstall": uninstall()
        default: break
        }
    }

    func mainButton() {
        switch mode {
        case .install, .update: runUpdate(verify: false)
        case .ready: launch()
        case .working: u.cancelled = true
        case .error: if remote != nil && status == "Paused" { runUpdate(verify: false) } else { check() }
        default: break
        }
    }

    func changeFolder() {
        guard mode != .working && mode != .playing else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose where to install Aetherion Project. A folder named \"Aetherion Project\" is made inside it."
        guard panel.runModal() == .OK, var dir = panel.url else { return }
        if dir.lastPathComponent != "Aetherion Project" { dir = dir.appendingPathComponent("Aetherion Project") }
        if !u.installedVersion(remote).isEmpty && dir.standardizedFileURL != u.installDir.standardizedFileURL {
            let a = NSAlert()
            a.messageText = "Move the installed game to \(dir.path)?"
            a.addButton(withTitle: "Move")
            a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
            do {
                if FileManager.default.fileExists(atPath: dir.path) {
                    if !((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.isEmpty ?? true) {
                        throw LauncherError.message("That folder is not empty.")
                    }
                    try FileManager.default.removeItem(at: dir)
                }
                try FileManager.default.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: u.installDir, to: dir)
            } catch {
                let e = NSAlert()
                e.messageText = "The game could not be moved: \(error.localizedDescription)"
                e.runModal()
                return
            }
        }
        u.installDir = dir
        savedInstallDir = dir
        if let m = remote { showLocalState(m) }
        needsDisplay = true
    }

    func uninstall() {
        guard mode != .working else { return }
        let a = NSAlert()
        a.messageText = "Remove Aetherion Project from this Mac?"
        a.informativeText = "Game files in \(u.installDir.path) are deleted. Your profile, outfits and settings are kept. Afterwards, drag Aetherion Launcher to the Trash."
        a.addButton(withTitle: "Remove")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let (_, files) = u.loadState()
        for k in files.keys where Manifest.safePath(k) { try? FileManager.default.removeItem(at: u.installDir.appendingPathComponent(k)) }
        for k in Set(files.keys.compactMap { $0.split(separator: "/").first.map(String.init) }) where k.hasSuffix(".app") {
            try? FileManager.default.removeItem(at: u.installDir.appendingPathComponent(k))
        }
        try? FileManager.default.removeItem(at: u.stateDir)
        if (try? FileManager.default.contentsOfDirectory(atPath: u.installDir.path))?.isEmpty ?? false { try? FileManager.default.removeItem(at: u.installDir) }
        check()
    }

    // MARK: drawing (top-left origin, 1180x680 points)

    func hot(_ id: String) -> Bool { hover == id }

    override func draw(_ dirty: NSRect) {
        let W = LauncherView.W, H = LauncherView.H
        Theme.bg.setFill()
        bounds.fill()
        if let art = art {
            let sc = max(W / art.size.width, H / art.size.height)
            let iw = art.size.width * sc, ih = art.size.height * sc
            art.draw(in: NSRect(x: (W - iw) * 0.7, y: (H - ih) * 0.3, width: iw, height: ih), from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: nil)
        }
        let shade = NSColor(srgbRed: 7 / 255, green: 9 / 255, blue: 12 / 255, alpha: 1)
        NSGradient(colors: [shade.withAlphaComponent(0.93), shade.withAlphaComponent(0.75), shade.withAlphaComponent(0.16), shade.withAlphaComponent(0.04)],
                   atLocations: [0, 0.36, 0.72, 1], colorSpace: .sRGB)?.draw(in: bounds, angle: 0)
        NSGradient(starting: shade.withAlphaComponent(0), ending: shade.withAlphaComponent(0.98))?.draw(in: NSRect(x: 0, y: H - 300, width: W, height: 300), angle: 90)
        NSGradient(starting: shade.withAlphaComponent(0.6), ending: shade.withAlphaComponent(0))?.draw(in: NSRect(x: 0, y: 0, width: W, height: 110), angle: 90)
        hit = [:]
        drawHeader()
        drawHero()
        drawNews()
        drawServers()
        drawBottom()
    }

    func drawHeader() {
        // The traffic lights sit at the top left; the name follows them.
        drawText("AETHERION PROJECT", fHead, Theme.text.withAlphaComponent(0.78), 86, 15, kern: 2.2)
        drawRight("Launcher \(appVersion)", fSmall, Theme.dim.withAlphaComponent(0.6), LauncherView.W - 24, 14)
    }

    func drawHero() {
        let x = M, y: CGFloat = 86
        drawText("AETHERION", fTitle, NSColor(white: 0, alpha: 0.47), x + 3, y + 4, kern: 5)
        drawText("AETHERION", fTitle, Theme.text, x, y, kern: 5)
        drawText("PROJECT", fSub, Theme.accent, x + 4, y + 106, kern: 21)
        NSGradient(starting: Theme.accent, ending: Theme.accent.withAlphaComponent(0))?.draw(in: NSRect(x: x + 4, y: y + 158, width: 180, height: 2), angle: 0)
        drawText("by Aljay Leodones", fBy, Theme.text, x + 4, y + 172)
        let tag = "AZAZ GAMES"
        let tw = textWidth(tag, fHead, kern: 3.2)
        let pill = NSRect(x: x + 4, y: y + 210, width: tw + 26, height: 28)
        fill(pill, 14, Theme.accent2.withAlphaComponent(0.16))
        stroke(pill, 14, Theme.accent2.withAlphaComponent(0.6))
        drawText(tag, fHead, Theme.accent2, pill.minX + 13, pill.minY + 6, kern: 3.2)
        drawWrapped("A night-time survival battle royale set in a Philippine riverside slum. Drop in, loot what you can, and be the last squad standing. PC, Mac and phones play in the same matches.",
                    fBody, Theme.dim, NSRect(x: x + 4, y: y + 254, width: 500, height: 70))
    }

    func drawNews() {
        let r = NSRect(x: M, y: 418, width: 520, height: 150)
        fill(r, 10, Theme.panel)
        stroke(r, 10, Theme.line)
        drawText("WHAT'S NEW", fHead, Theme.accent, r.minX + 20, r.minY + 16, kern: 3)
        if let m = remote { drawRight("VERSION \(m.version)", fHead, Theme.dim, r.maxX - 20, r.minY + 16, kern: 2) }
        var y = r.minY + 42
        let notes = remote?.notes ?? [offline ? "Release notes appear here when the launcher is online." : "Loading the latest release…"]
        for n in notes {
            let h = wrappedHeight(n, fBody, r.width - 56)
            if y + min(h, 21) > r.maxY - 10 { break }
            fill(NSRect(x: r.minX + 22, y: y + 7, width: 5, height: 5), 2.5, Theme.accent)
            let boxH = min(h + 1, r.maxY - 12 - y)
            drawWrapped(n, fBody, Theme.text, NSRect(x: r.minX + 36, y: y, width: r.width - 56, height: boxH))
            y += boxH + 6
        }
    }

    func drawServers() {
        let w: CGFloat = 360
        let rows = max(servers?.count ?? 1, 1)
        let r = NSRect(x: LauncherView.W - M - w, y: 70, width: w, height: 58 + CGFloat(rows) * 46)
        fill(r, 10, Theme.panel)
        stroke(r, 10, Theme.line)
        let dot = serversUp == true ? Theme.good : serversUp == false ? Theme.danger : Theme.dim
        let pulse = serversUp == true ? CGFloat(0.5 + 0.5 * sin(Double(tick) * 0.12)) : 0
        fill(NSRect(x: r.minX + 20 - 4 * pulse, y: r.minY + 21 - 4 * pulse, width: 10 + 8 * pulse, height: 10 + 8 * pulse), 5 + 4 * pulse, dot.withAlphaComponent(0.27 * (1 - pulse)))
        fill(NSRect(x: r.minX + 20, y: r.minY + 21, width: 10, height: 10), 5, dot)
        drawText("OFFICIAL SERVERS", fHead, Theme.text, r.minX + 40, r.minY + 18, kern: 3)
        drawRight(serversUp == true ? "\(onlineCount) online" : serversUp == false ? "offline" : "…", fSmall, Theme.dim, r.maxX - 20, r.minY + 18)
        var y = r.minY + 52
        guard let list = servers, !list.isEmpty else {
            drawText(serversUp == false ? "The official servers can't be reached right now." : "Checking…", fBody, Theme.dim, r.minX + 20, y + 4)
            return
        }
        for s in list {
            let dm = s["game_mode"] as? String == "deathmatch"
            let mw = drawText(dm ? "Deathmatch" : "Classic", fBodyB, Theme.text, r.minX + 20, y)
            // (1.4.0) the server's bot difficulty, from game 0.22.0 on
            let skills = ["easy": "Easy", "normal": "Normal", "hard": "Hard", "pro": "Pro"]
            if let skill = skills[s["bot_skill"] as? String ?? ""], (s["bots"] as? Bool) != false {
                _ = drawText("· " + skill + " bots", fSmall, Theme.dim, r.minX + 20 + mw + 8, y + 2)
            }
            let maps = ["malasugue_mall": "Malasugue Mall", "freight_delight": "Freight Delight", "lawless_sub": "Lawless Sub", "kalinaw": "Sitio Kalinaw"]
            let mapId = s["map"] as? String ?? ""
            drawText((maps[mapId] ?? (dm ? "Malasugue Mall" : "Sitio Kalinaw")) + " · " + (s["region"] as? String ?? ""), fSmall, Theme.dim, r.minX + 20, y + 20)
            drawRight("\((s["players"] as? NSNumber)?.intValue ?? 0) / \((s["max"] as? NSNumber)?.intValue ?? 0)", fBodyB, Theme.text, r.maxX - 20, y)
            let lobby = s["state"] as? String == "lobby"
            drawRight(lobby ? "in the lobby" : "match in progress", fSmall, lobby ? Theme.accent2 : Theme.accent, r.maxX - 20, y + 20)
            y += 46
        }
    }

    func drawBottom() {
        let W = LauncherView.W, H = LauncherView.H
        let barW = W - M * 2 - btnW - 32
        drawText(status, fStatus, statusColor, M, H - 150)
        var d = detail
        var frac = -1.0
        if mode == .working, let p = progress {
            frac = p.total > 0 ? min(1, Double(p.done) / Double(p.total)) : 0
            var parts: [String] = []
            if p.total > 0 { parts.append("\(formatSize(p.done)) of \(formatSize(p.total))") }
            if p.downloadTotal > 0 { parts.append("downloaded \(formatSize(p.downloaded)) of \(formatSize(p.downloadTotal))") }
            if p.speed > 1024 && p.downloadTotal > p.downloaded {
                parts.append(formatSize(Int(p.speed)) + "/s")
                let left = Double(p.downloadTotal - p.downloaded) / max(p.speed, 1)
                parts.append(left >= 60 ? "about \(Int(ceil(left / 60))) min left" : "less than a minute left")
            }
            d = (p.total > 0 ? "\(Int(frac * 100))%  ·  " : "") + (parts.isEmpty ? p.phase : parts.joined(separator: "  ·  "))
        }
        drawWrapped(d, fBody, Theme.dim, NSRect(x: M, y: H - 118, width: barW, height: 40))
        let track = NSRect(x: M, y: H - 72, width: barW, height: 6)
        fill(track, 3, NSColor(white: 1, alpha: 0.13))
        if frac >= 0 {
            let f = NSRect(x: track.minX, y: track.minY, width: max(6, track.width * CGFloat(frac)), height: track.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: f, xRadius: 3, yRadius: 3).addClip()
            NSGradient(starting: NSColor(srgbRed: 214 / 255, green: 120 / 255, blue: 36 / 255, alpha: 1), ending: Theme.accentHot)?.draw(in: track, angle: 0)
            NSGraphicsContext.restoreGraphicsState()
        } else if mode == .checking || mode == .working {
            let seg = barW * 0.22, t = CGFloat((tick * 9) % Int(barW + seg)) - seg
            let f = NSRect(x: M + t, y: track.minY, width: seg, height: track.height).intersection(track)
            if f.width > 0 { fill(f, 3, Theme.accent.withAlphaComponent(0.8)) }
        }
        let y = H - 50
        var x = M
        x += drawText("Install folder", fSmall, Theme.dim, x, y) + 10
        var path = u.installDir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        while textWidth(path, fSmall) > 330 && path.count > 8 { path = "…" + path.dropFirst(5) }
        x += drawText(path, fSmall, Theme.text, x, y) + 18
        x = link("change", "Change", x, y) + 16
        x = link("folder", "Show in Finder", x, y) + 16
        let installed = !u.installedVersion(remote).isEmpty
        if installed { x = link("verify", "Verify files", x, y) + 16 }
        var rx = M + barW
        if installed {
            let uw = textWidth("Uninstall", fSmall)
            _ = link("uninstall", "Uninstall", rx - uw, y, Theme.dim)
            rx -= uw + 16
        }
        _ = link("website", "Website", rx - textWidth("Website", fSmall), y)
        // The button
        let b = NSRect(x: W - M - btnW, y: H - 154, width: btnW, height: btnH)
        var label = "PLEASE WAIT", enabled = true, primary = true
        switch mode {
        case .install: label = "INSTALL"
        case .update: label = "UPDATE"
        case .ready: label = "PLAY"
        case .working: label = "PAUSE"; primary = false
        case .error: label = status == "Paused" ? "RESUME" : "RETRY"
        case .playing: label = "PLAYING"; enabled = false
        case .checking: enabled = false
        }
        if enabled { hit["main"] = b }
        let isHot = enabled && hot("main"), down = enabled && pressed == "main"
        if primary {
            if enabled { for i in stride(from: 3, through: 1, by: -1) { fill(b.insetBy(dx: CGFloat(-i * 5), dy: CGFloat(-i * 5)), CGFloat(12 + i * 5), Theme.accent.withAlphaComponent(isHot ? 0.09 : 0.05)) } }
            let top = !enabled ? NSColor(srgbRed: 70 / 255, green: 62 / 255, blue: 50 / 255, alpha: 1) : down ? NSColor(srgbRed: 214 / 255, green: 136 / 255, blue: 40 / 255, alpha: 1) : isHot ? Theme.accentHot : Theme.accent
            let bot = !enabled ? NSColor(srgbRed: 58 / 255, green: 52 / 255, blue: 44 / 255, alpha: 1) : down ? NSColor(srgbRed: 190 / 255, green: 112 / 255, blue: 30 / 255, alpha: 1) : isHot ? NSColor(srgbRed: 245 / 255, green: 160 / 255, blue: 64 / 255, alpha: 1) : NSColor(srgbRed: 222 / 255, green: 132 / 255, blue: 38 / 255, alpha: 1)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: b, xRadius: 12, yRadius: 12).addClip()
            NSGradient(starting: top, ending: bot)?.draw(in: b, angle: 90)
            NSGraphicsContext.restoreGraphicsState()
            let tc = enabled ? NSColor(srgbRed: 26 / 255, green: 17 / 255, blue: 6 / 255, alpha: 1) : Theme.dim.withAlphaComponent(0.6)
            drawText(label, fBtn, tc, b.minX + (b.width - textWidth(label, fBtn, kern: 4)) / 2, b.minY + 18, kern: 4)
        } else {
            fill(b, 12, NSColor(white: 1, alpha: isHot ? 0.23 : 0.13))
            stroke(b, 12, NSColor(white: 1, alpha: 0.35))
            drawText(label, fBtn, Theme.text, b.minX + (b.width - textWidth(label, fBtn, kern: 4)) / 2, b.minY + 18, kern: 4)
        }
        drawRight("© Aljay Leodones · AzAz Games", fSmall, Theme.dim.withAlphaComponent(0.5), W - M, H - 50)
    }

    func link(_ id: String, _ text: String, _ x: CGFloat, _ y: CGFloat, _ color: NSColor = Theme.accent2) -> CGFloat {
        let enabled = mode != .working || id == "website" || id == "folder"
        let c = !enabled ? Theme.dim.withAlphaComponent(0.35) : hot(id) ? NSColor.white : color
        let w = drawText(text, fSmall, c, x, y)
        if enabled { hit[id] = NSRect(x: x - 2, y: y - 4, width: w + 4, height: 22) }
        if hot(id) && enabled { fill(NSRect(x: x, y: y + 18, width: w, height: 1), 0, c) }
        return x + w
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var view: LauncherView!

    func applicationDidFinishLaunching(_ n: Notification) {
        Theme.registerFonts()
        let rect = NSRect(x: 0, y: 0, width: LauncherView.W, height: LauncherView.H)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Aetherion Project"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.backgroundColor = Theme.bg
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self
        view = LauncherView(frame: rect)
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        view.start()
        if let shot = argValue("screenshot") {
            // CI: save the window after it has settled (launcher/macos/build.sh, the workflow).
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(argValue("screenshot-after") ?? "12")!) {
                if let rep = self.view.bitmapImageRepForCachingDisplay(in: self.view.bounds) {
                    self.view.cacheDisplay(in: self.view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: shot))
                }
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ a: NSApplication) -> Bool { true }

    func windowShouldClose(_ w: NSWindow) -> Bool {
        if view.mode == .working {
            let a = NSAlert()
            a.messageText = "Stop the download?"
            a.informativeText = "It continues from where it stopped next time."
            a.addButton(withTitle: "Stop")
            a.addButton(withTitle: "Keep downloading")
            if a.runModal() != .alertFirstButtonReturn { return false }
            view.u.cancelled = true
        }
        return true
    }
}

if argValue("selftest") != nil {
    exit(selfTest())
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
