# mDOWN

## About

mDOWN is a light personal media downloader for macOS (part of the DESKTOP MAC TOOLKIT). It lives in the menu bar, keeps about 30–40 MB of memory, and its extraction engine (yt-dlp) updates itself without rebuilding the app: checksum-verified, self-tested, rolled back automatically if a platform test regresses. An agent can drive it through an MCP server, and a Chromium extension (Brave, Chrome, Edge, Helium…) sends pages to it.

## Utilisation

- **App** : collez un lien, ou clic droit « Télécharger avec mDOWN » dans le navigateur.
- **Agent (MCP)** : `claude mcp add mdown -s user -- "/Users/<vous>/Applications/Applications Personnelles/mDOWN.app/Contents/MacOS/mDOWN" --mcp`. Outils : `download_media`, `get_download`, `list_downloads`, `cancel_download`, `list_allowed_folders`, `request_folder_access`, `engine_status`, `update_engine`. Un agent n'écrit que dans les dossiers autorisés dans les réglages ; toute autre demande attend votre accord dans le menu de la barre des menus.
- **Extension Chromium** : `chrome://extensions` → mode développeur → « Charger l'extension non empaquetée » → dossier `mDOWN.app/Contents/Resources/Extension` (ou `Extension/`) ; puis coller le code d'association (Réglages de mDOWN → Copier) dans les options de l'extension.
- **Safari** : signet « Télécharger avec mDOWN » (Réglages → Copier), lien `mdown://download?url=…`.

## Build

`./build_app.sh` (installe la version locale) · `DEV=1 ./build_app.sh` (édition de développement, données séparées).

## Support / Soutenir

https://github.com/sponsors/starbudweiser
