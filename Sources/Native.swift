// mDOWN — extension navigateur sans code d'association : le navigateur lance « mDOWN --native » (messagerie native, réservée à
// l'extension déclarée dans le manifeste), qui relaie vers l'appli par le socket privé. L'appli installe aussi l'extension elle-même
// (fichier .crx déposé dans « External Extensions » du navigateur) : il ne reste qu'à confirmer l'ajout dans le navigateur.
import Foundation
import Darwin

enum NativeHost {
    static let extensionID = "jjconfkgcbfgklodfeajekgfllgjoban"      // fixé par la clé publique du manifeste
    static let hostName = "fr.stephan.mdown"

    private static func readExactly(_ n: Int) -> Data? {
        var out = Data(), buf = [UInt8](repeating: 0, count: max(n, 1))
        while out.count < n {
            let r = read(0, &buf, n - out.count)
            if r <= 0 { return nil }
            out.append(buf, count: r)
        }
        return out
    }

    /// Boucle du processus lancé par le navigateur : un message JSON {path, body} en entrée, une réponse en sortie.
    static func run() -> Never {
        if let o = CommandLine.arguments.dropFirst().first(where: { $0.hasPrefix("chrome-extension://") }), o != "chrome-extension://\(extensionID)/" { exit(1) }
        while let head = readExactly(4) {
            let len = Int(head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            guard len > 0, len < 4_000_000, let body = readExactly(len),
                  let m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { break }
            let path = m["path"] as? String ?? ""
            var req = m["body"] as? [String: Any] ?? [:]
            switch path {
            case "/ping": req["op"] = "engine"
            case "/add": req["op"] = "add"
            case "/jobs": req["op"] = "list"
            case "/cancel": req["op"] = "cancel"
            case "/retry": req["op"] = "retry"
            default: respond(["ok": false, "error": "path"]); continue
            }
            var r = MCPServer.call(req)       // lance l'appli en arrière-plan si besoin
            if path == "/ping" { r = ["ok": r["ok"] as? Bool ?? true, "version": r["version"] ?? "", "installed": r["installed"] ?? false] }
            respond(r)
        }
        exit(0)
    }

    private static func respond(_ obj: [String: Any]) {
        let d = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        var n = UInt32(d.count)
        let h = Data(bytes: &n, count: 4)
        FileHandle.standardOutput.write(h + d)
    }
}

/// Installation de l'extension dans les navigateurs à base de Chromium.
enum ExtensionInstaller {
    struct Browser: Identifiable { let id: String; let name: String; let dir: String; var hostDirs: [String] = []
        var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(dir, isDirectory: true) }
    }
    // Brave lit le dossier de relais de Chrome (constaté) : on écrit dans les deux.
    static let all = [Browser(id: "brave", name: "Brave", dir: "BraveSoftware/Brave-Browser", hostDirs: ["Google/Chrome", "BraveSoftware/Brave-Browser"]),
                      Browser(id: "chrome", name: "Chrome", dir: "Google/Chrome", hostDirs: ["Google/Chrome"]),
                      Browser(id: "edge", name: "Edge", dir: "Microsoft Edge", hostDirs: ["Microsoft Edge"]),
                      Browser(id: "chromium", name: "Chromium", dir: "Chromium", hostDirs: ["Chromium"]),
                      Browser(id: "vivaldi", name: "Vivaldi", dir: "Vivaldi", hostDirs: ["Vivaldi"])]

    static var detected: [Browser] { all.filter { FileManager.default.fileExists(atPath: $0.support.path) } }
    static func isInstalled(_ b: Browser) -> Bool {
        FileManager.default.fileExists(atPath: b.support.appendingPathComponent("External Extensions/\(NativeHost.extensionID).json").path)
    }

    private static var version: String {
        guard let u = Bundle.main.resourceURL?.appendingPathComponent("Extension/manifest.json"), let d = try? Data(contentsOf: u),
              let m = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return "0" }
        return m["version"] as? String ?? "0"
    }

    /// Dépose le paquet et déclare le relais. Rend faux si le paquet manque (appli compilée sans extension).
    @discardableResult static func install(_ b: Browser) -> Bool {
        let fm = FileManager.default
        guard let crx = Bundle.main.resourceURL?.appendingPathComponent("mDOWN.crx"), fm.fileExists(atPath: crx.path) else { return false }
        let keep = Paths.base.appendingPathComponent("Extension", isDirectory: true)
        try? fm.createDirectory(at: keep, withIntermediateDirectories: true)
        let dest = keep.appendingPathComponent("mDOWN.crx")
        try? fm.removeItem(at: dest)
        guard (try? fm.copyItem(at: crx, to: dest)) != nil else { return false }
        let ext = b.support.appendingPathComponent("External Extensions", isDirectory: true)
        try? fm.createDirectory(at: ext, withIntermediateDirectories: true)
        let pref: [String: Any] = ["external_crx": dest.path, "external_version": version]
        let host: [String: Any] = ["name": NativeHost.hostName, "description": "mDOWN", "path": Bundle.main.executablePath ?? "",
                                   "type": "stdio", "allowed_origins": ["chrome-extension://\(NativeHost.extensionID)/"]]
        guard let p = try? JSONSerialization.data(withJSONObject: pref, options: .prettyPrinted),
              let h = try? JSONSerialization.data(withJSONObject: host, options: .prettyPrinted),
              (try? p.write(to: ext.appendingPathComponent("\(NativeHost.extensionID).json"))) != nil else { return false }
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for d in b.hostDirs {
            let hosts = base.appendingPathComponent(d, isDirectory: true).appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            try? fm.createDirectory(at: hosts, withIntermediateDirectories: true)
            guard (try? h.write(to: hosts.appendingPathComponent("\(NativeHost.hostName).json"))) != nil else { return false }
        }
        return true
    }

    /// Au lancement : remet à jour (chemin de l'appli, version du paquet) les navigateurs déjà équipés.
    static func refresh() { for b in detected where isInstalled(b) { install(b) } }
}
