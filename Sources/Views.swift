// mDOWN — fenêtre principale (maquette Flat Mat, arrondis doux) : état du moteur à gauche, file de téléchargements à droite.
import SwiftUI
import AppKit
import ServiceManagement

private let byteFmt: ByteCountFormatter = { let f = ByteCountFormatter(); f.countStyle = .file; f.allowsNonnumericFormatting = false; return f }()
/// Mémoire occupée (Mo en français, MB en anglais…), arrondie au Mo.
private let memFmt: ByteCountFormatter = { let f = ByteCountFormatter(); f.countStyle = .memory; f.allowedUnits = [.useMB]; f.allowsNonnumericFormatting = false; return f }()
private func bytes(_ n: Int64) -> String { byteFmt.string(fromByteCount: n) }
private func clock(_ s: Double) -> String {
    let t = Int(s); return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) : String(format: "%02d:%02d", t / 60, t % 60)
}

struct ContentView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var engine = Engine.shared
    @State private var field = ""
    @State private var showSettings = false
    @State private var memory = memoryFootprintMB()
    @State private var lastClip = ""
    @State private var targeted = false
    @AppStorage("mode") private var mode = "video"
    @AppStorage("quality") private var quality = "best"
    @AppStorage("vformat") private var vformat = "mp4"
    @AppStorage("aformat") private var aformat = "m4a"
    @AppStorage("clip") private var clip = true

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 0) {
                Sidebar().frame(width: 300)
                main
            }
        }
        .background(T.bg)
        .ignoresSafeArea()
        .foregroundColor(T.text)
        .font(.system(size: 13))
        .sheet(isPresented: $showSettings) { SettingsView(done: { showSettings = false }) }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in memory = memoryFootprintMB() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in checkClipboard() }
        .onAppear { checkClipboard(); if CommandLine.arguments.contains("--settings") { showSettings = true } }
        .onReceive(NotificationCenter.default.publisher(for: .init("mdown.settings"))) { _ in showSettings = true }
    }

    private func checkClipboard() {
        guard clip, let u = Store.clipboardURL(), u != lastClip else { return }
        lastClip = u
        if field.isEmpty { field = u }
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandName().padding(.leading, 70)
            Spacer()
            Circle().fill(T.ok).frame(width: 8, height: 8).overlay(Circle().stroke(T.ok.opacity(0.25), lineWidth: 3))
            Text(L.t("svc.active", memFmt.string(fromByteCount: Int64(memory * 1_048_576)))).font(.system(size: 12)).foregroundColor(T.text2)
            IconButton(symbol: "gearshape", help: L.t("set.title")) { showSettings = true }
        }
        .padding(.horizontal, 16).frame(height: 52)
    }

    private var main: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "link").foregroundColor(T.text2)
                    TextField(L.t("paste.ph"), text: $field).textFieldStyle(.plain).onSubmit(submit)
                }
                .padding(.horizontal, 12).frame(height: 36)
                .background(T.ctl, in: RoundedRectangle(cornerRadius: T.rCtl, style: .continuous))
                Button(action: submit) { Label(L.t("btn.download"), systemImage: "arrow.down.to.line") }.buttonStyle(PrimaryStyle())
            }
            HStack(spacing: 8) {
                modePicker
                if mode == "video" {
                    chip(L.t("opt.quality", quality == "best" ? L.t("q.best") : "\(quality)p"), items: [("best", L.t("q.best")), ("2160", "2160p"), ("1440", "1440p"), ("1080", "1080p"), ("720", "720p"), ("480", "480p")]) { quality = $0 }
                    chip(L.t("opt.format", vformat.uppercased()), items: [("mp4", "MP4"), ("mkv", "MKV")]) { vformat = $0 }
                } else {
                    chip(L.t("opt.format", aformat.uppercased()), items: [("m4a", "M4A"), ("mp3", "MP3")]) { aformat = $0 }
                }
                Spacer()
                Text(L.t("count.summary", store.jobs.count, store.jobs.filter { [.analyzing, .downloading].contains($0.state) }.count, store.jobs.filter { $0.state == .queued }.count))
                    .font(.system(size: 12)).foregroundColor(T.text2)
            }
            GeometryReader { g in
                let n = store.jobs.count
                let gaps = CGFloat(max(0, n - 1)) * 8
                let rowH: CGFloat = n == 0 ? 0 : min(92, max(76, (g.size.height - gaps) / CGFloat(n)))
                let rest = g.size.height - CGFloat(n) * rowH - gaps - (n > 0 ? 8 : 0)
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.jobs) { JobRow(job: $0, height: rowH) }
                        if n == 0 || rest >= 90 { dropCard(height: n == 0 ? g.size.height : rest) }
                    }
                }
                .scrollIndicators(.never)
            }
            HStack {
                Text(L.t("foot.menu")); Spacer(); Text(L.t("foot.engine"))
            }.font(.system(size: 12)).foregroundColor(T.text2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: T.rCard, style: .continuous).stroke(T.acc, lineWidth: targeted ? 2 : 0).padding(6))
        .onDrop(of: [.url, .plainText], isTargeted: $targeted) { providers in
            for p in providers {
                if p.canLoadObject(ofClass: URL.self) { _ = p.loadObject(ofClass: URL.self) { u, _ in if let u { DispatchQueue.main.async { Store.shared.add(text: u.absoluteString) } } } }
                else { _ = p.loadObject(ofClass: String.self) { s, _ in if let s { DispatchQueue.main.async { Store.shared.add(text: s) } } } }
            }
            return true
        }
    }

    private func submit() {
        if store.add(text: field) > 0 { field = "" }
    }

    private func dropCard(height: CGFloat) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.to.line").font(.system(size: 20, weight: .semibold)).foregroundColor(T.text2)
            Text(L.t("empty.drop")).font(.system(size: 14, weight: .semibold))
            Text(L.t("empty.hint")).font(.system(size: 12)).foregroundColor(T.text2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .background(RoundedRectangle(cornerRadius: T.rCard, style: .continuous).strokeBorder(T.text2.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach([("video", "mode.video", "film"), ("audio", "mode.audio", "music.note")], id: \.0) { m in
                Button { mode = m.0 } label: {
                    Label(L.t(m.1), systemImage: m.2).font(.system(size: 12.5, weight: mode == m.0 ? .semibold : .regular))
                        .foregroundColor(mode == m.0 ? T.onAcc : T.text2)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(mode == m.0 ? T.acc : Color.clear, in: RoundedRectangle(cornerRadius: T.rCtl - 2, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
        .padding(3).background(T.ctl, in: RoundedRectangle(cornerRadius: T.rCtl, style: .continuous))
    }

    private func chip(_ label: String, items: [(String, String)], pick: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(items, id: \.0) { i in Button(i.1) { pick(i.0) } }
        } label: {
            HStack(spacing: 4) { Text(label); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
        }
        .menuStyle(.button).menuIndicator(.hidden).buttonStyle(SoftStyle()).fixedSize()
    }
}

// MARK: Colonne de gauche : moteur, bilan du jour, dossier

struct Sidebar: View {
    @ObservedObject private var engine = Engine.shared
    @ObservedObject private var store = Store.shared
    @AppStorage("clip") private var clip = true
    @AppStorage("channel") private var channel = "stable"
    @AppStorage("folder") private var folderPath = ""

    private var title: String {
        switch engine.state {
        case .missing: return L.t("eng.missing")
        case .installing: return L.t("eng.installing")
        case .checking: return L.t("eng.checking")
        case .updating: return L.t("eng.updating")
        case .failed: return L.t("eng.failed")
        case .ready: return L.t("eng.upToDate", engine.version)
        }
    }
    private var subtitle: String {
        if engine.rolledBack { return L.t("eng.rolled") }
        if case .failed = engine.state { return L.t("err.noengine") }
        return engine.lastCheck.map { L.t("eng.checked", L.ago($0)) } ?? L.t("eng.never")
    }
    private var tint: Color {
        switch engine.state { case .ready: return engine.rolledBack ? T.warn : T.ok; case .failed, .missing: return T.err; default: return T.warn }
    }
    private var busy: Bool { [.checking, .installing, .updating].contains(engine.state) || engine.testing }

    var body: some View {
        VStack(spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: engine.state == .ready ? "checkmark.shield" : "arrow.triangle.2.circlepath").font(.system(size: 15, weight: .semibold)).foregroundColor(tint)
                            .frame(width: 34, height: 34).background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: T.rCtl, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                            Text(subtitle).font(.system(size: 12)).foregroundColor(T.text2).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(displayPlatforms) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(p.name)
                                    if let d = p.date { Text(L.t(p.fromJob ? (p.ok == true ? "plat.jobok" : "plat.jobfail") : "plat.tested", L.ago(d))).font(.system(size: 11)).foregroundColor(T.text2).lineLimit(1) }
                                }
                                Spacer(minLength: 6)
                                platformTag(p)
                            }.frame(maxHeight: .infinity)
                        }
                    }.frame(maxHeight: .infinity)
                    HStack {
                        Text(L.t("eng.channel")).foregroundColor(T.text2)
                        Spacer()
                        Menu {
                            Button(L.t("ch.stable")) { channel = "stable" }
                            Button(L.t("ch.nightly")) { channel = "nightly" }
                        } label: { Text(L.t(channel == "nightly" ? "ch.nightly" : "ch.stable")).fontWeight(.bold) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                    Button { Task { await engine.checkNow() } } label: {
                        HStack(spacing: 6) {
                            if busy { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                            Text(L.t("eng.check"))
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(SoftStyle()).disabled(busy)
                }
            }.frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                stat(String(doneToday.count), L.t("today.done"))
                stat(bytes(doneToday.reduce(0) { $0 + ($1.bytes ?? 0) }), L.t("today.received"))
                stat(String(store.jobs.filter { $0.state == .failed }.count), L.t("today.errors"))
            }

            Card {
                VStack(spacing: 6) {
                    HStack {
                        Label(store.folder.path.replacingOccurrences(of: NSHomeDirectory() + "/", with: ""), systemImage: "folder").lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(L.t("dest.change")) { chooseFolder() }.buttonStyle(.plain).modifier(TagLook())
                    }
                    HStack {
                        Text(L.t("dest.clip")).foregroundColor(T.text2)
                        Spacer()
                        Button { clip.toggle() } label: { Tag(text: L.t(clip ? "dest.clipOn" : "dest.clipOff"), kind: clip ? .ok : .plain) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity)
    }

    /// Les six plateformes de la maquette (non testées tant qu'elles n'ont rien servi), plus toute autre utilisée ou en panne.
    private var displayPlatforms: [Engine.Platform] {
        let fixed = [("youtube", "YouTube"), ("vimeo", "Vimeo"), ("tiktok", "TikTok"), ("instagram", "Instagram"), ("soundcloud", "SoundCloud"), ("twitter", "X")]
        var out = fixed.map { f in engine.platforms.first { $0.id == f.0 } ?? Engine.Platform(id: f.0, name: f.1) }
        for p in engine.platforms where !fixed.contains(where: { $0.0 == p.id }) && (p.fromJob || p.ok == false) { out.append(p) }
        return Array(out.prefix(8))
    }

    private var doneToday: [Job] { store.jobs.filter { $0.state == .done && ($0.finished.map(Calendar.current.isDateInToday) ?? false) } }

    @ViewBuilder private func platformTag(_ p: Engine.Platform) -> some View {
        if engine.testing && p.ok == nil { Tag(text: L.t("plat.testing")) }
        else if p.ok == true { Tag(text: L.t("plat.ok"), kind: .ok) }
        else if p.ok == false { Tag(text: L.t("plat.fail"), kind: .err) }
        else if ["vimeo", "tiktok", "twitter"].contains(p.id) { Tag(text: L.t("plat.login")) }
        else { Tag(text: L.t("plat.untested")) }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(l).font(.system(size: 11)).foregroundColor(T.text2)
        }
        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        .background(T.ctl, in: RoundedRectangle(cornerRadius: T.rCtl, style: .continuous))
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.directoryURL = store.folder
        if p.runModal() == .OK, let u = p.url { folderPath = u.path }
    }
}

private struct TagLook: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: 10.5, weight: .semibold)).foregroundColor(T.text2).padding(.horizontal, 8).padding(.vertical, 2)
            .background(T.ctl, in: RoundedRectangle(cornerRadius: T.rChip, style: .continuous))
    }
}

// MARK: Ligne de téléchargement

struct JobRow: View {
    let job: Job
    var height: CGFloat = 76
    private var store: Store { Store.shared }

    var body: some View {
        HStack(spacing: 14) {
            thumb
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(job.displayTitle).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    if let p = job.platform { Tag(text: p) }
                }
                meta
                Bar(value: job.state == .failed ? 1 : job.progress, color: barColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(right.0).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(right.1).font(.system(size: 12)).foregroundColor(T.text2).lineLimit(1)
            }.frame(width: 150, alignment: .leading)
            HStack(spacing: 6) { actions }.frame(width: 66, alignment: .trailing)
        }
        .padding(.horizontal, 12).frame(height: height)
        .background(T.card, in: RoundedRectangle(cornerRadius: T.rCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: T.rCard, style: .continuous).stroke(T.line, lineWidth: 1))
        .contextMenu { Button(L.t("act.remove")) { store.remove(job.id) } }
    }

    private var barColor: Color { job.state == .done ? T.ok : job.state == .failed ? T.err : T.acc }

    private var thumb: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: job.state == .failed ? "exclamationmark.triangle" : job.audio ? "music.note" : "play")
                .font(.system(size: 16)).foregroundColor(T.onThumb).frame(width: 84, height: 52)
                .background(T.thumb, in: RoundedRectangle(cornerRadius: T.rCtl, style: .continuous))
            if let d = job.count.map({ String($0) }) ?? job.duration.map(clock) {
                Text(d).font(.system(size: 10, weight: .semibold)).foregroundColor(.white).padding(.horizontal, 5)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4)).padding(3)
            }
        }
    }

    private var meta: some View {
        HStack(spacing: 6) {
            if job.state == .failed {
                Tag(text: L.t("state.failed"), kind: .err)
                Text(job.repairing ? L.t("err.repair") : (job.error ?? "")).foregroundColor(T.text2).lineLimit(1)
            } else {
                Text([job.count.map { L.t("pl.items", $0) }, job.qualityLabel.isEmpty ? nil : job.qualityLabel, job.format.uppercased(), job.count == nil ? job.bytes.map(bytes) : nil]
                    .compactMap { $0 }.joined(separator: " · ")).foregroundColor(T.text2).lineLimit(1)
                switch job.state {
                case .downloading: Tag(text: L.t("state.downloading"), kind: .ok)
                case .analyzing: Tag(text: L.t("state.analyzing"))
                case .queued: Tag(text: L.t("state.queued"))
                case .paused: Tag(text: L.t("state.paused"), kind: .warn)
                case .done: Tag(text: L.t("state.done"), kind: .ok)
                case .failed: EmptyView()
                }
            }
        }.font(.system(size: 12))
    }

    private var right: (String, String) {
        switch job.state {
        case .downloading, .analyzing:
            let pct = Int(job.progress * 100)
            let eta = job.eta.map { clock(Double($0)) }
            return (job.speed.map { bytes(Int64($0)) + "/s" } ?? "—", eta.map { L.t("sp.prog", pct, $0) } ?? L.t("sp.pct", pct))
        case .queued: return ("—", L.t("sp.queue"))
        case .paused: return (L.t("sp.pct", Int(job.progress * 100)), L.t("state.paused"))
        case .done: return (job.bytes.map(bytes) ?? "—", job.finished.map { L.ago($0) } ?? "")
        case .failed:
            if let r = job.retryAt, r > Date() { return ("—", L.t("state.retry", r.formatted(date: .omitted, time: .shortened))) }
            return ("—", "")
        }
    }

    @ViewBuilder private var actions: some View {
        switch job.state {
        case .downloading, .analyzing:
            IconButton(symbol: "pause.fill", help: L.t("act.pause")) { store.pause(job.id) }
            IconButton(symbol: "xmark", help: L.t("act.cancel")) { store.cancel(job.id) }
        case .queued: IconButton(symbol: "xmark", help: L.t("act.cancel")) { store.cancel(job.id) }
        case .paused:
            IconButton(symbol: "play.fill", help: L.t("act.resume")) { store.resume(job.id) }
            IconButton(symbol: "xmark", help: L.t("act.cancel")) { store.cancel(job.id) }
        case .done: IconButton(symbol: "folder", help: L.t("act.reveal")) { store.reveal(job.id) }
        case .failed: IconButton(symbol: "arrow.counterclockwise", help: L.t("act.retry")) { store.retry(job.id) }
        }
    }
}

// MARK: Réglages

struct SettingsView: View {
    var done: () -> Void
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var access = Access.shared
    @AppStorage("concurrent") private var concurrent = 2
    @AppStorage("cookies") private var cookies = ""
    @AppStorage("autoEngine") private var autoEngine = true
    @AppStorage("autoUpdate") private var autoUpdate = true
    @AppStorage("clip") private var clip = true
    @AppStorage("useWclaude") private var useWclaude = true
    @State private var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("set.title")).font(.system(size: 16, weight: .bold))
            HStack(alignment: .top, spacing: 12) { VStack(alignment: .leading, spacing: 12) {
            Card(pad: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L.t("set.concurrent")); Spacer()
                        Stepper(value: $concurrent, in: 1...4) { Text("\(concurrent)").fontWeight(.semibold).monospacedDigit() }.fixedSize()
                    }
                    HStack {
                        Text(L.t("set.cookies")); Spacer()
                        Picker("", selection: $cookies) {
                            Text(L.t("set.cookies.none")).tag("")
                            ForEach(["safari", "chrome", "firefox", "brave", "edge"], id: \.self) { Text($0.capitalized).tag($0) }
                        }.labelsHidden().fixedSize()
                    }
                    Text(L.t("set.cookies.help")).font(.system(size: 11.5)).foregroundColor(T.text2)
                }
            }
            Card(pad: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    switchRow(L.t("set.clip"), $clip)
                    switchRow(L.t("set.autoengine"), $autoEngine)
                    switchRow(L.t("set.autoapp"), $autoUpdate)
                    switchRow(L.t("set.wclaude"), $useWclaude)
                    switchRow(L.t("set.login"), $login).onChange(of: login) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { login = SMAppService.mainApp.status == .enabled }
                    }
                    HStack {
                        Button(L.t("set.appupdate")) { Task { await updater.check() } }.buttonStyle(SoftStyle())
                        Text(updaterText).font(.system(size: 12)).foregroundColor(T.text2).lineLimit(2)
                        if case .available = updater.state { Button(L.t("upd.install")) { Task { await updater.install() } }.buttonStyle(PrimaryStyle()) }
                    }
                }
            }
            }.frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 12) {
            Card(pad: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("set.access")).font(.system(size: 11.5)).foregroundColor(T.text2)
                    ForEach(access.pending, id: \.self) { p in
                        HStack {
                            Tag(text: L.t("access.ask", p), kind: .warn)
                            Spacer(minLength: 8)
                            Button(L.t("access.allow")) { Access.shared.allow(p) }.buttonStyle(PrimaryStyle())
                            Button(L.t("access.deny")) { Access.shared.deny(p) }.buttonStyle(SoftStyle())
                        }
                    }
                    ForEach(access.allowed, id: \.self) { p in
                        HStack {
                            Label(p, systemImage: "folder").lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            IconButton(symbol: "xmark", help: L.t("act.remove")) { Access.shared.remove(p) }
                        }
                    }
                    Button(L.t("set.access.add")) {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let u = panel.url { Access.shared.allow(u.path) }
                    }.buttonStyle(SoftStyle())
                }
            }
            Card(pad: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("set.ext.title")).font(.system(size: 11.5)).foregroundColor(T.text2)
                    if ExtensionInstaller.detected.isEmpty { Text(L.t("set.ext.none")).font(.system(size: 12)).foregroundColor(T.text2) }
                    ForEach(ExtensionInstaller.detected) { b in
                        extRow(b.name, button: L.t(extDone.contains(b.id) || ExtensionInstaller.isInstalled(b) ? "set.ext.reinstall" : "set.ext.install")) {
                            if let why = ExtensionInstaller.install(b) { extNote = L.t("set.ext.fail") + " (" + why + ")" }
                            else { extDone.insert(b.id); extNote = L.t("set.ext.next", b.name); ExtensionInstaller.openExtensionsPage(b) }
                        }
                    }
                    if !extNote.isEmpty { Text(extNote).font(.system(size: 11.5)).foregroundColor(T.text2).fixedSize(horizontal: false, vertical: true) }
                    extRow(L.t("set.ext.bookmarklet"), button: copied == "bm" ? L.t("set.copied") : L.t("set.copy")) { copy(Bridge.shared.bookmarklet, "bm") }
                }
            }
            }.frame(maxWidth: .infinity, alignment: .topLeading) }
            HStack { Spacer(); Button(L.t("set.done"), action: done).buttonStyle(PrimaryStyle()).keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 880).background(T.bg).foregroundColor(T.text)
    }

    private func switchRow(_ label: String, _ b: Binding<Bool>) -> some View {
        HStack { Text(label).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 12); Toggle("", isOn: b).labelsHidden().toggleStyle(.switch).tint(T.acc) }
    }

    @State private var copied = ""
    @State private var extDone: Set<String> = []
    @State private var extNote = ""
    private func copy(_ s: String, _ k: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        copied = k
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if copied == k { copied = "" } }
    }
    private func extRow(_ label: String, button: String, action: @escaping () -> Void) -> some View {
        HStack { Text(label).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 12); Button(button, action: action).buttonStyle(SoftStyle()) }
    }

    private var updaterText: String {
        switch updater.state {
        case .idle: return ""
        case .checking: return L.t("upd.checking")
        case .upToDate: return L.t("upd.uptodate", updater.currentVersion)
        case .available(let v): return L.t("upd.available", v)
        case .downloading: return L.t("upd.downloading")
        case .failed(let m): return m
        }
    }
}
