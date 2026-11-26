// mDOWN — pilotage par un agent : prise locale (réservée à l'utilisateur) côté appli, serveur MCP (stdio) côté agent.
// Lancement du serveur MCP : « mDOWN.app/Contents/MacOS/mDOWN --mcp ». Il parle à l'appli en cours (et la lance en arrière-plan si besoin).
import Foundation
import Darwin

private func socketPath() -> String { Paths.base.appendingPathComponent("mdown.sock").path }

private func unixAddress(_ path: String) -> sockaddr_un {
    var a = sockaddr_un()
    a.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &a.sun_path) { $0.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strncpy($0, path, 103) } }
    return a
}

private func jsonLine(_ obj: Any) -> Data {
    (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) .map { $0 + Data([10]) } ?? Data("{}\n".utf8)
}

/// Lit une ligne (jusqu'à \n) sur un descripteur, avec délai maximal.
private func readLine(fd: Int32, timeout: Int) -> Data? {
    var tv = timeval(tv_sec: timeout, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var buf = Data(), chunk = [UInt8](repeating: 0, count: 4096)
    while buf.count < 1 << 21 {
        let n = recv(fd, &chunk, chunk.count, 0)
        if n <= 0 { return buf.isEmpty ? nil : buf }
        buf.append(chunk, count: n)
        if buf.last == 10 { break }
    }
    return buf
}

// MARK: Côté appli

@MainActor
final class ControlServer {
    static let shared = ControlServer()
    private var source: DispatchSourceRead?
    private var fd: Int32 = -1

    func start() {
        let path = socketPath()
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var addr = unixAddress(path)
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard ok == 0 else { close(fd); return }
        chmod(path, 0o600)                                   // seul l'utilisateur peut parler à l'appli
        listen(fd, 8)
        let s = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
        let listener = fd
        s.setEventHandler {
            let c = accept(listener, nil, nil)
            guard c >= 0 else { return }
            DispatchQueue.global(qos: .utility).async {
                guard let data = readLine(fd: c, timeout: 5), let req = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { close(c); return }
                Task { @MainActor in
                    let resp = await ControlServer.handle(req)
                    DispatchQueue.global().async { let d = jsonLine(resp); _ = d.withUnsafeBytes { send(c, $0.baseAddress, d.count, 0) }; close(c) }
                }
            }
        }
        s.resume()
        source = s
    }

    private static func refusal(_ u: URL) -> [String: Any] {
        ["ok": false, "error": "folder_not_authorized", "pending_approval": true, "folder": u.path, "allowed_folders": Access.shared.roots,
         "message": "The user has not authorized this folder. A request is now waiting in the mDOWN menu bar menu. Ask the user to approve it, then retry, or download into one of allowed_folders (or omit folder)."]
    }

    static func handle(_ r: [String: Any]) async -> [String: Any] {
        let store = Store.shared, engine = Engine.shared
        func id() -> UUID? { (r["id"] as? String).flatMap(UUID.init) }
        switch r["op"] as? String ?? "" {
        case "folders":
            return ["ok": true, "allowed": Access.shared.roots, "pending_user_approval": Access.shared.pending]
        case "request_folder":
            switch Access.shared.check(r["folder"] as? String ?? "") {
            case .ok(let u): return ["ok": true, "authorized": true, "folder": u.path]
            case .forbidden(let why): return ["ok": false, "error": "folder_forbidden", "message": why]
            case .needsApproval(let u): Access.shared.request(u); return refusal(u)
            }
        case "add":
            var folder: String?
            if let f = r["folder"] as? String, !f.isEmpty {
                switch Access.shared.check(f) {
                case .ok(let u): folder = u.path
                case .forbidden(let why): return ["ok": false, "error": "folder_forbidden", "message": why]
                case .needsApproval(let u): Access.shared.request(u); return refusal(u)
                }
            }
            let ids = store.addJobs(text: r["url"] as? String ?? "", audio: (r["mode"] as? String).map { $0 == "audio" }, quality: r["quality"] as? String,
                                    format: r["format"] as? String, folder: folder, cookies: r["cookies"] as? String)
            guard let first = ids.first else { return ["ok": false, "error": L.t("err.badurl")] }
            return ["ok": true, "ids": ids.map(\.uuidString), "job": store.dict(store.jobs.first { $0.id == first } ?? Job(url: ""))]
        case "status":
            guard let i = id(), let j = store.jobs.first(where: { $0.id == i }) else { return ["ok": false, "error": "unknown id"] }
            return ["ok": true, "job": store.dict(j)]
        case "list": return ["ok": true, "jobs": store.jobs.map { store.dict($0) }]
        case "retry":
            guard let i = id() else { return ["ok": false, "error": "unknown id"] }
            store.retry(i); return ["ok": true]
        case "cancel":
            guard let i = id() else { return ["ok": false, "error": "unknown id"] }
            store.cancel(i); return ["ok": true]
        case "engine", "update":
            if r["op"] as? String == "update" { await engine.checkNow() }
            let plats = engine.platforms.map { p -> [String: Any] in ["name": p.name, "working": p.ok as Any, "source": p.fromJob ? "download" : "test"] }
            var d: [String: Any] = ["ok": true, "version": engine.version, "channel": engine.channel, "installed": engine.isInstalled, "platforms": plats,
                                    "js_runtime": engine.jsRuntime()?.name ?? "none", "ffmpeg": engine.ffmpegDir() != nil, "downloads_folder": store.folder.path]
            if let c = engine.lastCheck { d["last_check"] = ISO8601DateFormatter().string(from: c) }
            return d
        default: return ["ok": false, "error": "unknown op"]
        }
    }
}

// MARK: Côté agent : serveur MCP sur stdio

enum MCPServer {
    private static let out = NSLock()

    /// Parle à l'appli ; la lance en arrière-plan (sans prendre le focus) si elle ne tourne pas.
    static func call(_ req: [String: Any], timeout: Int = 20) -> [String: Any] {
        for attempt in 0..<30 {
            if let r = once(req, timeout: timeout) { return r }
            if attempt == 0 {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-g", "-a", Bundle.main.bundlePath, "--args", "--background"]
                try? p.run()
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return ["ok": false, "error": "mDOWN n'a pas pu être joint"]
    }

    private static func once(_ req: [String: Any], timeout: Int) -> [String: Any]? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = unixAddress(socketPath())
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard ok == 0 else { return nil }
        let d = jsonLine(req)
        _ = d.withUnsafeBytes { send(fd, $0.baseAddress, d.count, 0) }
        guard let data = readLine(fd: fd, timeout: timeout) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func emit(_ obj: [String: Any]) {
        out.lock(); defer { out.unlock() }
        FileHandle.standardOutput.write(jsonLine(obj))
    }

    private static let tools: [[String: Any]] = [
        ["name": "download_media",
         "description": "Download a video or audio from any web page supported by mDOWN's self-updating yt-dlp engine (YouTube, Vimeo, TikTok, X, Instagram, SoundCloud, Dailymotion, Twitch, Reddit… about 1800 sites). Waits for the end of the download by default and returns the saved file path. Use mode=audio for a sound-only file.",
         "inputSchema": ["type": "object", "required": ["url"], "properties": [
            "url": ["type": "string", "description": "Page URL of the media (a playlist URL downloads the whole playlist)."],
            "mode": ["type": "string", "enum": ["video", "audio"], "description": "Default: video."],
            "quality": ["type": "string", "enum": ["best", "2160", "1440", "1080", "720", "480"], "description": "Maximum video height. Default: best."],
            "format": ["type": "string", "enum": ["mp4", "mkv", "m4a", "mp3"], "description": "Default: mp4 for video (Mac compatible), m4a for audio."],
            "folder": ["type": "string", "description": "Absolute destination folder (created if needed). Must be inside a folder the user authorized in mDOWN (see list_allowed_folders); otherwise the request waits for the user's approval. Default: the folder set in mDOWN."],
            "cookies_text": ["type": "string", "description": "Optional Netscape cookies.txt content for sites that need a login. mDOWN keeps it in a private file and deletes it when the download ends."],
            "wait": ["type": "boolean", "description": "Wait until finished (default true). If false, returns the download id at once; poll with get_download."],
            "timeout_seconds": ["type": "integer", "description": "Maximum wait when wait=true. Default 1800."]]]],
        ["name": "get_download", "description": "State, progress and saved file path of a download started with download_media.",
         "inputSchema": ["type": "object", "required": ["id"], "properties": ["id": ["type": "string"]]]],
        ["name": "list_downloads", "description": "All downloads known to mDOWN (queued, running, finished, failed).", "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "cancel_download", "description": "Cancel and remove a download.", "inputSchema": ["type": "object", "required": ["id"], "properties": ["id": ["type": "string"]]]],
        ["name": "list_allowed_folders", "description": "Folders where mDOWN may save files for you (set by the user), and folder requests still waiting for the user's approval.", "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "request_folder_access", "description": "Ask the user to authorize a destination folder. Returns at once; the user approves from the mDOWN menu bar menu. System, Library and hidden folders are always refused.",
         "inputSchema": ["type": "object", "required": ["folder"], "properties": ["folder": ["type": "string", "description": "Absolute folder path."]]]],
        ["name": "engine_status", "description": "Version of the extraction engine, last check, per-platform health (tested on reference videos or from real downloads), JS runtime and ffmpeg availability.", "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "update_engine", "description": "Check now for a newer extraction engine, install it (checksum-verified, rolled back if a platform test regresses) and re-test the platforms. Use it when a site stops working.", "inputSchema": ["type": "object", "properties": [:]]],
    ]

    private static func text(_ obj: Any, error: Bool = false) -> [String: Any] {
        let s = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return ["content": [["type": "text", "text": s]], "isError": error]
    }

    private static func callTool(_ name: String, _ a: [String: Any], progress: ((Double) -> Void)?) -> [String: Any] {
        switch name {
        case "download_media":
            guard let url = a["url"] as? String else { return text(["error": "url required"], error: true) }
            var req: [String: Any] = ["op": "add", "url": url]
            for k in ["mode", "quality", "format", "folder"] { if let v = a[k] as? String { req[k] = v } }
            if let v = a["cookies_text"] as? String { req["cookies"] = v }
            let r = call(req)
            guard r["ok"] as? Bool == true, let job = r["job"] as? [String: Any], let id = job["id"] as? String else { return text(r, error: true) }
            if a["wait"] as? Bool == false { return text(job) }
            let deadline = Date().addingTimeInterval(Double(a["timeout_seconds"] as? Int ?? 1800))
            var last = job
            while Date() < deadline {
                Thread.sleep(forTimeInterval: 1)
                let s = call(["op": "status", "id": id])
                guard let j = s["job"] as? [String: Any] else { return text(["error": "download disappeared (cancelled?)", "id": id], error: true) }
                last = j
                progress?(j["progress"] as? Double ?? 0)
                let state = j["state"] as? String ?? ""
                if state == "done" { return text(j) }
                if state == "paused" || (state == "failed" && j["final"] as? Bool == true) { return text(j, error: state == "failed") }
            }
            return text(["note": "timeout reached, download continues in mDOWN", "job": last])
        case "get_download", "cancel_download":
            let r = call(["op": name == "get_download" ? "status" : "cancel", "id": a["id"] as? String ?? ""])
            return text(r, error: r["ok"] as? Bool != true)
        case "list_downloads": return text(call(["op": "list"]))
        case "list_allowed_folders": return text(call(["op": "folders"]))
        case "request_folder_access":
            let r = call(["op": "request_folder", "folder": a["folder"] as? String ?? ""])
            return text(r, error: r["ok"] as? Bool != true && r["pending_approval"] as? Bool != true)
        case "engine_status": return text(call(["op": "engine"]))
        case "update_engine": return text(call(["op": "update"], timeout: 400))
        default: return text(["error": "unknown tool"], error: true)
        }
    }

    static func run() -> Never {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        let queue = DispatchQueue(label: "mdown.mcp", attributes: .concurrent)
        while let line = Swift.readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8), let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            let id = msg["id"], method = msg["method"] as? String ?? ""
            let params = msg["params"] as? [String: Any] ?? [:]
            func reply(_ result: [String: Any]) { if let id { emit(["jsonrpc": "2.0", "id": id, "result": result]) } }
            switch method {
            case "initialize":
                reply(["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18", "capabilities": ["tools": [String: Any]()],
                       "serverInfo": ["name": "mdown", "version": version],
                       "instructions": "mDOWN downloads media from web pages with a self-updating yt-dlp engine. Use download_media; if a site fails, call update_engine then retry."])
            case "ping": reply([:])
            case "tools/list": reply(["tools": tools])
            case "tools/call":
                let token = (params["_meta"] as? [String: Any])?["progressToken"]
                queue.async {
                    let r = callTool(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:]) { p in
                        if let token { emit(["jsonrpc": "2.0", "method": "notifications/progress", "params": ["progressToken": token, "progress": p, "total": 1.0]]) }
                    }
                    reply(r)
                }
            default:
                if let id, !method.hasPrefix("notifications/") { emit(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "method not found"]]) }
            }
        }
        exit(0)
    }
}
