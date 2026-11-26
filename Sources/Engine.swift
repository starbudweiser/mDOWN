// mDOWN — moteur d'analyse adaptatif : yt-dlp (binaire autonome) téléchargé, vérifié (SHA-256), testé puis installé à chaud,
// sans jamais recompiler l'appli. Retour automatique à la version précédente si un test de plateforme régresse.
import Foundation
import CryptoKit

@MainActor
final class Engine: ObservableObject {
    static let shared = Engine()

    enum State: Equatable { case missing, installing, checking, updating, ready, failed(String) }

    struct Platform: Identifiable, Codable, Equatable {
        var id: String
        var name: String
        var ok: Bool?
        var date: Date?
        var fromJob = false          // le dernier résultat vient d'un vrai téléchargement et non d'un test
    }

    private struct Meta: Codable { var version = ""; var lastCheck: Date?; var platforms: [Platform] = [] }
    private struct Release { var tag: String; var bin: URL; var sums: URL }
    private struct Probe { var id: String; var name: String; var url: String }

    /// Une vidéo de référence stable par plateforme : sert à vérifier qu'un nouveau moteur n'a rien cassé.
    private static let probes = [
        Probe(id: "youtube", name: "YouTube", url: "https://www.youtube.com/watch?v=jNQXAC9IVRw"),
        Probe(id: "soundcloud", name: "SoundCloud", url: "https://soundcloud.com/forss/flickermood"),
        Probe(id: "archive", name: "Internet Archive", url: "https://archive.org/details/Popeye_forPresident"),
        Probe(id: "ted", name: "TED", url: "https://www.ted.com/talks/ken_robinson_says_schools_kill_creativity"),
    ]

    @Published private(set) var state: State = .missing
    @Published private(set) var version = ""
    @Published private(set) var lastCheck: Date?
    @Published private(set) var platforms: [Platform] = []
    @Published private(set) var testing = false
    @Published private(set) var rolledBack = false

    let ytdlp = Paths.engine.appendingPathComponent("yt-dlp")
    private let prev = Paths.engine.appendingPathComponent("yt-dlp.prev")
    private let metaURL = Paths.engine.appendingPathComponent("meta.json")
    private var updateTask: Task<Bool, Never>?
    private var lastForced = Date.distantPast
    private var timer: Timer?
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        return URLSession(configuration: c)
    }()

    var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: ytdlp.path) }
    var channel: String { UserDefaults.standard.string(forKey: "channel") ?? "stable" }
    var autoUpdate: Bool { UserDefaults.standard.object(forKey: "autoEngine") as? Bool ?? true }

    private init() {
        if let d = try? Data(contentsOf: metaURL), let m = try? JSONDecoder().decode(Meta.self, from: d) {
            version = m.version; lastCheck = m.lastCheck; platforms = m.platforms
        }
        for p in Self.probes where !platforms.contains(where: { $0.id == p.id }) { platforms.append(Platform(id: p.id, name: p.name)) }
        state = isInstalled ? .ready : .missing
    }

    /// Au démarrage : installe le moteur s'il manque, puis une recherche par jour (toutes les heures on regarde s'il est temps).
    func start() {
        if isInstalled, version.isEmpty { Task { let r = await Proc.run(ytdlp.path, ["--version"], timeout: 60); version = r.out.trimmingCharacters(in: .whitespacesAndNewlines) } }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        timer?.tolerance = 600
    }

    private func tick() {
        if !isInstalled { Task { _ = await ensureInstalled() }; return }
        if autoUpdate, Date().timeIntervalSince(lastCheck ?? .distantPast) > 24 * 3600 { Task { _ = await update(user: false) } }
    }

    func ensureInstalled() async -> Bool {
        if isInstalled { return true }
        _ = await update(user: true)
        return isInstalled
    }

    /// Bouton « Vérifier maintenant » : mise à jour éventuelle, puis tests des plateformes.
    func checkNow() async {
        let updated = await update(user: true)
        if !updated { await runProbes() }
    }

    /// Cherche et installe un moteur plus récent. `true` si une nouvelle version est en place.
    /// Les déclenchements automatiques (erreur d'extraction) sont espacés de 10 minutes.
    func update(user: Bool) async -> Bool {
        if let t = updateTask { return await t.value }
        if !user, isInstalled, Date().timeIntervalSince(lastForced) < 600 { return false }
        lastForced = Date()
        let t = Task { @MainActor in await self.performUpdate() }
        updateTask = t
        let r = await t.value
        updateTask = nil
        return r
    }

    private func performUpdate() async -> Bool {
        let had = isInstalled
        rolledBack = false
        state = had ? .checking : .installing
        do {
            let rel = try await latestRelease()
            lastCheck = Date(); save()
            if had, !VersionCompare.isNewer(rel.tag, than: version) { state = .ready; return false }
            state = had ? .updating : .installing
            let (tmp, resp) = try await session.download(from: rel.bin)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw EngineError.download }
            let (sumData, _) = try await session.data(from: rel.sums)
            guard let expected = Self.expectedHash(String(decoding: sumData, as: UTF8.self), file: "yt-dlp_macos"),
                  try Self.sha256(tmp) == expected else { throw EngineError.checksum }
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            let test = await Proc.run(tmp.path, ["--version"], timeout: 90)
            guard test.status == 0, !test.out.isEmpty else { throw EngineError.selfTest }
            let fm = FileManager.default
            if had { try? fm.removeItem(at: prev); try fm.moveItem(at: ytdlp, to: prev) }
            try? fm.removeItem(at: ytdlp)
            try fm.moveItem(at: tmp, to: ytdlp)
            version = test.out.trimmingCharacters(in: .whitespacesAndNewlines)
            save(); state = .ready
            await ensureComponents()
            let before = platforms.filter { $0.ok == true && !$0.fromJob }.map(\.id)
            await runProbes()
            if had, platforms.contains(where: { before.contains($0.id) && $0.ok == false && !$0.fromJob }), fm.fileExists(atPath: prev.path) {
                rollback()
                await runProbes()
                return false
            }
            return true
        } catch {
            state = isInstalled ? .ready : .failed(error.localizedDescription)
            return false
        }
    }

    private func rollback() {
        let fm = FileManager.default
        try? fm.removeItem(at: ytdlp)
        try? fm.moveItem(at: prev, to: ytdlp)
        Task { @MainActor in
            let r = await Proc.run(ytdlp.path, ["--version"], timeout: 60)
            version = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            rolledBack = true; save()
        }
    }

    private enum EngineError: LocalizedError {
        case noRelease, download, checksum, selfTest
        var errorDescription: String? {
            switch self {
            case .noRelease: return "release"
            case .download: return "download"
            case .checksum: return "SHA-256"
            case .selfTest: return "self-test"
            }
        }
    }

    private func latestRelease() async throws -> Release {
        let repo = channel == "nightly" ? "yt-dlp/yt-dlp-nightly-builds" : "yt-dlp/yt-dlp"
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else { throw EngineError.noRelease }
        func url(_ name: String) -> URL? { (assets.first { $0["name"] as? String == name }?["browser_download_url"] as? String).flatMap(URL.init) }
        guard let bin = url("yt-dlp_macos"), let sums = url("SHA2-256SUMS") else { throw EngineError.noRelease }
        return Release(tag: tag, bin: bin, sums: sums)
    }

    private static func expectedHash(_ sums: String, file: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            if f.count == 2, f[1] == file { return String(f[0]).lowercased() }
        }
        return nil
    }

    private static func sha256(_ url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        var hasher = SHA256()
        while let d = try h.read(upToCount: 1 << 20), !d.isEmpty { hasher.update(data: d) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Tests de plateformes

    func runProbes() async {
        guard isInstalled, !testing else { return }
        testing = true; defer { testing = false }
        var results: [(Probe, Bool?)] = []
        for p in Self.probes {
            let r = await Proc.run(ytdlp.path, ["--skip-download", "--simulate", "--no-warnings", "--playlist-items", "1", "--print", "id"] + commonArgs() + [p.url], timeout: 75)
            let low = r.err.lowercased()
            let needsAccount = low.contains("logged-in") || low.contains("cookies") || low.contains("sign in")     // ni réussite ni panne du moteur
            results.append((p, r.status == 0 && !r.out.isEmpty ? true : (needsAccount ? nil : false)))
        }
        guard results.contains(where: { $0.1 == true }) else { return }       // tout échoue : probablement hors ligne, on ne change rien
        for (p, ok) in results { if let ok { set(id: p.id, name: p.name, ok: ok, fromJob: false) } }
        save()
    }

    /// Résultat d'un vrai téléchargement : l'état de la plateforme reflète ce qui se passe réellement.
    func record(platform id: String, name: String, ok: Bool) {
        set(id: id, name: name, ok: ok, fromJob: true); save()
    }

    private func set(id: String, name: String, ok: Bool, fromJob: Bool) {
        if let i = platforms.firstIndex(where: { $0.id == id }) { platforms[i].ok = ok; platforms[i].date = Date(); platforms[i].fromJob = fromJob }
        else { platforms.append(Platform(id: id, name: name, ok: ok, date: Date(), fromJob: fromJob)) }
    }

    // MARK: Composants autour du moteur (JavaScript pour YouTube, ffmpeg pour fusionner image et son)

    func jsRuntime() -> (name: String, path: String)? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let list: [(String, String)] = [("deno", Paths.engine.appendingPathComponent("deno").path), ("deno", "/opt/homebrew/bin/deno"), ("deno", "/usr/local/bin/deno"),
            ("deno", home + "/.deno/bin/deno"), ("node", "/opt/homebrew/bin/node"), ("node", "/usr/local/bin/node"), ("bun", "/opt/homebrew/bin/bun")]
        return list.first { fm.isExecutableFile(atPath: $0.1) }.map { (name: $0.0, path: $0.1) }
    }

    func ffmpegDir() -> String? {
        let fm = FileManager.default
        for d in [Paths.engine.path, "/opt/homebrew/bin", "/usr/local/bin"] where fm.isExecutableFile(atPath: d + "/ffmpeg") { return d }
        return nil
    }

    /// Arguments communs : exécuteur JavaScript, composants distants du moteur, ffmpeg, cookies du navigateur.
    func commonArgs() -> [String] {
        var a = ["--no-colors"]
        if let js = jsRuntime() { a += ["--js-runtimes", "\(js.name):\(js.path)", "--remote-components", "ejs:github"] }
        if let f = ffmpegDir() { a += ["--ffmpeg-location", f] }
        if let b = UserDefaults.standard.string(forKey: "cookies"), !b.isEmpty { a += ["--cookies-from-browser", b] }
        return a
    }

    private func ensureComponents() async {
        if jsRuntime() == nil {
            #if arch(arm64)
            let arch = "aarch64"
            #else
            let arch = "x86_64"
            #endif
            await fetchZip("https://github.com/denoland/deno/releases/latest/download/deno-\(arch)-apple-darwin.zip", expect: "deno")
        }
        if ffmpegDir() == nil { await fetchZip("https://evermeet.cx/ffmpeg/getrelease/zip", expect: "ffmpeg") }
    }

    private func fetchZip(_ s: String, expect: String) async {
        guard let url = URL(string: s), let (tmp, resp) = try? await session.download(from: url), (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
        let zip = tmp.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".zip")
        try? FileManager.default.moveItem(at: tmp, to: zip)
        _ = await Proc.run("/usr/bin/ditto", ["-x", "-k", zip.path, Paths.engine.path])
        try? FileManager.default.removeItem(at: zip)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Paths.engine.appendingPathComponent(expect).path)
    }

    private func save() {
        let m = Meta(version: version, lastCheck: lastCheck, platforms: platforms)
        if let d = try? JSONEncoder().encode(m) { try? d.write(to: metaURL, options: .atomic) }
    }

    /// Nom lisible d'une plateforme d'après l'identifiant d'extracteur de yt-dlp (« youtube:tab » → YouTube).
    static func platformInfo(extractor: String) -> (id: String, name: String) {
        let id = extractor.split(separator: ":").first.map { String($0).lowercased() } ?? extractor.lowercased()
        let names = ["youtube": "YouTube", "vimeo": "Vimeo", "soundcloud": "SoundCloud", "tiktok": "TikTok", "instagram": "Instagram", "twitter": "X", "facebook": "Facebook",
                     "dailymotion": "Dailymotion", "twitch": "Twitch", "reddit": "Reddit", "bandcamp": "Bandcamp", "arte": "ARTE"]
        return (id, names[id] ?? id.prefix(1).uppercased() + id.dropFirst())
    }
}
