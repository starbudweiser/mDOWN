// mDOWN — extension navigateur sans code d'association : le navigateur lance « mDOWN --native » (messagerie native, réservée à
// l'extension déclarée dans le manifeste), qui relaie vers l'appli par le socket privé. L'appli installe aussi l'extension elle-même
// (dossier prêt à charger, sans code à coller). Chromium interdit l'installation silencieuse hors Chrome Web Store (essayé : l'extension
// déposée reste bloquée « non modifiable »), d'où le chargement manuel en 3 clics tant que l'extension n'est pas sur le Store.
import Foundation
import Darwin
import AppKit

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
    struct Browser: Identifiable { let id: String; let name: String; let dir: String; var hostDirs: [String] = []; var app = ""; var scheme = "chrome"
        var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(dir, isDirectory: true) }
    }
    // Brave lit le dossier de relais de Chrome (constaté) ; le sien est protégé par macOS.
    static let all = [Browser(id: "brave", name: "Brave", dir: "BraveSoftware/Brave-Browser", hostDirs: ["Google/Chrome"], app: "Brave Browser", scheme: "brave"),
                      Browser(id: "chrome", name: "Chrome", dir: "Google/Chrome", hostDirs: ["Google/Chrome"], app: "Google Chrome"),
                      Browser(id: "edge", name: "Edge", dir: "Microsoft Edge", hostDirs: ["Microsoft Edge"], app: "Microsoft Edge", scheme: "edge"),
                      Browser(id: "chromium", name: "Chromium", dir: "Chromium", hostDirs: ["Chromium"], app: "Chromium"),
                      Browser(id: "vivaldi", name: "Vivaldi", dir: "Vivaldi", hostDirs: ["Vivaldi"], app: "Vivaldi", scheme: "vivaldi")]

    static var detected: [Browser] { all.filter { FileManager.default.fileExists(atPath: $0.support.path) } }
    /// Dossier prêt à charger, visible dans le Finder.
    static var unpacked: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/mDOWN Extension", isDirectory: true) }
    static func isInstalled(_ b: Browser) -> Bool {
        guard let d = b.hostDirs.first else { return false }
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(d)
            .appendingPathComponent("NativeMessagingHosts/\(NativeHost.hostName).json")
        return FileManager.default.fileExists(atPath: u.path)
    }

    /// Copie l'extension dans un dossier visible et déclare le relais. Rend nil si tout va bien, sinon la cause.
    @discardableResult static func install(_ b: Browser) -> String? {
        let fm = FileManager.default
        guard let src = Bundle.main.resourceURL?.appendingPathComponent("Extension"), fm.fileExists(atPath: src.path) else { return "extension absente" }
        do {
            try? fm.removeItem(at: unpacked)
            try fm.copyItem(at: src, to: unpacked)
            let host: [String: Any] = ["name": NativeHost.hostName, "description": "mDOWN", "path": Bundle.main.executablePath ?? "",
                                       "type": "stdio", "allowed_origins": ["chrome-extension://\(NativeHost.extensionID)/"]]
            let h = try JSONSerialization.data(withJSONObject: host, options: .prettyPrinted)
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            for d in b.hostDirs {
                let hosts = base.appendingPathComponent(d, isDirectory: true).appendingPathComponent("NativeMessagingHosts", isDirectory: true)
                try fm.createDirectory(at: hosts, withIntermediateDirectories: true)
                try h.write(to: hosts.appendingPathComponent("\(NativeHost.hostName).json"))
            }
            return nil
        } catch { return error.localizedDescription }
    }

    /// Ouvre la page des extensions du navigateur (sans l'activer à la place de l'utilisateur) et montre le dossier à charger.
    static func openExtensionsPage(_ b: Browser) {
        if let page = URL(string: "\(b.scheme)://extensions"), let app = appURL(b) {
            NSWorkspace.shared.open([page], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
        NSWorkspace.shared.activateFileViewerSelecting([unpacked])
    }
    private static func appURL(_ b: Browser) -> URL? {
        for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
            let u = URL(fileURLWithPath: dir + "/" + b.app + ".app"); if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// Au lancement : remet à jour (chemin de l'appli, version du paquet) les navigateurs déjà équipés.
    static func refresh() { for b in detected where isInstalled(b) { _ = install(b) } }
}
