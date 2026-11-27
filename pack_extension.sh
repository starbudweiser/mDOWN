#!/bin/zsh
# Emballe l'extension en assets/mDOWN.crx avec la clé privée (~/.config/mdown/extension-key.pem, jamais dans le dépôt).
# L'identifiant de l'extension (clé publique du manifeste) ne change donc jamais. Nécessite Brave ou Chrome pour emballer.
set -euo pipefail
cd "$(dirname "$0")"
KEY="$HOME/.config/mdown/extension-key.pem"
[ -f "$KEY" ] || { echo "Clé absente : $KEY (assets/mDOWN.crx conservé tel quel)" >&2; exit 0; }
BR=""; for b in "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; do [ -x "$b" ] && { BR="$b"; break; }; done
[ -n "$BR" ] || { echo "Ni Brave ni Chrome pour emballer : assets/mDOWN.crx conservé" >&2; exit 0; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp -R Extension "$T/src"
"$BR" --pack-extension="$T/src" --pack-extension-key="$KEY" --user-data-dir="$T/prof" >/dev/null 2>&1 || true
[ -f "$T/src.crx" ] && cp "$T/src.crx" assets/mDOWN.crx && echo "assets/mDOWN.crx à jour" || echo "Emballage échoué" >&2
