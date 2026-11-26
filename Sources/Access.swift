// mDOWN — autorisations de dossiers pour les agents : un agent choisit où enregistrer, mais seulement dans les dossiers
// que l'utilisateur a autorisés. Toute autre demande attend son accord (menu de la barre des menus ou réglages), sans fenêtre volée.
import Foundation

@MainActor
final class Access: ObservableObject {
    static let shared = Access()

    enum Verdict {
        case ok(URL)
        case needsApproval(URL)
        case forbidden(String)
    }

    @Published private(set) var allowed: [String] = UserDefaults.standard.stringArray(forKey: "allowedFolders") ?? []
    @Published private(set) var pending: [String] = []

    /// Dossiers où un agent peut écrire : le dossier de téléchargement des réglages + ceux que l'utilisateur a ajoutés.
    var roots: [String] { ([Store.shared.folder.path, Paths.defaultFolder.path] + allowed).map { Self.real(URL(fileURLWithPath: $0)).path } }

    private static let blocked = ["/System", "/usr", "/bin", "/sbin", "/etc", "/private/etc", "/private/var/db", "/Library", "/Applications", "/dev", "/cores"]

    /// Chemin réel : symlinks résolus sur la partie existante, pour qu'un lien ne fasse pas sortir d'un dossier autorisé.
    private static func real(_ url: URL) -> URL {
        let fm = FileManager.default
        var existing = url.standardizedFileURL, tail: [String] = []
        while !fm.fileExists(atPath: existing.path), existing.path != "/" { tail.insert(existing.lastPathComponent, at: 0); existing.deleteLastPathComponent() }
        var r = existing.resolvingSymlinksInPath()
        for t in tail { r.appendPathComponent(t) }
        return r
    }

    func check(_ raw: String) -> Verdict {
        let expanded = (raw as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return .forbidden("the folder must be an absolute path") }
        let url = Self.real(URL(fileURLWithPath: expanded))
        let p = url.path
        let home = NSHomeDirectory()
        if p == "/" || p == home || Self.blocked.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) || p.hasPrefix(home + "/Library")
            || p.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { return .forbidden("system, Library and hidden folders can never be authorized") }
        if roots.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { return .ok(url) }
        return .needsApproval(url)
    }

    /// Un agent demande un dossier non autorisé : la demande attend l'utilisateur.
    func request(_ url: URL) { if !pending.contains(url.path) { pending.append(url.path) } }

    func allow(_ path: String) {
        if !allowed.contains(path) { allowed.append(path); UserDefaults.standard.set(allowed, forKey: "allowedFolders") }
        pending.removeAll { $0 == path }
    }
    func deny(_ path: String) { pending.removeAll { $0 == path } }
    func remove(_ path: String) { allowed.removeAll { $0 == path }; UserDefaults.standard.set(allowed, forKey: "allowedFolders") }
}
