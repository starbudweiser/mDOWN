// mDOWN — file de téléchargements : analyse, téléchargement par le moteur, reprise, nouvel essai automatique et réparation du moteur.
import Foundation
import AppKit

struct Job: Identifiable, Codable, Equatable {
    enum State: String, Codable { case queued, analyzing, downloading, paused, done, failed }
    var id = UUID()
    var url: String
    var title: String?
    var platform: String?
    var platformID: String?
    var duration: Double?
    var count: Int?                      // éléments d'une playlist
    var state: State = .queued
    var progress = 0.0
    var speed: Double?
    var eta: Int?
    var bytes: Int64?
    var audio = false
    var height: Int?                     // nil = meilleure qualité
    var format = "mp4"
    var noPlaylist = false
    var cookiesFile: String?             // cookies du navigateur de l'appelant (wCLAUDE…), fichier privé supprimé après le téléchargement
    var folder: String?                  // dossier choisi par l'appelant (agent) ; sinon celui des réglages
    var attempts = 0
    var error: String?
    var retryAt: Date?
    var repairing = false                // le moteur est en cours de mise à jour pour ce téléchargement
    var file: String?
    var added = Date()
    var finished: Date?

    var qualityLabel: String { audio ? "" : (height.map { "\($0)p" } ?? L.t("q.best")) }
    var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        guard let u = URL(string: url) else { return url }
        return (u.host ?? "") + u.path
    }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    @Published var jobs: [Job] = []

    private var procs: [UUID: Process] = [:]
    private var running = Set<UUID>()
    private enum Stop { case pause, cancel }
    private var stops: [UUID: Stop] = [:]
    private let file = Paths.base.appendingPathComponent("jobs.json")

    var isBusy: Bool { !running.isEmpty }
    var folder: URL {
        let p = UserDefaults.standard.string(forKey: "folder").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Paths.defaultFolder
        try? FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
        return p
    }

    private init() {
        if let d = try? Data(contentsOf: file), var list = try? JSONDecoder().decode([Job].self, from: d) {
            for i in list.indices where [.analyzing, .downloading].contains(list[i].state) { list[i].state = .queued }   // reprise après un arrêt
            jobs = list
        }
    }

    func start() { purgeCookies(); pump(); scheduleRetries() }

    // MARK: Ajout

    @discardableResult
    func add(text: String) -> Int { addJobs(text: text).count }

    /// Ajoute les liens trouvés dans `text` (les options non données viennent des réglages) et rend leurs identifiants.
    /// Un lien déjà en cours rend l'identifiant du téléchargement existant.
    @discardableResult
    func addJobs(text: String, audio: Bool? = nil, quality: String? = nil, format: String? = nil, folder: String? = nil, cookies: String? = nil) -> [UUID] {
        let ud = UserDefaults.standard
        let isAudio = audio ?? (ud.string(forKey: "mode") == "audio")
        let q = quality ?? ud.string(forKey: "quality") ?? "best"
        var ids: [UUID] = [], added = false
        for raw in text.split(whereSeparator: { $0.isWhitespace }) {
            guard let u = URL(string: String(raw)), let s = u.scheme?.lowercased(), s == "http" || s == "https", u.host != nil else { continue }
            let url = u.absoluteString
            if let dup = jobs.first(where: { $0.url == url && [.queued, .analyzing, .downloading, .paused].contains($0.state) }) { ids.append(dup.id); continue }
            var j = Job(url: url)
            j.audio = isAudio
            j.height = Int(q)
            let fmt = format ?? (isAudio ? (ud.string(forKey: "aformat") ?? "m4a") : (ud.string(forKey: "vformat") ?? "mp4"))
            j.format = isAudio ? (["m4a", "mp3"].contains(fmt) ? fmt : "m4a") : (["mp4", "mkv"].contains(fmt) ? fmt : "mp4")
            j.noPlaylist = url.contains("v=") && url.contains("list=")     // un lien de vidéo dans une liste : la vidéo seule
            j.folder = folder
            j.cookiesFile = cookies.flatMap { Self.writeCookies($0, for: j.id) }
            jobs.insert(j, at: 0); ids.append(j.id); added = true
        }
        if added { save(); pump() }
        return ids
    }

    func dict(_ j: Job) -> [String: Any] {
        var d: [String: Any] = ["id": j.id.uuidString, "url": j.url, "state": j.state.rawValue, "progress": (j.progress * 1000).rounded() / 1000, "attempts": j.attempts,
                                "final": (j.state == .failed && j.retryAt == nil && !j.repairing)]
        if let v = j.title { d["title"] = v }
        if let v = j.platform { d["platform"] = v }
        if let v = j.file { d["file"] = v }
        if let v = j.bytes { d["bytes"] = v }
        if let v = j.error { d["error"] = v }
        if let v = j.speed { d["bytes_per_second"] = Int(v) }
        if let v = j.eta { d["eta_seconds"] = v }
        if let v = j.count { d["playlist_items"] = v }
        if j.repairing { d["engine_repair_in_progress"] = true }
        return d
    }

    // MARK: Cookies fournis par l'appelant

    private static let cookiesDir: URL = {
        let u = Paths.base.appendingPathComponent("cookies", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return u
    }()

    private static func writeCookies(_ text: String, for id: UUID) -> String? {
        guard text.utf8.count <= 1_000_000 else { return nil }
        let f = cookiesDir.appendingPathComponent(id.uuidString + ".txt")
        guard (try? text.write(to: f, atomically: true, encoding: .utf8)) != nil else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path)
        return f.path
    }

    private func dropCookies(_ j: Job) { if let c = j.cookiesFile { try? FileManager.default.removeItem(atPath: c) } }

    /// Fichiers de cookies qui ne servent plus (téléchargement retiré ou terminé).
    private func purgeCookies() {
        let used = Set(jobs.compactMap(\.cookiesFile))
        for f in (try? FileManager.default.contentsOfDirectory(at: Self.cookiesDir, includingPropertiesForKeys: nil)) ?? [] where !used.contains(f.path) { try? FileManager.default.removeItem(at: f) }
    }

    static func clipboardURL() -> String? {
        guard let s = NSPasteboard.general.string(forType: .string) else { return nil }
        for w in s.split(whereSeparator: { $0.isWhitespace }) {
            if let u = URL(string: String(w)), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.host != nil { return u.absoluteString }
        }
        return nil
    }

    // MARK: Actions

    func pause(_ id: UUID) {
        if running.contains(id) { stops[id] = .pause; procs[id]?.terminate() }
        else if let i = idx(id) { jobs[i].state = .paused; save() }
    }
    func resume(_ id: UUID) { if let i = idx(id) { jobs[i].state = .queued; jobs[i].error = nil; jobs[i].retryAt = nil; save(); pump() } }
    func retry(_ id: UUID) { if let i = idx(id) { jobs[i].attempts = 0; resume(id) } }
    func cancel(_ id: UUID) {
        if running.contains(id) { stops[id] = .cancel; procs[id]?.terminate() }
        else { if let j = jobs.first(where: { $0.id == id }) { dropCookies(j) }; jobs.removeAll { $0.id == id }; save() }
    }
    func remove(_ id: UUID) { cancel(id) }
    func reveal(_ id: UUID) {
        guard let j = jobs.first(where: { $0.id == id }) else { return }
        if let f = j.file, FileManager.default.fileExists(atPath: f) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)]) }
        else { NSWorkspace.shared.open(folder) }
    }

    private func idx(_ id: UUID) -> Int? { jobs.firstIndex { $0.id == id } }
    private func mutate(_ id: UUID, _ f: (inout Job) -> Void) { if let i = idx(id) { f(&jobs[i]) } }

    // MARK: Ordonnancement

    func pump() {
        let limit = max(1, UserDefaults.standard.object(forKey: "concurrent") as? Int ?? 2)
        for j in jobs.reversed() where j.state == .queued && running.count < limit {   // le plus ancien d'abord
            if let r = j.retryAt, r > Date() { continue }
            launch(j.id)
        }
    }

    private func launch(_ id: UUID) {
        running.insert(id)
        mutate(id) { $0.state = $0.title == nil ? .analyzing : .downloading }
        Task { @MainActor in
            await self.run(id)
            self.running.remove(id); self.procs[id] = nil; self.stops[id] = nil
            self.save(); self.pump()
        }
    }

    private func scheduleRetries() {
        Task { @MainActor in
            while true {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                guard jobs.contains(where: { $0.retryAt != nil }) else { continue }      // rien à surveiller : aucun travail
                var changed = false
                for i in jobs.indices where jobs[i].state == .failed && !jobs[i].repairing {
                    if let r = jobs[i].retryAt, r <= Date() { jobs[i].state = .queued; jobs[i].retryAt = nil; changed = true }
                }
                if changed { save(); pump() }
            }
        }
    }

    // MARK: Exécution

    private func run(_ id: UUID) async {
        let engine = Engine.shared
        guard await engine.ensureInstalled() else { fail(id, err: "", fallback: L.t("err.noengine"), retry: true); return }
        guard let job0 = jobs.first(where: { $0.id == id }) else { return }
        if job0.title == nil {
            var a = ["-J", "--flat-playlist", "--no-warnings", "--playlist-items", "1:100"]
            a.append(job0.noPlaylist ? "--no-playlist" : "--yes-playlist")
            a += engine.commonArgs()
            if let c = job0.cookiesFile { a += ["--cookies", c] }
            a.append(job0.url)
            let r = await Proc.run(engine.ytdlp.path, a, timeout: 180)
            if stops[id] != nil { finishStop(id); return }
            guard r.status == 0, let data = r.out.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                fail(id, err: r.err, fallback: L.t("err.badurl"), retry: true); return
            }
            let ex = (json["extractor_key"] as? String) ?? (json["extractor"] as? String) ?? ""
            let info = Engine.platformInfo(extractor: (json["extractor"] as? String) ?? ex)
            let entries = json["entries"] as? [Any]
            mutate(id) {
                $0.title = json["title"] as? String ?? $0.url
                $0.platform = info.name; $0.platformID = info.id
                $0.duration = json["duration"] as? Double
                if json["_type"] as? String == "playlist" { $0.count = (json["playlist_count"] as? Int) ?? entries?.count }
                $0.state = .downloading
            }
        }
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        let result = await download(job)
        if stops[id] != nil { finishStop(id); return }
        if result.status == 0 {
            let path = result.files.last
            let size = path.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0)[.size]) as? Int64 }
            mutate(id) {
                $0.state = .done; $0.progress = 1; $0.speed = nil; $0.eta = nil; $0.error = nil; $0.finished = Date()
                $0.file = path; if let size, job.count == nil { $0.bytes = size }
            }
            dropCookies(job); mutate(id) { $0.cookiesFile = nil }
            if let pid = job.platformID, let name = job.platform { engine.record(platform: pid, name: name, ok: true) }
        } else {
            fail(id, err: result.err, fallback: "", retry: true)
        }
    }

    private func finishStop(_ id: UUID) {
        if stops[id] == .cancel { if let j = jobs.first(where: { $0.id == id }) { dropCookies(j) }; jobs.removeAll { $0.id == id } }
        else { mutate(id) { $0.state = .paused; $0.speed = nil; $0.eta = nil } }
    }

    private static let extractorErrors = ["unable to extract", "nsig", "sign in to confirm", "http error 403", "requested format is not available",
                                          "unsupported url", "no video formats", "challenge", "player response", "http error 429"]
    private static let permanentErrors = ["private video", "video unavailable", "this video has been removed", "copyright", "members-only", "account associated"]

    private func fail(_ id: UUID, err: String, fallback: String, retry: Bool) {
        let lines = err.split(whereSeparator: \.isNewline).map(String.init)
        var msg = lines.last(where: { $0.hasPrefix("ERROR") }) ?? lines.last ?? fallback
        if let r = msg.range(of: "ERROR: ") { msg = String(msg[r.upperBound...]) }
        if msg.isEmpty { msg = fallback }
        let low = err.lowercased()
        let extractor = Self.extractorErrors.contains { low.contains($0) }
        let permanent = Self.permanentErrors.contains { low.contains($0) }
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        if let pid = job.platformID, let name = job.platform, !permanent { Engine.shared.record(platform: pid, name: name, ok: false) }
        let attempts = job.attempts + 1
        mutate(id) {
            $0.state = .failed; $0.error = String(msg.prefix(160)); $0.attempts = attempts; $0.speed = nil; $0.eta = nil
        }
        guard retry, !permanent, attempts <= 2 else { return }
        if extractor {
            // Le site a probablement changé : on cherche tout de suite un moteur plus récent, puis on relance seul.
            mutate(id) { $0.repairing = true }
            Task { @MainActor in
                let updated = await Engine.shared.update(user: false)
                self.mutate(id) {
                    $0.repairing = false
                    if updated { $0.state = .queued; $0.error = nil } else { $0.retryAt = Date().addingTimeInterval(120) }
                }
                self.save(); self.pump()
            }
        } else {
            mutate(id) { $0.retryAt = Date().addingTimeInterval(120) }
        }
    }

    // MARK: Processus de téléchargement

    private final class Stream: @unchecked Sendable {
        private let lock = NSLock()
        private var outBuf = Data(), errTail = Data()
        private var files: [String] = []
        private var last = Date.distantPast
        private var lastFile = ""
        let onProgress: @Sendable ([String]) -> Void
        init(onProgress: @escaping @Sendable ([String]) -> Void) { self.onProgress = onProgress }

        func feedOut(_ d: Data) {
            lock.lock(); outBuf.append(d)
            var lines: [String] = []
            while let r = outBuf.firstRange(of: Data([10])) {
                lines.append(String(decoding: outBuf[..<r.lowerBound], as: UTF8.self)); outBuf.removeSubrange(..<r.upperBound)
            }
            lock.unlock()
            lines.forEach(handle)
        }
        func feedErr(_ d: Data) { lock.lock(); errTail.append(d); if errTail.count > 16_384 { errTail = errTail.suffix(16_384) }; lock.unlock() }
        func flush() { lock.lock(); let rest = String(decoding: outBuf, as: UTF8.self); outBuf.removeAll(); lock.unlock(); if !rest.isEmpty { handle(rest) } }
        var errText: String { lock.lock(); defer { lock.unlock() }; return String(decoding: errTail, as: UTF8.self) }
        var finished: [String] { lock.lock(); defer { lock.unlock() }; return files }

        private func handle(_ l: String) {
            if l.hasPrefix("FILE|") { lock.lock(); files.append(String(l.dropFirst(5))); lock.unlock(); return }
            guard l.hasPrefix("PRG|") else { return }
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            lock.lock()
            let name = f.count > 8 ? f[8] : ""
            let changed = name != lastFile
            let due = Date().timeIntervalSince(last) > 0.3
            if changed || due { lastFile = name; last = Date() }
            lock.unlock()
            if changed || due { onProgress(f) }
        }
    }

    private final class Ctx { var file = ""; var stage = 0; var item = 0 }

    private func download(_ job: Job) async -> (status: Int32, err: String, files: [String]) {
        let engine = Engine.shared
        let id = job.id
        let dest = job.folder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? folder
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        var a = ["--newline", "--progress", "--no-warnings", "--no-simulate", "--embed-metadata", "-N", "4", "-P", dest.path,
                 "-o", "%(playlist_title&{} /|)s%(playlist_index&{} - |)s%(title).150B.%(ext)s",
                 "--progress-template", "download:PRG|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s|%(info.playlist_index)s|%(info.n_entries)s|%(progress.filename)s",
                 "--print", "after_move:FILE|%(filepath)s"]
        a.append(job.noPlaylist ? "--no-playlist" : "--yes-playlist")
        if job.audio {
            a += ["-f", "ba/b", "-x", "--audio-format", job.format, "--audio-quality", "0"]
        } else {
            let cap = job.height.map { "[height<=\($0)]" } ?? ""
            a += ["-f", "bv*\(cap)+ba/b\(cap)", "--merge-output-format", job.format]
            a += job.format == "mp4" ? ["-S", (job.height ?? 0) > 1080 ? "res,vcodec:h264,acodec:m4a" : "vcodec:h264,res,acodec:m4a"] : ["-S", "res,vcodec,acodec"]
        }
        a += engine.commonArgs()
        if let c = job.cookiesFile { a += ["--cookies", c] }
        a.append(job.url)

        let ctx = Ctx()
        let audio = job.audio
        let stream = Stream { [weak self] f in
            DispatchQueue.main.async { self?.applyProgress(id, f, ctx, audio: audio) }
        }
        return await withCheckedContinuation { cont in
            let p = Process(), out = Pipe(), err = Pipe()
            p.executableURL = engine.ytdlp; p.arguments = a; p.environment = Proc.environment
            p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
            out.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; if d.isEmpty { h.readabilityHandler = nil } else { stream.feedOut(d) } }
            err.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; if d.isEmpty { h.readabilityHandler = nil } else { stream.feedErr(d) } }
            p.terminationHandler = { pr in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
                    out.fileHandleForReading.readabilityHandler = nil; err.fileHandleForReading.readabilityHandler = nil
                    stream.flush()
                    cont.resume(returning: (pr.terminationStatus, stream.errText, stream.finished))
                }
            }
            do { try p.run(); procs[id] = p } catch { cont.resume(returning: (-1, error.localizedDescription, [])) }
        }
    }

    private func applyProgress(_ id: UUID, _ f: [String], _ ctx: Ctx, audio: Bool) {
        func num(_ i: Int) -> Double? { i < f.count ? Double(f[i]) : nil }
        let dl = num(1) ?? 0
        let total = num(2) ?? num(3) ?? 0
        let frac = total > 0 ? min(1, dl / total) : 0
        let item = Int(num(6) ?? 1)
        let name = f.count > 8 ? f[8] : ""
        if item != ctx.item { ctx.item = item; ctx.stage = 0; ctx.file = name }
        else if name != ctx.file { ctx.file = name; ctx.stage += 1 }          // flux suivant (le son après l'image)
        let own = audio ? frac : (ctx.stage == 0 ? frac * 0.88 : min(1, 0.88 + frac * 0.12))
        let n = Double(max(1, Int(num(7) ?? 1)))
        let overall = (Double(max(1, item) - 1) + own) / n
        mutate(id) {
            $0.state = .downloading
            $0.progress = max($0.progress < 0.99 ? overall : $0.progress, 0)
            $0.speed = num(4); $0.eta = num(5).map { Int($0) }
            if total > 0, $0.count == nil { $0.bytes = Int64(total) }
        }
    }

    // MARK: Persistance

    private func save() {
        let keep = jobs.filter { $0.state != .done }.count
        _ = keep
        var list = jobs
        let done = list.filter { $0.state == .done }
        if done.count > 40 { let drop = Set(done.sorted { ($0.finished ?? .distantPast) < ($1.finished ?? .distantPast) }.prefix(done.count - 40).map(\.id)); list.removeAll { drop.contains($0.id) }; jobs = list }
        if let d = try? JSONEncoder().encode(list) { try? d.write(to: file, options: .atomic) }
    }
}
