// mDOWN — passerelle pour les navigateurs : petit serveur HTTP réservé à la boucle locale (127.0.0.1), ouvert aux seules extensions
// qui présentent le code d'association, et lien « mdown:// » pour les autres navigateurs (Safari : signet).
import Foundation
import Darwin
import AppKit

@MainActor
final class Bridge {
    static let shared = Bridge()
    static let port: UInt16 = Paths.isDev ? 47616 : 47615      // l'édition de développement a son propre port
    static let scheme = Paths.isDev ? "mdown-dev" : "mdown"

    private var source: DispatchSourceRead?
    private let tokenURL = Paths.base.appendingPathComponent("bridge.token")

    /// Code d'association : aléatoire, créé une fois, lisible par l'utilisateur seul.
    var token: String {
        if let t = try? String(contentsOf: tokenURL, encoding: .utf8), t.count >= 32 { return t.trimmingCharacters(in: .whitespacesAndNewlines) }
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let t = bytes.map { String(format: "%02x", $0) }.joined()
        try? t.write(to: tokenURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
        return t
    }

    var extensionFolder: URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Extension")
        if let b = bundled, FileManager.default.fileExists(atPath: b.path) { return b }
        return nil
    }

    var bookmarklet: String { "javascript:location.href='\(Self.scheme)://download?url='+encodeURIComponent(location.href)" }

    func start() {
        _ = token
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var a = sockaddr_in()
        a.sin_family = sa_family_t(AF_INET); a.sin_port = Self.port.bigEndian; a.sin_addr.s_addr = inet_addr("127.0.0.1")   // boucle locale seulement
        let ok = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard ok == 0, listen(fd, 16) == 0 else { close(fd); return }       // port pris (autre édition) : la passerelle reste fermée
        let s = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
        let token = self.token
        s.setEventHandler {
            let c = accept(fd, nil, nil)
            guard c >= 0 else { return }
            DispatchQueue.global(qos: .utility).async { Bridge.serve(c, token: token) }
        }
        s.resume(); source = s
    }

    // MARK: HTTP

    private nonisolated static func serve(_ c: Int32, token: String) {
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = Data(), chunk = [UInt8](repeating: 0, count: 8192)
        var headEnd: Range<Data.Index>?
        while buf.count < 65_536 {
            let n = recv(c, &chunk, chunk.count, 0)
            if n <= 0 { break }
            buf.append(chunk, count: n)
            if headEnd == nil { headEnd = buf.range(of: Data("\r\n\r\n".utf8)) }
            if let h = headEnd {
                let head = String(decoding: buf[..<h.lowerBound], as: UTF8.self).lowercased()
                let len = head.components(separatedBy: "\r\n").first { $0.hasPrefix("content-length:") }.flatMap { Int($0.dropFirst(15).trimmingCharacters(in: .whitespaces)) } ?? 0
                if buf.count - h.upperBound >= len { break }
            }
        }
        guard let h = headEnd else { close(c); return }
        let head = String(decoding: buf[..<h.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let body = buf[h.upperBound...]
        let first = head[0].split(separator: " ")
        guard first.count >= 2 else { close(c); return }
        let method = String(first[0]), path = String(first[1].split(separator: "?").first ?? "")
        var hdr: [String: String] = [:]
        for l in head.dropFirst() { if let i = l.firstIndex(of: ":") { hdr[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) } }

        func reply(_ code: Int, _ text: String, _ json: [String: Any]? = nil, origin: String? = nil) {
            let payload = json.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
            var out = "HTTP/1.1 \(code) \(text)\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n"
            if let o = origin {
                out += "Access-Control-Allow-Origin: \(o)\r\nAccess-Control-Allow-Headers: content-type, x-mdown-token\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nVary: Origin\r\n"
            }
            let d = Data((out + "\r\n").utf8) + payload
            _ = d.withUnsafeBytes { send(c, $0.baseAddress, d.count, 0) }
            close(c)
        }

        // Une page web quelconque ne doit jamais pouvoir piloter l'appli : seules les extensions passent, avec le code d'association.
        let origin = hdr["origin"] ?? ""
        guard ["chrome-extension://", "moz-extension://", "safari-web-extension://"].contains(where: origin.hasPrefix) else { reply(403, "Forbidden", ["ok": false]); return }
        if method == "OPTIONS" { reply(204, "No Content", origin: origin); return }
        guard hdr["x-mdown-token"] == token else { reply(401, "Unauthorized", ["ok": false, "error": "code"], origin: origin); return }

        var req = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        switch path {
        case "/ping": req["op"] = "engine"
        case "/add": req["op"] = "add"
        case "/jobs": req["op"] = "list"
        case "/cancel": req["op"] = "cancel"
        case "/retry": req["op"] = "retry"
        default: reply(404, "Not Found", ["ok": false], origin: origin); return
        }
        Task { @MainActor in
            var r = await ControlServer.handle(req)
            if path == "/ping" { r = ["ok": true, "version": r["version"] ?? "", "installed": r["installed"] ?? false] }
            DispatchQueue.global().async { reply(200, "OK", r, origin: origin) }
        }
    }

    // MARK: Lien mdown://download?url=…&mode=audio

    func handle(url: URL) {
        guard url.scheme == Self.scheme, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        func q(_ n: String) -> String? { c.queryItems?.first { $0.name == n }?.value }
        guard c.host == "download", let target = q("url") else { return }
        Store.shared.addJobs(text: target, audio: q("mode").map { $0 == "audio" }, quality: q("quality"), format: q("format"))
    }
}
