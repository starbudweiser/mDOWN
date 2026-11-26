// mDOWN — lancement de processus externes (moteur, ffmpeg…) et chemins de l'appli.
import Foundation

enum Paths {
    /// L'édition de développement (identifiant en « .dev ») a ses propres données : elle ne touche jamais celles de la version installée.
    static let isDev = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    static let base: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(isDev ? "mDOWN Dev" : "mDOWN", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static let engine: URL = {
        let u = base.appendingPathComponent("engine", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static var defaultFolder: URL { FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("mDOWN", isDirectory: true) }
}

enum Proc {
    struct Result { var status: Int32; var out: String; var err: String }

    private final class Box { var out = Data(); var err = Data() }

    static var environment: [String: String] {
        var e = ProcessInfo.processInfo.environment
        e["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        e["PYTHONUNBUFFERED"] = "1"
        return e
    }

    /// Lance un exécutable, attend sa fin (ou `timeout` secondes, 0 = sans limite) et rend sa sortie.
    static func run(_ exe: String, _ args: [String], timeout: TimeInterval = 0) async -> Result {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let p = Process(), o = Pipe(), e = Pipe(), box = Box()
                p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
                p.environment = environment
                p.standardOutput = o; p.standardError = e; p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch { cont.resume(returning: Result(status: -1, out: "", err: error.localizedDescription)); return }
                let g = DispatchGroup()
                g.enter(); DispatchQueue.global().async { box.out = o.fileHandleForReading.readDataToEndOfFile(); g.leave() }
                g.enter(); DispatchQueue.global().async { box.err = e.fileHandleForReading.readDataToEndOfFile(); g.leave() }
                if timeout > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } } }
                p.waitUntilExit(); g.wait()
                cont.resume(returning: Result(status: p.terminationStatus, out: String(decoding: box.out, as: UTF8.self), err: String(decoding: box.err, as: UTF8.self)))
            }
        }
    }
}

/// Mémoire réellement occupée par l'appli (empreinte), en Mo.
func memoryFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}

enum VersionCompare {
    /// « 2026.11.25.012345 » est plus récent que « 2026.11.24 » : comparaison numérique champ par champ.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 } }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
