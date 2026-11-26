// mDOWN — lien facultatif avec wCLAUDE (navigateur piloté par agent) : ses cookies, quand l'utilisateur l'a relié à mDOWN,
// servent à tester les plateformes qui exigent un compte (Vimeo, TikTok…). Sans wCLAUDE, rien ne change.
import Foundation

enum WClaude {
    /// Cookies de wCLAUDE pour cette adresse, au format Netscape ; rien si wCLAUDE n'est pas lancée, pas reliée ou réglage coupé.
    static func cookies(for url: String) async -> String? {
        guard UserDefaults.standard.object(forKey: "useWclaude") as? Bool ?? true else { return nil }
        let control = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/wCLAUDE/control.json")
        guard let d = try? Data(contentsOf: control), let info = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let port = info["controlPort"] as? Int, let token = info["token"] as? String,
              let q = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let u = URL(string: "http://127.0.0.1:\(port)/mdown/cookies?url=\(q)") else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 5)
        req.setValue(token, forHTTPHeaderField: "x-wclaude-token")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], obj["ok"] as? Bool == true,
              let text = obj["cookies"] as? String, text.split(separator: "\n").contains(where: { !$0.hasPrefix("#") || $0.hasPrefix("#HttpOnly_") }) else { return nil }
        return text
    }
}
