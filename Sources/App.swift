// mDOWN — téléchargeur de médias léger, résident dans la barre des menus, au moteur d'analyse qui se met à jour seul.
import SwiftUI
import AppKit

@main
enum Launcher {
    static func main() {
        if CommandLine.arguments.contains("--native") || CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("chrome-extension://") }) { NativeHost.run() }
        if CommandLine.arguments.contains("--mcp") { MCPServer.run() }      // serveur MCP pour un agent : aucune interface
        MDownApp.main()
    }
}

struct MDownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject private var store = Store.shared
    @ObservedObject private var access = Access.shared

    var body: some Scene {
        MenuBarExtra {
            let active = store.jobs.filter { [.analyzing, .downloading].contains($0.state) }
            if active.isEmpty { Text(L.t("menu.idle")) }
            ForEach(active) { j in Text("\(j.displayTitle) — \(Int(j.progress * 100)) %") }
            if !access.pending.isEmpty {
                Divider()
                ForEach(access.pending, id: \.self) { p in
                    Button(L.t("menu.allow", (p as NSString).lastPathComponent)) { Access.shared.allow(p) }
                    Button(L.t("menu.deny", (p as NSString).lastPathComponent)) { Access.shared.deny(p) }
                }
            }
            Divider()
            Button(L.t("menu.paste")) { if let u = Store.clipboardURL() { store.add(text: u) } }
            Button(L.t("menu.open")) { MainWindow.show() }
            Button(L.t("menu.engine")) { Task { await Engine.shared.checkNow() } }
            Button(L.t("menu.settings")) { MainWindow.show(); NotificationCenter.default.post(name: .init("mdown.settings"), object: nil) }
            Divider()
            Button(L.t("menu.about")) { About.show() }
            Button(L.t("menu.quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            menuIcon(!access.pending.isEmpty ? "exclamationmark.circle" : store.isBusy ? "arrow.down.circle.fill" : "arrow.down.circle")       // silhouette monochrome : suit le thème de la barre
        }
    }
}

/// Silhouette monochrome (image modèle : suit le thème de la barre), plus grande que le pictogramme par défaut.
@MainActor
func menuIcon(_ name: String) -> Image {
    let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: "mDOWN")?.withSymbolConfiguration(cfg) else { return Image(systemName: name) }
    img.isTemplate = true
    return Image(nsImage: img)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var updateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Engine.shared.start()
        Store.shared.start()
        ControlServer.shared.start()
        Bridge.shared.start()
        ExtensionInstaller.refresh()
        if !Paths.isDev {
            updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
                Task { @MainActor in Updater.shared.tick(busy: Store.shared.isBusy) }
            }
            updateTimer?.tolerance = 1800
            Task { @MainActor in Updater.shared.tick(busy: Store.shared.isBusy) }
        }
        // Mode silencieux : ni ouverture de session, ni lancement par un agent (--background) ne montrent de fenêtre.
        let ev = NSAppleEventManager.shared().currentAppleEvent
        let login = ev?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        if !login, !CommandLine.arguments.contains("--background") { Task { @MainActor in MainWindow.show() } }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in MainWindow.show() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in urls.forEach { Bridge.shared.handle(url: $0) } }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Fenêtre principale créée à la demande et détruite à la fermeture : au repos, l'appli ne garde aucune interface en mémoire.
@MainActor
enum MainWindow {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 940, height: 620)
            w.contentView = NSHostingView(rootView: ContentView())
            w.setFrameAutosaveName("mdown.main")
            if !w.setFrameUsingName("mdown.main") { w.center() }
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                Task { @MainActor in
                    window?.contentView = nil
                    window = nil
                    if let o = closeObserver { NotificationCenter.default.removeObserver(o); closeObserver = nil }
                }
            }
            window = w
        }
        if CommandLine.arguments.contains("--quiet") { window?.orderBack(nil); return }      // essais : fenêtre affichée sans prendre le focus
        NSApp.activate()
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
    }
}
