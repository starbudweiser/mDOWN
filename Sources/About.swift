// mDOWN — fenêtre « À propos » (modèle Socle : swift/AboutWindow.swift).
import AppKit

@MainActor
enum About {
    private static var window: NSWindow?
    private static let sideMargin: CGFloat = 28
    private static let textWidth: CGFloat = 300

    static func show() {
        if window == nil { window = makeWindow() }
        window?.center()
        NSApp.activate()
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
    }

    private final class Link: NSObject {
        @objc func open() { NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/starbudweiser")!) }
    }
    private static let link = Link()

    private static func label(_ text: String, size: CGFloat = 12, bold: Bool = false, secondary: Bool = false) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: text)
        f.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        f.textColor = secondary ? .secondaryLabelColor : .labelColor
        f.alignment = .center
        f.preferredMaxLayoutWidth = textWidth
        f.isSelectable = false
        f.translatesAutoresizingMaskIntoConstraints = false
        f.widthAnchor.constraint(lessThanOrEqualToConstant: textWidth).isActive = true
        return f
    }

    /// Nom de l'appli avec son « m » dans la couleur du logo.
    private static func nameLabel() -> NSTextField {
        let f = label("mDOWN", size: 17, bold: true)
        let s = NSMutableAttributedString(string: "mDOWN", attributes: [.font: NSFont.boldSystemFont(ofSize: 17), .foregroundColor: NSColor.labelColor])
        s.addAttribute(.foregroundColor, value: NSColor(srgbRed: 0x22 / 255, green: 0xc3 / 255, blue: 0xa6 / 255, alpha: 1), range: NSRange(location: 0, length: 1))
        f.attributedStringValue = s; f.alignment = .center
        return f
    }

    private static func makeWindow() -> NSWindow {
        let info = Bundle.main.infoDictionary ?? [:]
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 84).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 84).isActive = true
        let support = NSButton(title: L.t("about.support"), target: link, action: #selector(Link.open))
        support.isBordered = false
        support.font = .systemFont(ofSize: 12)
        let views: [NSView] = [
            icon, nameLabel(),
            label(L.t("about.version", info["CFBundleShortVersionString"] as? String ?? "?", info["CFBundleVersion"] as? String ?? "?"), secondary: true),
            label(L.t("about.collection"), secondary: true),
            label(L.t("about.tagline")),
            label(L.t("about.authors"), bold: true),
            label(L.t("about.license")),
            label(L.t("about.disclaimer"), secondary: true),
            support,
        ]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 12
        stack.setCustomSpacing(6, after: views[1]); stack.setCustomSpacing(4, after: views[2]); stack.setCustomSpacing(18, after: views[3])
        stack.edgeInsets = NSEdgeInsets(top: 28, left: sideMargin, bottom: 24, right: sideMargin)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: textWidth + 2 * sideMargin).isActive = true
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L.t("menu.about")
        w.isReleasedWhenClosed = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: content.topAnchor), stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                                     stack.trailingAnchor.constraint(equalTo: content.trailingAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        w.contentView = content
        content.layoutSubtreeIfNeeded()
        w.setContentSize(content.fittingSize)
        return w
    }
}
