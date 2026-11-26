// mDOWN — design Flat Mat, arrondis doux (valeurs de la maquette validée), clair et sombre selon le Mac.
import SwiftUI
import AppKit

enum T {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            let d = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: d ? dark : light)
        })
    }
    static let bg = dyn(0xf4f1ec, 0x131316)
    static let card = dyn(0xffffff, 0x232327)
    static let ctl = dyn(0xebe6de, 0x2c2c31)
    static let line = dyn(0xe3ddd2, 0x303035)
    static let text = dyn(0x26231e, 0xf5f5f7)
    static let text2 = dyn(0x7b756a, 0x98989f)
    static let acc = dyn(0x26231e, 0x0a84ff)
    static let onAcc = dyn(0xf4f1ec, 0xffffff)
    static let ok = dyn(0x2f7d4a, 0x30d158)
    static let warn = dyn(0xa2650f, 0xff9f0a)
    static let err = dyn(0xc0392b, 0xff6961)
    static let thumb = dyn(0x26231e, 0x2c2c31)
    static let onThumb = dyn(0xf4f1ec, 0xf5f5f7)
    /// Le « m » du nom prend la couleur du logo.
    static let brand = dyn(0x0e9f87, 0x22c3a6)

    static let rCard: CGFloat = 10      // arrondis doux
    static let rCtl: CGFloat = 7
    static let rChip: CGFloat = 6
    static let rBar: CGFloat = 3
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// Nom de l'appli avec son « m » coloré.
struct BrandName: View {
    var size: CGFloat = 15
    var body: some View {
        (Text("m").foregroundColor(T.brand) + Text("DOWN").foregroundColor(T.text)).font(.system(size: size, weight: .bold))
    }
}

struct Card<Content: View>: View {
    var pad: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(pad)
            .background(T.card, in: RoundedRectangle(cornerRadius: T.rCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: T.rCard, style: .continuous).stroke(T.line, lineWidth: 1))
    }
}

struct Tag: View {
    enum Kind { case plain, ok, warn, err }
    var text: String
    var kind: Kind = .plain
    private var fg: Color { switch kind { case .plain: T.text2; case .ok: T.ok; case .warn: T.warn; case .err: T.err } }
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .semibold)).foregroundColor(fg).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background((kind == .plain ? T.ctl : fg.opacity(0.18)), in: RoundedRectangle(cornerRadius: T.rChip, style: .continuous))
    }
}

struct Bar: View {
    var value: Double
    var color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: T.rBar).fill(T.ctl)
                RoundedRectangle(cornerRadius: T.rBar).fill(color).frame(width: max(0, g.size.width * min(1, value)))
            }
        }.frame(height: 6)
    }
}

struct PrimaryStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 13, weight: .semibold)).foregroundColor(T.onAcc)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(T.acc.opacity(c.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: T.rCtl, style: .continuous))
    }
}

struct SoftStyle: ButtonStyle {
    var square = false
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 12.5, weight: .medium)).foregroundColor(T.text)
            .padding(.horizontal, square ? 0 : 12).padding(.vertical, square ? 0 : 6)
            .frame(width: square ? 30 : nil, height: square ? 30 : nil)
            .background(T.ctl.opacity(c.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: T.rCtl, style: .continuous))
    }
}

struct IconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12.5, weight: .semibold)) }
            .buttonStyle(SoftStyle(square: true)).help(help)
    }
}
